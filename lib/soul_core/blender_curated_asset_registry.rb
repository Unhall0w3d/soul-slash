# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "pathname"
require "securerandom"
require "tmpdir"
require "uri"

module SoulCore
  # Limits curated Poly Haven downloads to the reviewed asset registry and
  # validates their identities and digests before installation.
  class BlenderCuratedAssetRegistry
    CONFIRMATION = "INSTALL_BLENDER_CURATED_ASSETS"
    HOST = "dl.polyhaven.org"
    INSTALL_RELATIVE_ROOT = "Soul/visual/assets/blender/polyhaven"

    def initialize(registry_path:, root:, downloader: nil)
      @registry_path = File.expand_path(registry_path)
      @root = File.expand_path(root)
      @downloader = downloader || method(:download)
      @registry = JSON.parse(File.read(@registry_path))
      validate_registry!
    end

    def preview
      { "confirmation_phrase" => CONFIRMATION, "expected_digest" => plan_digest,
        "registry_sha256" => Digest::SHA256.file(@registry_path).hexdigest,
        "install_root" => install_root, "assets" => @registry.fetch("assets").map { |a| a.slice("id", "kind", "resolution") },
        "file_count" => files.length, "total_bytes" => files.sum { |file| file.fetch("bytes") },
        "network_allowed_hosts" => [HOST], "background_execution" => false }
    end

    def install(expected_digest:, confirmation:)
      raise "exact confirmation is required" unless confirmation == CONFIRMATION
      raise "asset install plan digest changed" unless secure_compare(expected_digest, plan_digest)

      validate_installed!(allow_missing: true)
      files.each do |file|
        destination = destination_for(file)
        next if File.file?(destination)

        Dir.mktmpdir("soul-polyhaven-a8-") do |dir|
          temporary = File.join(dir, "download")
          @downloader.call(file, temporary)
          validate_file!(temporary, file)
          ensure_parent_directories(destination)
          staged = "#{destination}.partial-#{SecureRandom.hex(6)}"
          begin
            raise "curated asset staging path already exists" if File.exist?(staged) || File.symlink?(staged)
            FileUtils.cp(temporary, staged)
            validate_file!(staged, file)
            File.rename(staged, destination)
          ensure
            FileUtils.rm_f(staged) if staged
          end
        end
      end
      validate_installed!
      { "ok" => true, "lifecycle_state" => "complete", "receipt" => preview.merge("installed" => true) }
    rescue StandardError => e
      { "ok" => false, "lifecycle_state" => "failed", "error" => e.message }
    end

    def verify
      validate_installed!
      { "ok" => true, "registry_sha256" => Digest::SHA256.file(@registry_path).hexdigest,
        "file_count" => files.length, "total_bytes" => files.sum { |file| file.fetch("bytes") } }
    rescue StandardError => e
      { "ok" => false, "error" => e.message }
    end

    private

    def files = @registry.fetch("assets").flat_map { |asset| asset.fetch("files") }
    def install_root = File.join(@root, INSTALL_RELATIVE_ROOT)
    def plan_digest = Digest::SHA256.hexdigest(JSON.generate(canonical(@registry)))

    def validate_registry!
      raise "unsupported curated-asset registry schema" unless @registry.fetch("schema_version") == 1
      raise "unexpected curated-asset install root" unless @registry.fetch("install_root") == INSTALL_RELATIVE_ROOT
      ids = @registry.fetch("assets").map { |asset| asset.fetch("id") }
      raise "registry must contain only island_tree_01 and boulder_01" unless ids.sort == %w[boulder_01 island_tree_01]
      files.each do |file|
        path = file.fetch("path")
        uri = URI.parse(file.fetch("url"))
        raise "unsafe asset path #{path.inspect}" unless safe_relative?(path)
        raise "asset URL is not HTTPS dl.polyhaven.org" unless uri.scheme == "https" && uri.host == HOST && uri.userinfo.nil? && uri.port == 443
        raise "invalid asset byte count" unless file.fetch("bytes").is_a?(Integer) && file.fetch("bytes").positive?
        raise "invalid SHA-256 pin" unless file.fetch("sha256").match?(/\A[a-f0-9]{64}\z/)
      end
      raise "registry contains duplicate asset paths" unless files.map { |file| file.fetch("path") }.uniq.length == files.length
    end

    def validate_installed!(allow_missing: false)
      reject_symlink_or_missing_root!(allow_missing)
      expected = files.map { |file| file.fetch("path") }.sort
      actual = Dir.glob(File.join(install_root, "**", "*"), File::FNM_DOTMATCH).filter_map do |entry|
        raise "symlinked curated asset file: #{entry}" if File.symlink?(entry)
        next if [".", ".."].include?(File.basename(entry)) || File.directory?(entry)
        relative = Pathname.new(entry).relative_path_from(Pathname.new(install_root)).to_s
        raise "unexpected non-file in curated asset root: #{relative}" unless File.file?(entry)
        relative
      end.sort
      extra = actual - expected
      raise "unexpected curated asset files: #{extra.join(', ')}" unless extra.empty?
      files.each do |file|
        path = destination_for(file)
        next unless File.exist?(path) || File.symlink?(path)
        raise "curated asset path is not a regular file: #{file.fetch('path')}" unless File.file?(path) && !File.symlink?(path)
      end
      (expected & actual).each { |path| validate_file!(File.join(install_root, path), files.find { |file| file.fetch("path") == path }) }
      missing = expected - actual
      raise "missing curated asset files: #{missing.join(', ')}" unless allow_missing || missing.empty?
    end

    def reject_symlink_or_missing_root!(allow_missing)
      return unless File.exist?(install_root) || File.symlink?(install_root)
      raise "curated asset root is a symlink" if File.symlink?(install_root)
      raise "curated asset root is not a directory" unless File.directory?(install_root)
      Pathname.new(install_root).ascend do |path|
        break if path.to_s == @root
        raise "symlink in curated asset path: #{path}" if File.symlink?(path)
      end
    end

    def destination_for(file)
      candidate = File.expand_path(file.fetch("path"), install_root)
      raise "asset path escapes install root" unless candidate.start_with?(install_root + File::SEPARATOR)
      candidate
    end

    def ensure_parent_directories(destination)
      parent = File.dirname(destination)
      relative = Pathname.new(parent).relative_path_from(Pathname.new(@root)).each_filename.to_a
      current = @root
      relative.each do |part|
        current = File.join(current, part)
        raise "symlink in curated asset path: #{current}" if File.symlink?(current)
        FileUtils.mkdir(current) unless File.exist?(current)
        raise "curated asset parent is not a directory: #{current}" unless File.directory?(current)
      end
    end

    def validate_file!(path, file)
      raise "symlinked curated asset file: #{path}" if File.symlink?(path)
      raise "asset size mismatch for #{file.fetch('path')}" unless File.size(path) == file.fetch("bytes")
      actual = Digest::SHA256.file(path).hexdigest
      raise "asset digest mismatch for #{file.fetch('path')}" unless secure_compare(actual, file.fetch("sha256"))
    end

    def download(file, destination)
      uri = URI.parse(file.fetch("url"))
      2.times do |attempt|
        begin
          Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER,
                          open_timeout: 15, read_timeout: 120) do |http|
            request = Net::HTTP::Get.new(uri.request_uri)
            request["Accept-Encoding"] = "identity"
            http.request(request) do |response|
              raise "asset download failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
              expected = file.fetch("bytes")
              declared = response["Content-Length"]
              raise "asset download length changed" if declared && Integer(declared) != expected
              received = 0
              File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |stream|
                response.read_body do |chunk|
                  received += chunk.bytesize
                  raise "asset download exceeded pinned byte count" if received > expected
                  stream.write(chunk)
                end
              end
              raise "asset download length changed" unless received == expected
            end
          end
          return
        rescue StandardError
          raise if attempt == 1
        end
      end
    end

    def safe_relative?(path)
      !Pathname.new(path).absolute? && !path.split(File::SEPARATOR).include?("..") && !path.empty?
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize
      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end
  end
end
