# frozen_string_literal: true

module SoulCore
  module EnvLoader
    module_function

    def load(path = ".env")
      return false unless File.exist?(path)

      File.readlines(path, chomp: true).each do |line|
        stripped = line.strip
        next if stripped.empty?
        next if stripped.start_with?("#")
        next unless stripped.include?("=")

        key, value = stripped.split("=", 2)
        key = key.to_s.strip
        value = value.to_s.strip

        next if key.empty?
        next unless key.match?(/\A[A-Z_][A-Z0-9_]*\z/)

        value = unquote(value)
        ENV[key] = value unless ENV.key?(key)
      end

      true
    end

    def unquote(value)
      if (value.start_with?('"') && value.end_with?('"')) ||
         (value.start_with?("'") && value.end_with?("'"))
        value[1..-2]
      else
        value
      end
    end
  end
end
