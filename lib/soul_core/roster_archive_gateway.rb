# frozen_string_literal: true
require_relative "roster_memory_gateway"

module SoulCore
  # Conversations are loaded on demand. A shared, bucketed append-only registry
  # retains request identity even when its conversation is cold. No pruning,
  # background worker, or implicit retry is part of this storage format.
  class RosterArchiveGateway
    Directory = RosterConversationGateway::Directory
    Refused = RosterConversationGateway::Refused
    G = RosterMemoryGateway
    ID = RosterConversationGateway::ID
    BUCKET_LIMIT = 4096

    def self.digest(value) = G.digest(value)
    def self.file_digest(io)
      value=Digest::SHA256.new
      io.rewind
      while (chunk=io.read(65_536))
        value.update(chunk)
      end
      value.hexdigest
    end
    def self.capacity_policy = "per_conversation_with_global_replay_registry"
    def self.manifest(owner)
      {"version"=>"roster_archive_v1", "conversation_binding"=>G.manifest(owner),
       "implementation_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
       "conversation_record_limit"=>G::LIMIT, "registry_bucket_limit"=>BUCKET_LIMIT}
    end

    def self.create(path:, owner:)
      publish(path: path, owner: owner) { |_store| nil }
    end

    # Build an unpublished store, retaining every source byte and original
    # terminal result. Publication is one directory rename after verification.
    def self.import(source:, path:, owner:, expected_manifest_sha256:)
      old = G.new(path: source, owner: owner)
      raise Refused, "source journal busy" unless old.instance_variable_get(:@lock).flock(File::LOCK_EX | File::LOCK_NB)
      old.send(:load!)
      manifest = old.instance_variable_get(:@manifest)
      raise Refused, "source manifest changed" unless digest(manifest) == expected_manifest_sha256
      attempts = old.instance_variable_get(:@attempts)
      raise Refused, "unfinished source requires review" unless attempts.values.all? { |a| %w[complete failed canceled].include?(a["state"]) }
      records = old.instance_variable_get(:@records)
      source_root = old.instance_variable_get(:@root)
      source_hashes = source_root.children.sort.to_h do |name|
        f = source_root.open_file(name)
        begin; [name, file_digest(f)]; ensure; f.close; end
      end
      result = publish(path: path, owner: owner) do |store|
        Dir.mkdir(store.instance_variable_get(:@root).anchor("legacy"), 0o700)
        legacy = Directory.new(File.join(store.instance_variable_get(:@root).path, "legacy"))
        begin
          source_hashes.each do |name, hash|
            input = source_root.open_file(name)
            begin
              File.open(legacy.anchor(name), File::WRONLY|File::CREAT|File::EXCL|File::NOFOLLOW, 0o600) do |output|
                IO.copy_stream(input, output); output.flush; output.fsync
              end
              copied = legacy.open_file(name)
              begin; raise Refused, "archive copy mismatch" unless file_digest(copied) == hash; ensure; copied.close; end
            ensure
              input.close
            end
          end
          legacy.sync
        ensure
          legacy.close
        end
        attempts.values.group_by { |a| a.fetch("input").fetch("conversation_id") }.each do |conversation, group|
          ids = group.map { |a| a.fetch("input").fetch("request_id") }
          subset = records.select { |r| ids.include?(r["request_id"]) }
          store.send(:create_conversation!, conversation, subset: subset, source_manifest: manifest)
          group.each { |a| store.send(:reserve!, a.fetch("input")) }
          inner = store.send(:open_conversation, conversation)
          begin
            inner.send(:load!)
            imported = inner.instance_variable_get(:@attempts)
            group.each do |a|
              raise Refused, "imported attempt changed" unless imported.fetch(a["input"]["request_id"]) == a
            end
          ensure
            inner.close
          end
        end
        source_root.verify!
        source_hashes.each do |name, hash|
          f = source_root.open_file(name)
          begin; raise Refused, "source bytes changed" unless file_digest(f) == hash; ensure; f.close; end
        end
        {"manifest_sha256"=>expected_manifest_sha256, "files"=>source_hashes,
         "records"=>records.length, "conversations"=>attempts.values.map { |a| a["input"]["conversation_id"] }.uniq.length,
         "requests"=>attempts.length}
      end
      {"state"=>"complete", "source_preserved"=>true, "source"=>result}
    ensure
      old&.close
    end

    def initialize(path:, owner:, memory: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, unpublished: false)
      @owner, @memory, @clock, @mutex = owner, memory, clock, Mutex.new
      @root = Directory.new(path)
      @manifest = @root.read("roster.json")
      raise Refused, "archive binding changed" unless @manifest == self.class.manifest(owner)
      @lock = @root.open_file("lock", File::RDWR)
      @lock_identity = [@lock.stat.dev, @lock.stat.ino]
      @conversations = Directory.new(File.join(path, "conversations"))
      @requests = Directory.new(File.join(path, "requests"))
      @keys = Directory.new(File.join(path, "request-keys"))
      raise Refused, "registry buckets missing" unless @requests.children.sort == (0...256).map { |i| format("b-%02x", i) }
      unless unpublished
        @ready = @root.read("ready.json")
        raise Refused, "archive not published" unless @ready.keys.sort == %w[manifest_sha256 source] && @ready["manifest_sha256"] == self.class.digest(@manifest)
        verify_legacy!
        verify!
      end
    rescue Exception
      close
      raise
    end

    def close
      @lock&.close unless @lock&.closed?
      @keys&.close; @requests&.close; @conversations&.close; @root&.close
    end

    def complete(conversation_id:, request_id:, adapter:, messages:, deadline:, cancel: -> { false })
      unless [conversation_id, request_id].all? { |s| s.is_a?(String) && ID.match?(s) } && adapter.instance_of?(RosterChatAdapter)
        raise Refused, "bounded identities and explicit adapter required"
      end
      ContinuityLab::ChatGateway.validate_input!(conversation_id, messages)
      adapter.payload(messages: messages)
      raise Refused, "canceled or deadline invalid" unless deadline.is_a?(Numeric) && deadline.finite? && (deadline-@clock.call).between?(0.001,180) && !cancel.call
      input = {"conversation_id"=>conversation_id,"request_id"=>request_id,"adapter"=>adapter.binding,"messages"=>JSON.parse(JSON.generate(messages))}
      locked = @mutex.try_lock
      raise Refused, "archive writer busy" unless locked
      file_locked = @lock.flock(File::LOCK_EX|File::LOCK_NB)
      raise Refused, "archive root busy" unless file_locked
      verify!
      registration = registration_for(request_id)
      expected = reservation(input)
      raise Refused, "request identity reused with different input" if registration && registration.slice(*expected.keys) != expected
      name = self.class.digest(conversation_id)
      if exists?(@conversations, name)
        inner = open_conversation(conversation_id)
      else
        raise Refused, "registered conversation missing" if registration
        create_conversation!(conversation_id)
        inner = open_conversation(conversation_id)
      end
      raise Refused, "conversation journal busy" unless inner.instance_variable_get(:@lock).flock(File::LOCK_EX|File::LOCK_NB)
      inner.send(:load!)
      attempt = inner.instance_variable_get(:@attempts)[request_id]
      raise Refused, "request registry missing" if attempt && !registration
      raise Refused, "interrupted admission requires review" if registration && !attempt
      # Reservation is durable before any model work. An interrupted reservation
      # is retained and blocks retries rather than being silently reconstructed.
      reserve!(input) unless registration
      inner.complete(conversation_id: conversation_id, request_id: request_id, adapter: adapter,
        messages: messages, deadline: deadline, cancel: cancel)
    ensure
      inner&.close
      @lock.flock(File::LOCK_UN) if file_locked
      @mutex.unlock if locked
    end

    private

    def self.publish(path:, owner:)
      raise Refused, "canonical new archive path required" unless path.is_a?(String) && File.expand_path(path)==path && path!="/"
      parent = Directory.new(File.dirname(path)); parent.lock_initialization!
      leaf = File.basename(path)
      raise Refused, "archive destination exists" if parent.children.include?(leaf)
      stage = "archive-stage-#{SecureRandom.hex(16)}"
      Dir.mkdir(parent.anchor(stage),0o700); staged_path=File.join(File.dirname(path),stage)
      directory=Directory.new(staged_path)
      directory.write("roster.json",manifest(owner)); directory.write("lock",{})
      %w[conversations requests request-keys].each { |n| Dir.mkdir(directory.anchor(n),0o700) }
      requests=Directory.new(File.join(staged_path,"requests"))
      256.times { |i| Dir.mkdir(requests.anchor(format("b-%02x",i)),0o700) }; requests.sync; requests.close
      store=new(path:staged_path,owner:owner,unpublished:true)
      source=yield store
      directory.write("ready.json",{"manifest_sha256"=>digest(manifest(owner)),"source"=>source})
      store.close; store=nil
      checked=new(path:staged_path,owner:owner); checked.close
      directory.verify!; parent.verify!
      raise Refused,"archive destination appeared" if parent.children.include?(leaf)
      File.rename(parent.anchor(stage),parent.anchor(leaf)); parent.sync
      source
    ensure
      store&.close; directory&.close; parent&.close
    end
    private_class_method :publish

    def verify!
      @root.verify!; @requests.verify!; @keys.verify!; @conversations.verify!
      raise Refused,"archive manifest changed" unless @root.read("roster.json")==@manifest && @root.read("ready.json")==@ready
      f=@root.open_file("lock")
      raise Refused,"archive lock changed" unless [f.stat.dev,f.stat.ino]==@lock_identity
      expected=%w[roster.json lock ready.json conversations requests request-keys]
      expected << "legacy" if @ready["source"]
      raise Refused,"unexpected archive root entry" unless @root.children.sort==expected.sort
    ensure
      f&.close
    end

    def verify_legacy!
      source=@ready["source"]
      return if source.nil?
      raise Refused,"invalid source archive receipt" unless source.is_a?(Hash) && source.keys.sort==%w[conversations files manifest_sha256 records requests] && source["files"].is_a?(Hash) && source["files"].length<=G::LIMIT+2
      d=Directory.new(File.join(@root.path,"legacy"))
      raise Refused,"source archive files changed" unless d.children.sort==source["files"].keys.sort
      source["files"].each do |name,hash|
        f=d.open_file(name)
        begin; raise Refused,"source archive bytes changed" unless self.class.file_digest(f)==hash; ensure; f.close; end
      end
      raise Refused,"source archive identity changed" unless self.class.digest(d.read("roster.json"))==source["manifest_sha256"]
    ensure
      d&.close
    end

    def create_conversation!(id, subset: [], source_manifest: nil)
      @conversations.verify!
      name=self.class.digest(id)
      raise Refused,"conversation already exists" if exists?(@conversations, name)
      stage="stage-#{SecureRandom.hex(16)}"
      Dir.mkdir(@conversations.anchor(stage),0o700)
      path=File.join(@conversations.path,stage); envelope=Directory.new(path)
      G.create(path:File.join(path,"journal"),owner:@owner)
      inner=G.new(path:File.join(path,"journal"),owner:@owner,memory:@memory,clock:@clock)
      inner.send(:load!)
      unless subset.empty?
        inner.send(:append!,"transition","archive-import",{"source_manifest_sha256"=>self.class.digest(source_manifest),
          "source_tail_sha256"=>self.class.digest(subset.last),"imported_records"=>subset.length,
          "payloads_sha256"=>self.class.digest(subset.map { |r| r.values_at("state","request_id","data") })})
        subset.each { |r| inner.send(:append!,r["state"],r["request_id"],r["data"]) }
        inner.send(:load!)
      end
      descriptor={"conversation_id"=>id,"journal_manifest_sha256"=>self.class.digest(inner.instance_variable_get(:@manifest))}
      envelope.write("descriptor.json",descriptor)
      inner.close;inner=nil;envelope.verify!;@conversations.verify!
      raise Refused,"conversation destination appeared" if exists?(@conversations, name)
      File.rename(@conversations.anchor(stage),@conversations.anchor(name));@conversations.sync
    ensure
      inner&.close;envelope&.close
    end

    def open_conversation(id)
      envelope=Directory.new(File.join(@conversations.path,self.class.digest(id)))
      raise Refused,"conversation envelope changed" unless envelope.children.sort==%w[descriptor.json journal]
      descriptor=envelope.read("descriptor.json")
      raise Refused,"conversation identity changed" unless descriptor.keys.sort==%w[conversation_id journal_manifest_sha256] && descriptor["conversation_id"]==id
      inner=G.new(path:File.join(envelope.path,"journal"),owner:@owner,memory:@memory,clock:@clock)
      raise Refused,"conversation journal replaced" unless self.class.digest(inner.instance_variable_get(:@manifest))==descriptor["journal_manifest_sha256"]
      inner
    rescue Exception
      inner&.close
      raise
    ensure
      envelope&.close
    end

    def exists?(directory, name)
      File.lstat(directory.anchor(name))
      true
    rescue Errno::ENOENT
      false
    end

    def reservation(input)
      {"request_id"=>input.fetch("request_id"),"conversation_id"=>input.fetch("conversation_id"),"input_sha256"=>self.class.digest(input)}
    end

    def bucket(request_id)
      Directory.new(File.join(@requests.path,"b-#{self.class.digest(request_id)[0,2]}"))
    end

    def registry(request_id)
      d=bucket(request_id);names=d.children.sort
      raise Refused,"registry bucket oversized" if names.length>BUCKET_LIMIT
      previous=self.class.digest([@manifest,File.basename(d.path)]);seen={}
      names.each_with_index.map do |name,index|
        raise Refused,"registry gap" unless name==format("r-%06d.json",index+1)
        r=d.read(name,4096)
        unless r.is_a?(Hash) && r.keys.sort==%w[conversation_id input_sha256 previous request_id sequence] &&
            r["sequence"]==index+1 && r["previous"]==previous && [r["request_id"],r["conversation_id"]].all? { |v| v.is_a?(String)&&ID.match?(v) } &&
            r["input_sha256"].is_a?(String) && /\A[a-f0-9]{64}\z/.match?(r["input_sha256"]) &&
            "b-#{self.class.digest(r['request_id'])[0,2]}"==File.basename(d.path) && !seen[r["request_id"]]
          raise Refused,"registry binding changed"
        end
        seen[r["request_id"]]=true;previous=self.class.digest(r);r
      end
    ensure
      d&.close
    end

    def registration_for(request_id)
      entry=registry(request_id).find { |r| r["request_id"]==request_id }
      name=self.class.digest(request_id)+".json"
      key=exists?(@keys,name) ? @keys.read(name,4096) : nil
      if entry || key
        unless entry && key && key==entry.slice("request_id","conversation_id","input_sha256")
          raise Refused,"incomplete or changed request reservation"
        end
      end
      entry
    end

    def reserve!(input)
      raise Refused,"request already reserved" if registration_for(input.fetch("request_id"))
      entries=registry(input.fetch("request_id"))
      raise Refused,"registry bucket quota" if entries.length>=BUCKET_LIMIT
      d=bucket(input["request_id"])
      previous=entries.empty? ? self.class.digest([@manifest,File.basename(d.path)]) : self.class.digest(entries.last)
      @keys.write(self.class.digest(input["request_id"])+".json",reservation(input))
      d.write(format("r-%06d.json",entries.length+1),reservation(input).merge("sequence"=>entries.length+1,"previous"=>previous))
    ensure
      d&.close
    end
  end
end
