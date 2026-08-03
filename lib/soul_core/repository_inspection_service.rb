# frozen_string_literal: true

require "open3"
require "pathname"
require "time"
require "timeout"

module SoulCore
  class RepositoryInspectionService
    ROOTS_ENV = "SOUL_REPOSITORY_INSPECT_ROOTS"
    DEFAULT_ROOTS = "project=."
    ROOT_ID = /\A[a-z][a-z0-9_-]{0,31}\z/
    MAX_ROOTS = 8
    MAX_STATUS_ENTRIES = 100
    MAX_LOG_ENTRIES = 10
    MAX_DIFF_BYTES = 24 * 1024
    MAX_COMMAND_BYTES = 64 * 1024
    COMMAND_TIMEOUT_SECONDS = 5
    GIT_PATHS = %w[/usr/bin/git /bin/git].freeze
    SECRET_PATH = /(?:\A|\/)(?:\.env(?:\..*)?|\.netrc|\.git-credentials|authorized_keys|id_(?:rsa|dsa|ecdsa|ed25519)(?:\.pub)?|credentials?(?:\..*)?|secrets?(?:\..*)?)(?:\z|\/)/i
    SECRET_EXTENSIONS = %w[.der .key .p12 .pfx .pem].freeze
    SECRET_CONTENT = [
      /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/,
      /\bAKIA[0-9A-Z]{16}\b/,
      /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,
      /\bsk-[A-Za-z0-9_-]{20,}\b/,
      /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/
    ].freeze
    EXCLUDED_PATHSPECS = [
      ":(exclude,glob)**/.env*",
      ":(exclude,glob)**/.netrc",
      ":(exclude,glob)**/.git-credentials",
      ":(exclude,glob)**/authorized_keys",
      ":(exclude,glob)**/id_rsa*",
      ":(exclude,glob)**/id_dsa*",
      ":(exclude,glob)**/id_ecdsa*",
      ":(exclude,glob)**/id_ed25519*",
      ":(exclude,glob)**/*credential*",
      ":(exclude,glob)**/*secret*",
      ":(exclude,glob)**/*.der",
      ":(exclude,glob)**/*.key",
      ":(exclude,glob)**/*.p12",
      ":(exclude,glob)**/*.pfx",
      ":(exclude,glob)**/*.pem"
    ].freeze

    CommandResult = Struct.new(:stdout, :stderr, :success, :truncated, :timed_out, keyword_init: true)
    class AwaitingInput < StandardError; end
    class BoundaryViolation < StandardError; end

    def initialize(root: Dir.pwd, process_env: ENV, clock: -> { Time.now.utc }, command_runner: nil, git_path: nil)
      @project_root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
      @command_runner = command_runner || method(:run_bounded)
      @git_path = git_path
    end

    def roots
      records = configured_roots.map do |root_id, path|
        begin
          validate_repository!(path)
          { "root_id" => root_id, "available" => true }
        rescue StandardError => error
          { "root_id" => root_id, "available" => false, "reason" => error.message }
        end
      end
      complete({ "roots" => records, "count" => records.length }, "approved repository roots inspected")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("approved repository roots failed safely: #{error.class}")
    end

    def inspect(root_id:)
      id, root = resolve_repository(root_id)
      head = required_git(root, %w[rev-parse --verify HEAD], max_bytes: 256).stdout.strip
      branch_result = git(root, %w[symbolic-ref --quiet --short HEAD], max_bytes: 512)
      branch = branch_result.success ? safe_text(branch_result.stdout.strip, 256) : nil
      status_result = required_git(root, %w[status --porcelain=v1 -z --untracked-files=normal], max_bytes: MAX_COMMAND_BYTES)
      log_result = required_git(root, ["log", "--max-count=#{MAX_LOG_ENTRIES}", "--date=iso-strict", "--format=%H%x09%h%x09%aI%x09%an%x09%s"], max_bytes: MAX_COMMAND_BYTES)
      worktree = diff(root, cached: false)
      staged = diff(root, cached: true)

      status = parse_status(status_result.stdout)
      complete({
        "root_id" => id,
        "branch" => branch,
        "detached" => branch.nil?,
        "head" => head.match?(/\A[0-9a-f]{40,64}\z/) ? head : "unavailable",
        "status" => status,
        "recent_commits" => parse_log(log_result.stdout),
        "diff" => { "worktree" => worktree, "staged" => staged },
        "content_trusted" => false,
        "authority" => "reference_only",
        "limits" => {
          "status_entries" => MAX_STATUS_ENTRIES,
          "log_entries" => MAX_LOG_ENTRIES,
          "diff_bytes_per_scope" => MAX_DIFF_BYTES,
          "command_timeout_seconds" => COMMAND_TIMEOUT_SECONDS
        }
      }, "approved repository inspected")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("repository inspection failed safely: #{error.class}")
    end

    private

    def configured_roots
      raw = @process_env.fetch(ROOTS_ENV, DEFAULT_ROOTS).to_s.strip
      raw = DEFAULT_ROOTS if raw.empty?
      entries = raw.split(";", -1)
      raise AwaitingInput, "#{ROOTS_ENV} must declare 1..#{MAX_ROOTS} repositories" unless entries.length.between?(1, MAX_ROOTS)

      entries.each_with_object({}) do |entry, roots|
        root_id, path = entry.split("=", 2).map { |value| value.to_s.strip }
        raise AwaitingInput, "approved repositories must use root_id=/absolute/or/project-relative/path" if root_id.empty? || path.empty?
        raise AwaitingInput, "approved repository ID is invalid: #{root_id}" unless root_id.match?(ROOT_ID)
        raise AwaitingInput, "approved repository ID is duplicated: #{root_id}" if roots.key?(root_id)
        roots[root_id] = File.expand_path(path, @project_root)
      end
    end

    def resolve_repository(root_id)
      id = root_id.to_s.strip
      roots = configured_roots
      raise AwaitingInput, "approved repository is required; ask to show approved repository roots" if id.empty?
      raise AwaitingInput, "unknown approved repository #{id}; ask to show approved repository roots" unless roots.key?(id)
      root = roots.fetch(id)
      validate_repository!(root)
      [id, root]
    end

    def validate_repository!(root)
      raise BoundaryViolation, "approved repository must be an existing directory" unless File.directory?(root)
      validate_no_symlink_components!(root)
      result = required_git(root, %w[rev-parse --show-toplevel], max_bytes: 4096)
      reported = File.expand_path(result.stdout.strip)
      raise BoundaryViolation, "approved path must be the repository top level" unless reported == File.expand_path(root)
      true
    rescue Errno::EACCES, Errno::ENOENT
      raise BoundaryViolation, "approved repository is unavailable"
    end

    def validate_no_symlink_components!(path)
      cursor = File::SEPARATOR
      File.expand_path(path).split(File::SEPARATOR).reject(&:empty?).each do |segment|
        cursor = File.join(cursor, segment)
        next unless File.exist?(cursor) || File.symlink?(cursor)
        raise BoundaryViolation, "approved repository traverses a symbolic link" if File.lstat(cursor).symlink?
      end
    end

    def selected_git_path
      return @git_path if @git_path && GIT_PATHS.include?(@git_path)
      GIT_PATHS.find { |path| File.file?(path) && File.executable?(path) }
    end

    def git(root, arguments, max_bytes:)
      path = selected_git_path
      raise BoundaryViolation, "fixed Git executable is unavailable" unless path
      argv = [path, "--no-pager", "-c", "color.ui=false", "-c", "core.fsmonitor=false", *arguments]
      @command_runner.call(argv, chdir: root, max_bytes: max_bytes, timeout: COMMAND_TIMEOUT_SECONDS)
    end

    def required_git(root, arguments, max_bytes:)
      result = git(root, arguments, max_bytes: max_bytes)
      raise BoundaryViolation, "repository command exceeded its time boundary" if result.timed_out
      raise BoundaryViolation, "repository command failed safely" unless result.success
      result
    end

    def diff(root, cached:)
      arguments = ["diff"]
      arguments << "--cached" if cached
      arguments.concat(["--no-ext-diff", "--no-textconv", "--no-renames", "--unified=3", "--", ".", *EXCLUDED_PATHSPECS])
      result = required_git(root, arguments, max_bytes: MAX_DIFF_BYTES)
      content = result.stdout.to_s.dup.force_encoding(Encoding::UTF_8)
      unless content.valid_encoding? && !content.include?("\0")
        return { "content" => "", "bytes" => 0, "truncated" => result.truncated == true, "withheld" => true, "reason" => "diff is not safe UTF-8 text" }
      end
      content = content.gsub(/[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]/, "�")
      if SECRET_CONTENT.any? { |pattern| content.match?(pattern) }
        return { "content" => "", "bytes" => 0, "truncated" => false, "withheld" => true, "reason" => "credential-like content detected" }
      end
      {
        "content" => content,
        "bytes" => content.bytesize,
        "truncated" => result.truncated == true,
        "withheld" => false
      }
    end

    def parse_status(raw)
      records = []
      omitted = 0
      fields = raw.to_s.split("\0", -1)
      index = 0
      while index < fields.length && !fields[index].empty?
        field = fields[index]
        code = field.byteslice(0, 2).to_s
        path = field.byteslice(3..).to_s
        index += 1
        index += 1 if code.start_with?("R", "C") && index < fields.length
        if prohibited_path?(path)
          omitted += 1
          next
        end
        records << { "code" => safe_text(code, 2), "path" => safe_text(path, 512) }
        break if records.length >= MAX_STATUS_ENTRIES
      end
      {
        "clean" => records.empty? && omitted.zero?,
        "entries" => records,
        "count" => records.length,
        "omitted_count" => omitted,
        "truncated" => index < fields.length - 1
      }
    end

    def parse_log(raw)
      raw.to_s.lines.first(MAX_LOG_ENTRIES).filter_map do |line|
        full, short, authored_at, author, subject = line.chomp.split("\t", 5)
        next unless full.to_s.match?(/\A[0-9a-f]{40,64}\z/)
        {
          "commit" => full,
          "short_commit" => safe_text(short, 16),
          "authored_at" => safe_text(authored_at, 64),
          "author" => safe_text(author, 256),
          "subject" => safe_text(subject, 512)
        }
      end
    end

    def prohibited_path?(path)
      normalized = path.to_s.tr("\\", "/")
      basename = File.basename(normalized)
      normalized.match?(SECRET_PATH) || basename.match?(/(?:credential|secret)/i) || SECRET_EXTENSIONS.include?(File.extname(normalized).downcase)
    end

    def safe_text(value, limit)
      clean = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�").gsub(/[\x00-\x1f\x7f]/, " ")
      clean = clean.byteslice(0, limit).to_s
      clean.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
    end

    def run_bounded(argv, chdir:, max_bytes:, timeout:)
      stdout = +""
      stderr = +""
      truncated = false
      status = nil
      timed_out = false
      stdin = out = err = wait = nil
      begin
        stdin, out, err, wait = Open3.popen3({ "GIT_OPTIONAL_LOCKS" => "0", "LC_ALL" => "C" }, *argv, chdir: chdir)
        stdin.close
        Timeout.timeout(timeout) do
          streams = { out => stdout, err => stderr }
          until streams.empty?
            ready = IO.select(streams.keys, nil, nil, 0.1)
            next unless ready
            ready.first.each do |stream|
              chunk = stream.read_nonblock(4096)
              target = streams.fetch(stream)
              remaining = max_bytes - target.bytesize
              if remaining <= 0 || chunk.bytesize > remaining
                target << chunk.byteslice(0, [remaining, 0].max).to_s
                truncated = true
                Process.kill("TERM", wait.pid) rescue nil
              else
                target << chunk
              end
            rescue EOFError
              streams.delete(stream)
            end
          end
          status = wait.value
        end
      rescue Timeout::Error
        timed_out = true
        Process.kill("KILL", wait.pid) rescue nil
        status = wait.value rescue nil
      ensure
        [stdin, out, err].compact.each { |stream| stream.close unless stream.closed? }
      end
      CommandResult.new(stdout: stdout, stderr: stderr, success: !timed_out && (status&.success? || truncated), truncated: truncated, timed_out: timed_out)
    end

    def complete(data, message) = outcome(true, "complete", message, data)
    def awaiting(message) = outcome(false, "awaiting_input", message, {})
    def blocked(message) = outcome(false, "blocked_for_human_review", message, {})
    def failed(message) = outcome(false, "failed", message, {})

    def outcome(ok, lifecycle, message, data)
      {
        "ok" => ok,
        "lifecycle_state" => lifecycle,
        "message" => message,
        "data" => data,
        "mutation" => "none",
        "retrieved_at" => @clock.call.iso8601(6)
      }
    end
  end
end
