# frozen_string_literal: true

require_relative "store"
require_relative "direct_evidence"

module SoulCore
  module ContinuityLab
    # Host-owned transport bindings around the existing experimental journal.
    # No client history is imported, and no model result grants write authority.
    class ChatGateway
      VERSION = "continuity_chat_gateway_a22_v1"
      MODEL = "soul-continuity-qwen"
      MAX_CONVERSATIONS = 16
      MAX_TURNS = 32
      ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/
      SESSION = /\Ac-[a-f0-9]{64}\z/
      STAGE = /\Astage-[a-f0-9]{32}\z/
      attr_reader :path

      # An fd-anchored private directory, not a general filesystem capability.
      class Directory
        attr_reader :path

        def initialize(path)
          child = nil
          unless path.is_a?(String) && path.valid_encoding? && path.start_with?("/") &&
                 !path.include?("\0") && path != "/" && File.expand_path(path) == path
            raise ValidationError, "canonical private directory required"
          end
          @path = path
          @fd = File.open("/", File::RDONLY)
          path.split("/").reject(&:empty?).each do |component|
            child = File.open(anchor(component), File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
            raise IntegrityError, "non-directory ancestor" unless child.stat.directory?
            @fd.close
            @fd = child
          end
          stat = @fd.stat
          raise IntegrityError, "owner-private directory required" unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o700
          @identity = [stat.dev, stat.ino]
        rescue Exception => error
          child&.close unless child&.closed?
          close
          raise IntegrityError, "private directory unavailable" if error.is_a?(SystemCallError)
          raise
        end

        def anchor(name)
          raise IntegrityError, "unsafe internal leaf" unless name.is_a?(String) && name.match?(/\A[A-Za-z0-9_.-]+\z/) && !%w[. ..].include?(name)
          "/proc/self/fd/#{@fd.fileno}/#{name}"
        end

        def verify!
          stat = File.lstat(path)
          raise IntegrityError, "private directory identity changed" unless !stat.symlink? && [stat.dev, stat.ino] == @identity &&
            stat.uid == Process.uid && (stat.mode & 0o777) == 0o700 && File.realpath(path) == path
        end

        def children = Dir.children("/proc/self/fd/#{@fd.fileno}")
        def sync = @fd.fsync
        def lock_initialization!
          raise Busy, "adapter initialization occupied" unless @fd.flock(File::LOCK_EX | File::LOCK_NB)
        end
        def close
          @fd&.close unless @fd&.closed?
        end

        def open_file(name, flags = File::RDONLY)
          before = File.lstat(anchor(name))
          unless before.file? && !before.symlink? && before.nlink == 1 && before.uid == Process.uid && (before.mode & 0o777) == 0o600
            raise IntegrityError, "unsafe private file"
          end
          file = File.open(anchor(name), flags | File::NOFOLLOW | File::NONBLOCK)
          stat = file.stat
          unless [stat.dev, stat.ino, stat.nlink] == [before.dev, before.ino, 1]
            file.close
            raise IntegrityError, "private file changed"
          end
          file
        end

        def read(name, limit = 65_536)
          file = open_file(name)
          text = file.read(limit + 1)
          raise IntegrityError, "private record exceeds bound" if text.bytesize > limit
          ContinuityLab.parse(text)
        ensure
          file&.close
        end

        def write(name, data)
          File.open(anchor(name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
            file.write(ContinuityLab.encode(data) + "\n")
            file.flush
            file.fsync
          end
          sync
        end
      end

      def self.binding(executor, corpus)
        Retrieval.validate_corpus!(corpus)
        raise ValidationError, "too many source documents" if corpus.length > DirectEvidence::MAX_DOCUMENTS
        # Full metadata overhead is checked again by DirectEvidence before calls.
        raise ValidationError, "corpus too large" if ContinuityLab.encode(corpus).bytesize > DirectEvidence::MAX_BYTES
        { "version" => VERSION, "config" => executor.config.to_h,
          "profile" => executor.profile, "corpus" => corpus,
          "corpus_digest" => ContinuityLab.digest(corpus),
          "implementation" => implementation_hashes }
      end

      def self.implementation_hashes
        paths = Dir.glob(File.join(__dir__, "*.{rb,gbnf}")) + [File.expand_path("../../../scripts/continuity-lab-worker.rb", __dir__)]
        paths.sort.to_h { |file| [File.basename(file), Digest::SHA256.file(file).hexdigest] }
      end

      def self.create(path:, executor:, corpus: [])
        raise ValidationError, "canonical new root required" unless path.is_a?(String) && File.expand_path(path) == path && path != "/"
        raise Conflict, "root already exists" if File.exist?(path) || File.symlink?(path)
        # Require an explicitly prepared private parent and anchor creation to
        # its open descriptor, just as conversation staging is anchored below.
        parent = Directory.new(File.dirname(path))
        parent.lock_initialization!
        name = File.basename(path)
        raise Conflict, "root already exists" if parent.children.include?(name)
        value = binding(executor, corpus)
        stage = "stage-#{SecureRandom.hex(16)}"
        Dir.mkdir(parent.anchor(stage), 0o700)
        parent.verify!
        directory = Directory.new(File.join(File.dirname(path), stage))
        directory.write("adapter.json", value)
        directory.write("lock", {})
        directory.sync
        parent.verify!
        # Cooperating initializers serialize on the parent; never deliberately
        # replace even an empty destination. Failed staging stays inspectable.
        raise Conflict, "root already exists" if parent.children.include?(name)
        File.rename(parent.anchor(stage), parent.anchor(name))
        parent.sync
        true
      ensure
        directory&.close
        parent&.close
      end

      def initialize(path:, executor:)
        @path, @executor, @mutex = path, executor, Mutex.new
        @root = Directory.new(path)
        @manifest = @root.read("adapter.json")
        unless @manifest.is_a?(Hash) && @manifest == self.class.binding(executor, @manifest.fetch("corpus"))
          raise IntegrityError, "adapter configuration or implementation changed"
        end
        @lock = @root.open_file("lock", File::RDWR)
        @lock_identity = [@lock.stat.dev, @lock.stat.ino]
        inventory!
      rescue Exception
        close
        raise
      end

      def close
        @lock&.close unless @lock&.closed?
        @root&.close
      end

      def self.validate_input!(conversation_id, messages)
        unless conversation_id.is_a?(String) && conversation_id.valid_encoding? && ID.match?(conversation_id) &&
               !%w[new null undefined].include?(conversation_id.downcase) && messages.is_a?(Array) &&
               messages.length.odd? && messages.length.between?(1, MAX_TURNS * 2 - 1) &&
               ContinuityLab.encode(messages).bytesize <= 131_072
          raise ValidationError, "invalid conversation or bounded history"
        end
        messages.each_with_index do |message, index|
          unless message.is_a?(Hash) && message.keys.sort == %w[content role] &&
                 message["role"] == (index.even? ? "user" : "assistant") &&
                 message["content"].is_a?(String) && message["content"].encoding == Encoding::UTF_8 &&
                 message["content"].valid_encoding? && message["content"].bytesize.between?(1, 16_384)
            raise ValidationError, "only complete text history is supported"
          end
        end
      end

      def complete(conversation_id:, messages:)
        self.class.validate_input!(conversation_id, messages)
        locked = @mutex.try_lock
        raise Busy, "adapter occupied" unless locked
        file_locked = @lock.flock(File::LOCK_EX | File::LOCK_NB)
        raise Busy, "adapter occupied" unless file_locked
        inventory!
        name = "c-#{Digest::SHA256.hexdigest(conversation_id)}"
        unless @root.children.include?(name)
          raise Conflict, "history import and branching are not supported" unless messages.length == 1
          create_session(name, conversation_id)
        end
        session = Directory.new(File.join(path, name))
        metadata = session.read("binding.json")
        unless metadata.keys.sort == %w[conversation_id created root_digest version] && metadata["version"] == VERSION &&
               metadata["conversation_id"] == conversation_id && metadata["root_digest"] == ContinuityLab.digest(@manifest) &&
               metadata["created"].is_a?(Integer) && metadata["created"].positive? && session.children.sort == %w[binding.json worker]
          raise IntegrityError, "invalid conversation binding"
        end
        worker = Directory.new(File.join(session.path, "worker"))
        raise IntegrityError, "unexpected worker state" unless worker.children == ["store"]
        store_path = File.join(worker.path, "store")
        state = snapshot(store_path)
        events = state.fetch("events").values
        unless events.each_with_index.all? { |event, index| event["event_id"] == event_id(index) }
          raise IntegrityError, "foreign event in adapter lineage"
        end
        index = messages.length / 2
        raise Conflict, "missing or rewritten history" if index > events.length
        messages[0...-1].each_slice(2).with_index do |(question, answer), prior|
          event = events.fetch(prior)
          unless event["state"] == "complete" && event["reason"] == "reply" &&
                 event["content"] == question["content"] && event["reply"] == answer["content"]
            raise Conflict, "history differs from durable results"
          end
        end
        event = events[index]
        content = messages.last.fetch("content")
        raise Conflict, "edits and regeneration are not supported" if event && event["content"] != content
        replayed = !!(event && Store::TERMINAL.include?(event["state"]))
        unless replayed
          session.verify!
          worker.verify!
          @root.verify!
          # Pending intent recovery is delegated to the existing runtime, which
          # blocks an unresolved generation instead of repeating it.
          @executor.run(state_directory: worker.path, event_id: event_id(index), content: content)
          state = snapshot(store_path)
          event = state.fetch("events").fetch(event_id(index))
        end
        unless event["state"] == "complete" && event["reason"] == "reply"
          raise Conflict, "turn not complete; inspect retained state before continuing"
        end
        {
          "id" => "chatcmpl-#{ContinuityLab.digest([state.fetch('lineage_id'), event_id(index)])[0, 32]}",
          "created" => metadata.fetch("created"), "content" => event.fetch("reply"),
          "soul" => { "version" => VERSION, "lineage_id" => state.fetch("lineage_id"),
            "event_id" => event_id(index), "replayed" => replayed, "verified_calculation" => false,
            "profile" => @executor.profile, "timestamp_scope" => "conversation_created",
            "context" => { "max_recent_exchanges" => 3, "max_recent_encoded_bytes" => 4096,
              "input_token_ceiling" => 3072, "output_token_ceiling" => 768,
              "history_policy" => "full_transport_validation_bounded_model_projection" } }
        }
      rescue JSON::ParserError, KeyError, SystemCallError, IOError => error
        raise IntegrityError, "adapter storage unavailable: #{error.class}"
      ensure
        worker&.close
        session&.close
        @lock.flock(File::LOCK_UN) if file_locked
        @mutex.unlock if locked
      end

      private

      def event_id(index) = format("turn-%04d", index + 1)

      def inventory!
        @root.verify!
        raise IntegrityError, "adapter manifest changed" unless @root.read("adapter.json") == @manifest
        file = @root.open_file("lock")
        raise IntegrityError, "adapter lock changed" unless [file.stat.dev, file.stat.ino] == @lock_identity
        names = @root.children
        raise IntegrityError, "unexpected adapter entry" unless (names - %w[adapter.json lock]).all? { |name| SESSION.match?(name) || STAGE.match?(name) }
        raise QuotaExceeded, "adapter conversation quota reached" if names.count { |name| SESSION.match?(name) || STAGE.match?(name) } > MAX_CONVERSATIONS
      ensure
        file&.close
      end

      def create_session(name, conversation_id)
        count = @root.children.count { |child| SESSION.match?(child) || STAGE.match?(child) }
        raise QuotaExceeded, "adapter conversation quota reached" if count >= MAX_CONVERSATIONS
        stage = "stage-#{SecureRandom.hex(16)}"
        Dir.mkdir(@root.anchor(stage), 0o700)
        staged = Directory.new(File.join(path, stage))
        staged.write("binding.json", { "version" => VERSION, "conversation_id" => conversation_id,
          "created" => Time.now.to_i, "root_digest" => ContinuityLab.digest(@manifest) })
        Dir.mkdir(staged.anchor("worker"), 0o700)
        store = Store.create(path: File.join(staged.path, "worker", "store"), config: @executor.config, corpus: @manifest.fetch("corpus"))
        store.close
        store = nil
        worker = Directory.new(File.join(staged.path, "worker"))
        worker.sync
        staged.sync
        @root.verify!
        raise Conflict, "conversation destination exists" if @root.children.include?(name)
        File.rename(@root.anchor(stage), @root.anchor(name))
        @root.sync
      ensure
        store&.close
        worker&.close
        staged&.close
      end

      def snapshot(store_path)
        store = Store.open(path: store_path, config: @executor.config)
        result = store.snapshot
        raise IntegrityError, "corpus binding changed" unless result["corpus"] == @manifest["corpus"]
        result
      ensure
        store&.close
      end
    end
  end
end
