# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "bounded_command_runner"

module SoulCore
  class SelfAugmentationService
    SCHEMA = "soul.self_augmentation.proposal.v1"
    ROOT = File.join("Soul", "augmentation", "proposals")
    CONFIRMATION = "CREATE_SELF_AUGMENTATION_PROPOSAL"
    MAX_PATHS = 5_000
    MAX_FILE_BYTES = 256 * 1024
    MAX_TOTAL_BYTES = 4 * 1024 * 1024
    MAX_RECORDS = 100
    EXCLUDED = %r{(?:\A\.git/|(?:\A|/)(?:\.env(?:\.[^/]*)?|secrets?|credentials?)(?:/|\z)|\A(?:Soul/(?:runtime|memory|config|augmentation|host_improvement)/|models/)|\.(?:pem|key)\z)}i

    def initialize(root: Dir.pwd, clock: -> { Time.now }, runner: BoundedCommandRunner.new)
      @root = File.expand_path(root)
      @clock = clock
      @runner = runner
    end

    def census
      head = git("rev-parse", "HEAD").strip
      raise "Git HEAD is unavailable" unless head.match?(/\A[a-f0-9]{40,64}\z/)
      status = git("status", "--short", "--untracked-files=no").lines.map(&:strip).reject(&:empty?).first(1_000)
      paths = git("ls-files", "-z").split("\0", -1).reject(&:empty?)
      raise "tracked path limit exceeded" if paths.length > MAX_PATHS

      total = 0
      text_files = binary_files = excluded = symlinks = 0
      extensions = Hash.new(0)
      accepted = []
      content_limit_reached = false
      paths.sort.each do |relative|
        if relative.match?(EXCLUDED)
          excluded += 1
          next
        end
        path = File.expand_path(relative, @root)
        raise "tracked path escaped repository" unless path.start_with?(@root + File::SEPARATOR)
        stat = File.lstat(path)
        if stat.symlink?
          symlinks += 1
          next
        end
        next unless stat.file?
        extension = File.extname(relative).downcase.sub(/\A\./, "")
        extensions[extension.empty? ? "none" : extension] += 1
        if stat.size > MAX_FILE_BYTES
          binary_files += 1
          next
        end
        content = File.binread(path, MAX_FILE_BYTES + 1).to_s
        if content.include?("\0")
          binary_files += 1
          next
        end
        if total + content.bytesize > MAX_TOTAL_BYTES
          content_limit_reached = true
          break
        end
        total += content.bytesize
        text_files += 1
        accepted << [relative, Digest::SHA256.hexdigest(content)]
      rescue Errno::ENOENT
        next
      end
      evidence = {"head"=>head,"dirty_paths"=>status,"files"=>accepted}
      raise "tracked symbolic links require separate human review" if symlinks.positive?
      report = {
        "schema_version"=>"soul.self_augmentation.census.v1", "generated_at"=>@clock.call.iso8601,
        "head"=>head, "tracked_path_count"=>paths.length, "text_file_count"=>text_files,
        "binary_or_oversize_count"=>binary_files, "excluded_count"=>excluded, "symlink_count"=>symlinks,
        "content_bytes_read"=>total, "content_limit_reached"=>content_limit_reached, "dirty_tracked_paths"=>status, "languages"=>extensions.sort_by { |_k,v| -v }.first(20).to_h,
        "verifier_count"=>paths.count { |path| path.start_with?("scripts/verify-") },
        "source_digest"=>digest(evidence), "read_only"=>true, "bounded"=>true
      }
      success({"census"=>report, "proposals"=>inventory.fetch("data")})
    rescue RuntimeError => error
      failed(error.message)
    end

    def preview(objective:, why_not_skill:)
      objective = validated_text(objective, "objective")
      why = validated_text(why_not_skill, "why_not_skill")
      census_result = census
      return census_result unless census_result["ok"]
      report = census_result.dig("data", "census")
      proposal = build_proposal(objective, why, report)
      success({"proposal"=>proposal,"expected_digest"=>proposal_digest(proposal),"confirmation_phrase"=>CONFIRMATION,"read_only"=>true})
    rescue ArgumentError => error
      awaiting(error.message)
    end

    def create_proposal(objective:, why_not_skill:, confirmation:, expected_digest:)
      return awaiting("preview digest is required") if expected_digest.to_s.empty?
      return blocked("exact confirmation is required") unless confirmation.to_s == CONFIRMATION
      current = preview(objective: objective, why_not_skill: why_not_skill)
      return current unless current["ok"]
      proposal = current.dig("data", "proposal")
      return blocked("repository evidence changed; preview again") unless secure_equal?(proposal_digest(proposal), expected_digest.to_s)
      ensure_storage_root!
      directory = packet_directory(proposal.fetch("proposal_id"))
      return blocked("augmentation proposal already exists") if File.exist?(directory) || File.symlink?(directory)
      Dir.mkdir(directory, 0o700)
      atomic_write(File.join(directory, "proposal.json"), JSON.pretty_generate(proposal) + "\n")
      atomic_write(File.join(directory, "REVIEW.md"), review_markdown(proposal))
      blocked("augmentation proposal awaits human review", data: {"proposal"=>proposal,"packet"=>relative(directory),"implementation_started"=>false}, mutation: "self_augmentation_proposal_created")
    rescue Errno::EEXIST
      blocked("augmentation proposal already exists")
    end

    def inventory(limit: MAX_RECORDS)
      ensure_storage_root!
      maximum = [Integer(limit), MAX_RECORDS].min
      records = Dir.children(storage_root).sort.reverse.first(maximum).filter_map { |id| read_proposal(id) }
      success({"records"=>records,"count"=>records.length,"limit"=>maximum,"read_only"=>true})
    end

    private

    def git(*args)
      result = @runner.run("git", *args, timeout_seconds: 20, max_output_bytes: MAX_TOTAL_BYTES + 512 * 1024, chdir: @root)
      raise "Git census command failed safely" unless result.success? && !result.truncated
      result.stdout
    end

    def build_proposal(objective, why, report)
      seed = digest({"objective"=>objective,"why_not_skill"=>why,"source_digest"=>report.fetch("source_digest")})
      {
        "schema_version"=>SCHEMA,"proposal_id"=>"aug_#{seed[0,16]}","created_at"=>@clock.call.iso8601,
        "objective"=>objective,"why_not_skill"=>why,"source_digest"=>report.fetch("source_digest"),"head"=>report.fetch("head"),
        "suggested_scope"=>["prepare an isolated candidate change", "add deterministic verification", "document compatibility and rollback"],
        "prohibited_scope"=>["modify production code from this proposal", "invoke Codex automatically", "create a worktree", "merge or deploy"],
        "implementation_authorized"=>false,"human_review_required"=>true,"stage"=>"proposal_review","risk_class"=>"class_4"
      }
    end

    def review_markdown(proposal)
      <<~MD
        # Self Augmentation Proposal Review

        - Proposal: `#{proposal.fetch("proposal_id")}`
        - Objective: #{proposal.fetch("objective")}
        - Why this is not a skill: #{proposal.fetch("why_not_skill")}
        - Source revision: `#{proposal.fetch("head")}`
        - Implementation authorized: **no**

        ## Human checklist

        - [ ] The objective requires a core-system change rather than a bounded skill.
        - [ ] Scope, compatibility, migration, rollback, and tests are explicit.
        - [ ] Private data and credentials are excluded.
        - [ ] A separate implementation brief is approved before code changes.
      MD
    end

    def validated_text(value, name)
      text = value.to_s.strip
      raise ArgumentError, "#{name} must contain 20 to 1000 characters" unless text.length.between?(20, 1000)
      text
    end

    def storage_root = File.join(@root, ROOT)
    def ensure_storage_root!
      cursor = @root
      ROOT.split(File::SEPARATOR).each do |component|
        cursor = File.join(cursor, component)
        raise "augmentation path must not traverse a symlink" if File.symlink?(cursor)
        Dir.mkdir(cursor, 0o700) unless File.exist?(cursor)
        raise "augmentation path component must be a directory" unless File.directory?(cursor)
      end
    end
    def packet_directory(id)
      raise ArgumentError, "proposal_id is invalid" unless id.to_s.match?(/\Aaug_[a-f0-9]{16}\z/)
      File.join(storage_root, id.to_s)
    end
    def read_proposal(id)
      directory = packet_directory(id)
      return nil unless File.directory?(directory) && !File.symlink?(directory)
      path = File.join(directory, "proposal.json")
      return nil unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_FILE_BYTES
      JSON.parse(File.binread(path, MAX_FILE_BYTES))
    rescue ArgumentError, JSON::ParserError, Errno::ENOENT
      nil
    end
    def atomic_write(path, content)
      raise "packet target already exists" if File.exist?(path) || File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content); file.flush; file.fsync }
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if defined?(temporary) && File.file?(temporary)
    end
    def relative(path) = path.delete_prefix(@root + File::SEPARATOR)
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def proposal_digest(proposal) = digest(proposal.reject { |key, _value| key == "created_at" })
    def secure_equal?(left, right) = left.bytesize == right.bytesize && left.bytes.zip(right.bytes).reduce(0) { |memo,pair| memo | (pair[0] ^ pair[1]) }.zero?
    def success(data) = {"ok"=>true,"lifecycle_state"=>"complete","data"=>data,"mutation"=>"none"}
    def awaiting(reason) = {"ok"=>false,"lifecycle_state"=>"awaiting_input","reason"=>reason,"mutation"=>"none"}
    def blocked(reason, data: nil, mutation: "none")
      result={"ok"=>false,"lifecycle_state"=>"blocked_for_human_review","reason"=>reason,"mutation"=>mutation}; result["data"]=data if data; result
    end
    def failed(reason) = {"ok"=>false,"lifecycle_state"=>"failed","reason"=>reason,"mutation"=>"none"}
  end
end
