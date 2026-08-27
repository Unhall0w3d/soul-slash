# frozen_string_literal: true

require "ipaddr"
require "json"
require "pathname"
require_relative "memory_projection_contract"
require_relative "memory_projection_query_service"
require_relative "memory_projection_reconciler"
require_relative "memory_projection_transports"

module SoulCore
  # Builds the optional remote projection reader from owner-private deployment
  # state. Any unavailable dependency remains a read failure that the query
  # service converts to the canonical local retrieval path.
  class MemoryProjectionRuntimeFactory
    MAX_PRIVATE_FILE_BYTES = 128 * 1024

    class UnavailableDependency
      def method_missing(*) = raise("projection dependency is unavailable")
      def respond_to_missing?(*, **) = true
    end

    def initialize(root:, process_env:, paths:, memory_store:, index_service:, embedding_client:, local_retrieval:)
      @root = root
      @env = process_env
      @paths = paths
      @memory_store = memory_store
      @index_service = index_service
      @embedding_client = embedding_client
      @local_retrieval = local_retrieval
    end

    def build
      qdrant, falkor, projection_root = projection_dependencies
      query_service(qdrant, falkor, projection_root)
    rescue StandardError
      unavailable = UnavailableDependency.new
      query_service(unavailable, unavailable, File.join(@paths.private_root, "projection"))
    end

    # A33 uses the same private transport construction as read-only queries but
    # fails closed instead of silently substituting unavailable dependencies.
    def build_reconciler
      qdrant, falkor, projection_root = projection_dependencies
      selector = selector_store(projection_root)
      [MemoryProjectionReconciler.new(
        contract: MemoryProjectionContract.new(memory_store: @memory_store, index_service: @index_service),
        qdrant_client: qdrant, falkor_client: falkor, selector_store: selector
      ), selector]
    end

    private

    def projection_dependencies
      projection_root = File.join(@paths.private_root, "projection")
      config_path = @env.fetch("SOUL_MEMORY_PROJECTION_PRIVATE_CONFIG", File.join(projection_root, "deployment.json"))
      config = read_private_json(config_path, allowed_root: projection_root)
      validate_config!(config, projection_root)
      ca_path = private_regular_path(config.fetch("ca_certificate_path"), allowed_root: projection_root)
      qdrant = QdrantProjectionClient.new(transport: BoundedJsonTlsTransport.new(
        endpoint: "https://#{config.fetch('ipv4')}:6333", ca_path: ca_path,
        headers: {"api-key" => read_private_text(config.fetch("qdrant_api_key_path"), allowed_root: projection_root)}
      ))
      falkor = FalkorProjectionClient.new(command_client: RedisTlsCommandClient.new(
        host: config.fetch("ipv4"), port: 6379, ca_path: ca_path,
        password: read_private_text(config.fetch("falkordb_password_path"), allowed_root: projection_root)
      ))
      [qdrant, falkor, projection_root]
    end

    def selector_store(projection_root)
      MemoryProjectionSelectorStore.new(private_root: @paths.private_root,
        path: File.join(projection_root, "active-generation.json"))
    end

    def query_service(qdrant, falkor, projection_root)
      selector = selector_store(projection_root)
      MemoryProjectionQueryService.new(
        memory_store: @memory_store,
        embedding_client: @embedding_client || UnavailableDependency.new,
        projection_contract: MemoryProjectionContract.new(memory_store: @memory_store, index_service: @index_service),
        selector_store: selector,
        qdrant_client: qdrant,
        falkor_client: falkor,
        local_retrieval: @local_retrieval,
        query_instruction: @env["SOUL_MEMORY_EMBEDDING_QUERY_INSTRUCTION"]
      )
    end

    def read_private_json(path, allowed_root:)
      JSON.parse(read_private_text(path, allowed_root: allowed_root))
    rescue JSON::ParserError
      raise "private projection JSON is malformed"
    end

    def read_private_text(path, allowed_root:)
      resolved = private_regular_path(path, allowed_root: allowed_root)
      raise "private projection file exceeds byte bound" if File.size(resolved) > MAX_PRIVATE_FILE_BYTES
      value = File.binread(resolved).strip
      raise "private projection file is empty" if value.empty?
      value
    end

    def private_regular_path(path, allowed_root:)
      root = File.realpath(allowed_root)
      value = File.expand_path(path.to_s)
      raise "private projection path escapes root" unless value.start_with?("#{root}#{File::SEPARATOR}")
      current = Pathname.new(root)
      relative = Pathname.new(value).relative_path_from(current)
      [current, *relative.each_filename.map { |name| current = current.join(name) }].each do |component|
        raise "private projection path contains a symlink" if File.symlink?(component.to_s)
      end
      stat = File.stat(value)
      raise "private projection path is not owner private" unless stat.file? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
      value
    rescue ArgumentError, Errno::ENOENT
      raise "private projection path is unavailable"
    end

    def validate_config!(config, projection_root)
      raise "private projection configuration is invalid" unless config.is_a?(Hash) && config["schema_version"] == "soul.memory-projection.private.a20.v1"
      host = config.fetch("fqdn").to_s
      raise "private projection host is invalid" unless host.match?(/\A[a-z0-9][a-z0-9.-]{1,252}[a-z0-9]\z/)
      address = IPAddr.new(config.fetch("ipv4").to_s)
      raise "private projection address is invalid" unless address.ipv4? && address.private?
      %w[ca_certificate_path qdrant_api_key_path falkordb_password_path].each do |key|
        private_regular_path(config.fetch(key), allowed_root: projection_root)
      end
    end
  end
end
