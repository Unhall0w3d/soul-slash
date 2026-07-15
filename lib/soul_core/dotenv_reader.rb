# frozen_string_literal: true

module SoulCore
  class DotenvReader
    MAX_BYTES = 64 * 1024
    MAX_LINES = 512
    ENV_NAME = /\A[A-Z_][A-Z0-9_]*\z/

    Result = Struct.new(:values, :loaded, :relative_path, :lifecycle_state, :errors, keyword_init: true) do
      def ok?
        errors.empty?
      end
    end

    def initialize(root:, path: nil)
      @root = File.expand_path(root)
      @path = File.expand_path(path || File.join(@root, ".env"), @root)
    end

    def read
      relative = relative_path!
      stat = File.lstat(@path)
      return blocked(relative, "dotenv must be a regular non-symlink file") unless stat.file? && !stat.symlink?
      return blocked(relative, "dotenv exceeds #{MAX_BYTES} bytes") if stat.size > MAX_BYTES

      flags = File::RDONLY
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
      bytes = File.open(@path, flags) do |file|
        opened = file.stat
        unless opened.file? && opened.dev == stat.dev && opened.ino == stat.ino
          return blocked(relative, "dotenv changed during safe open")
        end
        file.read(MAX_BYTES + 1)
      end
      return blocked(relative, "dotenv exceeds #{MAX_BYTES} bytes") if bytes.bytesize > MAX_BYTES

      text = bytes.dup.force_encoding(Encoding::UTF_8)
      return blocked(relative, "dotenv must be valid UTF-8") unless text.valid_encoding?

      lines = text.lines(chomp: true)
      return blocked(relative, "dotenv exceeds #{MAX_LINES} lines") if lines.length > MAX_LINES

      values = {}
      errors = []
      lines.each_with_index do |line, index|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")

        unless stripped.include?("=")
          errors << "line #{index + 1}: expected NAME=value"
          next
        end
        key, raw = stripped.split("=", 2).map(&:strip)
        unless key.match?(ENV_NAME)
          errors << "line #{index + 1}: invalid environment name"
          next
        end
        if values.key?(key)
          errors << "line #{index + 1}: duplicate environment name #{key}"
          next
        end
        values[key] = unquote(raw)
      end
      return blocked(relative, errors.first(100)) unless errors.empty?

      result(values.freeze, true, relative, "complete", [])
    rescue Errno::ENOENT
      result({}, false, safe_relative_path, "complete", [])
    rescue Errno::EACCES, Errno::EISDIR, IOError, SystemCallError => error
      blocked(safe_relative_path, "dotenv could not be read safely: #{error.class}")
    rescue ArgumentError => error
      blocked(safe_relative_path, error.message)
    end

    private

    def relative_path!
      prefix = @root.end_with?(File::SEPARATOR) ? @root : "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "dotenv path must remain below the project root" unless @path.start_with?(prefix)

      @path.delete_prefix(prefix)
    end

    def safe_relative_path
      relative_path!
    rescue ArgumentError
      nil
    end

    def unquote(value)
      return value[1..-2] if value.length >= 2 && ((value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'")))

      value
    end

    def result(values, loaded, relative_path, lifecycle_state, errors)
      Result.new(values: values, loaded: loaded, relative_path: relative_path, lifecycle_state: lifecycle_state, errors: Array(errors))
    end

    def blocked(relative_path, errors)
      result({}, false, relative_path, "blocked_for_human_review", Array(errors))
    end
  end
end
