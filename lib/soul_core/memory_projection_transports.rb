# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "pathname"
require "socket"
require "tempfile"
require "timeout"
require "uri"

module SoulCore
  class MemoryProjectionSelectorStore
    SCHEMA = "soul.memory_projection_reconciler.a21.v1"
    MAX_BYTES = 32 * 1024

    def initialize(private_root:, path:)
      @private_root = File.expand_path(private_root)
      @path = File.expand_path(path)
      prefix = "#{@private_root}#{File::SEPARATOR}"
      raise ArgumentError, "selector path escapes private memory" unless @path.start_with?(prefix)
    end

    def active
      validate_path!
      return nil unless File.exist?(@path)
      raise "selector is not a regular file" unless File.file?(@path) && !File.symlink?(@path)
      raise "selector exceeds byte bound" if File.size(@path) > MAX_BYTES
      validate_selector(JSON.parse(File.binread(@path)))
    rescue JSON::ParserError
      raise "selector JSON is malformed"
    end

    def activate(selector)
      value = validate_selector(selector)
      validate_path!
      FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
      validate_path!
      temporary = Tempfile.new([".active-generation-", ".json"], File.dirname(@path), mode: 0o600)
      begin
        temporary.write(JSON.generate(value) + "\n")
        temporary.flush
        temporary.fsync
        temporary.close
        raise "selector destination is a symlink" if File.symlink?(@path)
        File.rename(temporary.path, @path)
        File.chmod(0o600, @path)
        File.open(File.dirname(@path), File::RDONLY) { |directory| directory.fsync }
      ensure
        temporary.close unless temporary.closed?
        File.delete(temporary.path) if File.exist?(temporary.path)
      end
      value
    end

    private

    def validate_path!
      root = Pathname.new(@private_root)
      current = root
      relative = Pathname.new(File.dirname(@path)).relative_path_from(root)
      [root, *relative.each_filename.map { |name| current = current.join(name) }].each do |component|
        next unless File.exist?(component.to_s) || File.symlink?(component.to_s)
        raise "selector path contains a symlink component" if File.symlink?(component.to_s)
      end
      true
    rescue ArgumentError
      raise "selector path escapes private memory"
    end

    def validate_selector(value)
      raise "selector must be an object" unless value.is_a?(Hash)
      required = %w[schema generation_id payload_digest source_digests qdrant_collection falkor_graph]
      raise "selector fields are invalid" unless value.keys.sort == required.sort
      raise "selector schema is invalid" unless value["schema"] == SCHEMA
      raise "selector generation is invalid" unless value["generation_id"].to_s.match?(/\Ageneration_[0-9a-f]{20}\z/)
      raise "selector payload digest is invalid" unless value["payload_digest"].to_s.match?(/\A[0-9a-f]{64}\z/)
      digests = value["source_digests"]
      raise "selector source digests are invalid" unless digests.is_a?(Hash) && digests.keys.sort == %w[approved_index canonical_state]
      raise "selector source digests are invalid" unless digests.values.all? { |item| item.to_s.match?(/\A[0-9a-f]{64}\z/) }
      raise "selector Qdrant collection is invalid" unless value["qdrant_collection"].to_s.match?(/\Asoul_memory_vectors_[0-9a-f]{20}\z/)
      raise "selector FalkorDB graph is invalid" unless value["falkor_graph"].to_s.match?(/\ASoulMemory_[0-9a-f]{20}\z/)
      JSON.parse(JSON.generate(value))
    end
  end

  class BoundedJsonTlsTransport
    Response = Struct.new(:code, :body, keyword_init: true)

    def initialize(endpoint:, ca_path:, headers: {}, open_timeout: 5, read_timeout: 60, max_response_bytes: 128 * 1024 * 1024)
      @endpoint = URI.parse(endpoint)
      raise ArgumentError, "projection endpoint must use HTTPS" unless @endpoint.is_a?(URI::HTTPS) && @endpoint.path.to_s.empty?
      @ca_path = ca_path
      @headers = headers
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @max_response_bytes = max_response_bytes
    end

    def request(method, path, body: nil)
      klass = {"GET" => Net::HTTP::Get, "PUT" => Net::HTTP::Put, "POST" => Net::HTTP::Post, "DELETE" => Net::HTTP::Delete}.fetch(method)
      request = klass.new(path, @headers)
      if body
        encoded = JSON.generate(body)
        raise "projection request exceeds byte bound" if encoded.bytesize > @max_response_bytes
        request["content-type"] = "application/json"
        request.body = encoded
      end
      http = Net::HTTP.new(@endpoint.host, @endpoint.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.ca_file = @ca_path
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      response = http.start { |client| client.request(request) }
      payload = response.body.to_s
      raise "projection response exceeds byte bound" if payload.bytesize > @max_response_bytes
      Response.new(code: Integer(response.code), body: payload)
    end
  end

  class QdrantProjectionClient
    MAX_POINTS = 5_000
    BATCH_SIZE = 128

    def initialize(transport:)
      @transport = transport
      @expected = {}
    end

    def prepare(name:, payload:)
      validate_name!(name)
      validate_payload!(payload)
      @expected[name] = payload
      response = @transport.request("GET", "/collections/#{name}")
      return "existing" if response.code == 200
      raise "Qdrant collection inspection failed" unless response.code == 404
      created = @transport.request("PUT", "/collections/#{name}", body: {"vectors" => {"size" => payload.fetch("dimensions"), "distance" => "Cosine"}})
      raise "Qdrant collection creation failed" unless success?(created)
      payload.fetch("points").each_slice(BATCH_SIZE) do |points|
        written = @transport.request("PUT", "/collections/#{name}/points?wait=true", body: {"points" => points})
        raise "Qdrant point write failed" unless success?(written)
      end
      "created"
    end

    def verify(name:)
      expected = @expected.fetch(name)
      points = []
      offset = nil
      iterations = 0
      loop do
        iterations += 1
        raise "Qdrant scroll exceeds operation bound" if iterations > 42
        body = {"limit" => BATCH_SIZE, "with_payload" => true, "with_vector" => true}
        body["offset"] = offset if offset
        response = @transport.request("POST", "/collections/#{name}/points/scroll", body: body)
        raise "Qdrant verification read failed" unless success?(response)
        result = parse(response).fetch("result")
        batch = Array(result.fetch("points"))
        points.concat(batch)
        raise "Qdrant verification exceeds point bound" if points.length > MAX_POINTS
        offset = result["next_page_offset"]
        break if offset.nil?
      end
      observed = expected.merge("points" => points.sort_by { |point| point.fetch("payload").fetch("memory_id") })
      expected_digest = digest(expected)
      raise "Qdrant exact membership verification failed" unless digest(observed) == expected_digest
      {"payload_digest" => expected_digest}
    end

    def delete(name:)
      validate_name!(name)
      response = @transport.request("DELETE", "/collections/#{name}")
      raise "Qdrant generation cleanup failed" unless success?(response) || response.code == 404
      true
    end

    private

    def validate_name!(name)
      raise "Qdrant generation name is invalid" unless name.to_s.match?(/\Asoul_memory_vectors_[0-9a-f]{20}\z/)
    end
    def validate_payload!(payload)
      raise "Qdrant payload is invalid" unless payload.is_a?(Hash) && payload["schema"] == "soul.memory_qdrant_projection.a18.v1"
      raise "Qdrant point bound exceeded" if Array(payload["points"]).length > MAX_POINTS
      dimensions = Integer(payload.fetch("dimensions"))
      raise "Qdrant dimensions are invalid" unless dimensions.between?(1, 1_024)
    end
    def success?(response) = response.code.between?(200, 299)
    def parse(response) = JSON.parse(response.body)
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    def canonical(value) = value.is_a?(Hash) ? value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] } : value.is_a?(Array) ? value.map { |item| canonical(item) } : value
  end

  class RedisTlsCommandClient
    def initialize(host:, port:, ca_path:, password:, connect_timeout: 5, read_timeout: 30)
      @host, @port, @ca_path, @password = host, Integer(port), ca_path, password
      @connect_timeout, @read_timeout = connect_timeout, read_timeout
    end

    def call(*parts) = pipeline([parts]).first

    def pipeline(commands)
      raise "Redis pipeline exceeds batch bound" if commands.length > 128
      Timeout.timeout(@read_timeout) do
        tcp = Socket.tcp(@host, @port, connect_timeout: @connect_timeout)
        context = OpenSSL::SSL::SSLContext.new
        context.verify_mode = OpenSSL::SSL::VERIFY_PEER
        context.ca_file = @ca_path
        ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
        ssl.hostname = @host
        ssl.sync_close = true
        ssl.connect
        ssl.write(frame(["AUTH", @password]))
        raise "FalkorDB authentication failed" unless read_response(ssl) == "OK"
        ssl.write(commands.map { |command| frame(command) }.join)
        commands.map { read_response(ssl) }
      end
    ensure
      ssl&.close
      tcp&.close unless tcp&.closed?
    end

    private

    def frame(parts) = "*#{parts.length}\r\n" + parts.map { |part| value = part.to_s; "$#{value.bytesize}\r\n#{value}\r\n" }.join
    def read_response(io)
      marker = io.read(1)
      raise "FalkorDB response ended unexpectedly" unless marker
      line = io.gets("\r\n")&.delete_suffix("\r\n") or raise "FalkorDB response ended unexpectedly"
      case marker
      when "+" then line
      when "-" then raise "FalkorDB command failed"
      when ":" then Integer(line)
      when "$"
        size = Integer(line)
        return nil if size == -1
        value = io.read(size)
        raise "FalkorDB response ended unexpectedly" unless value&.bytesize == size && io.read(2) == "\r\n"
        value
      when "*"
        count = Integer(line)
        return nil if count == -1
        Array.new(count) { read_response(io) }
      else raise "FalkorDB response type is invalid"
      end
    end
  end

  class FalkorProjectionClient
    MAX_RECORDS = 5_000
    BATCH_SIZE = 128
    NODE_FIELDS = %w[layer source_kind content_digest canonical_source_digest state created_at updated_at].freeze

    def initialize(command_client:)
      @client = command_client
      @expected = {}
    end

    def prepare(name:, payload:)
      validate_name!(name)
      validate_payload!(payload)
      @expected[name] = payload
      return "existing" if Array(@client.call("GRAPH.LIST")).include?(name)
      commands = [["GRAPH.QUERY", name, "CREATE (:ProjectionGeneration {schema: #{literal(payload.fetch("schema"))}})", "--compact"]]
      payload.fetch("nodes").each { |node| commands << ["GRAPH.QUERY", name, create_node(node), "--compact"] }
      payload.fetch("edges").each { |edge| commands << ["GRAPH.QUERY", name, create_edge(edge), "--compact"] }
      commands.each_slice(BATCH_SIZE) { |batch| @client.pipeline(batch) }
      "created"
    end

    def verify(name:)
      expected = @expected.fetch(name)
      node_query = "MATCH (n:Memory) RETURN n.id, labels(n), #{NODE_FIELDS.map { |field| "n.#{field}" }.join(', ')} ORDER BY n.id"
      edge_query = "MATCH (a:Memory)-[r]->(b:Memory) RETURN a.id, b.id, type(r) ORDER BY type(r), a.id, b.id"
      nodes = rows(@client.call("GRAPH.RO_QUERY", name, node_query, "--compact")).map do |row|
        id, labels, *values = row
        {"id" => id, "labels" => Array(labels), "properties" => NODE_FIELDS.zip(values).to_h}
      end
      edges = rows(@client.call("GRAPH.RO_QUERY", name, edge_query, "--compact")).map do |source, target, relation|
        {"source" => source, "target" => target, "relation" => relation}
      end
      observed = expected.merge("nodes" => nodes, "edges" => edges)
      expected_digest = digest(expected)
      raise "FalkorDB exact membership verification failed" unless digest(observed) == expected_digest
      {"payload_digest" => expected_digest}
    end

    def delete(name:)
      validate_name!(name)
      return true unless Array(@client.call("GRAPH.LIST")).include?(name)
      @client.call("GRAPH.DELETE", name)
      true
    end

    private

    def rows(response) = Array(response).fetch(1, [])
    def validate_name!(name)
      raise "FalkorDB generation name is invalid" unless name.to_s.match?(/\ASoulMemory_[0-9a-f]{20}\z/)
    end
    def validate_payload!(payload)
      raise "FalkorDB payload is invalid" unless payload.is_a?(Hash) && payload["schema"] == "soul.memory_falkor_projection.a18.v1"
      raise "FalkorDB record bound exceeded" if Array(payload["nodes"]).length > MAX_RECORDS || Array(payload["edges"]).length > MAX_RECORDS * 2
    end
    def create_node(node)
      labels = Array(node.fetch("labels"))
      raise "FalkorDB node labels are invalid" unless labels.all? { |label| label.match?(/\A[A-Z][A-Za-z0-9]*\z/) }
      properties = {"id" => node.fetch("id")}.merge(node.fetch("properties"))
      "CREATE (n:#{labels.join(':')} #{map_literal(properties)})"
    end
    def create_edge(edge)
      relation = edge.fetch("relation")
      raise "FalkorDB relation is invalid" unless %w[SUPERSEDED_BY EXACT_DUPLICATE].include?(relation)
      "MATCH (a:Memory {id: #{literal(edge.fetch("source"))}}), (b:Memory {id: #{literal(edge.fetch("target"))}}) CREATE (a)-[:#{relation}]->(b)"
    end
    def map_literal(properties)
      raise "FalkorDB properties are invalid" unless properties.keys.all? { |key| (["id"] + NODE_FIELDS).include?(key.to_s) }
      "{" + properties.sort.map { |key, value| "#{key}: #{literal(value)}" }.join(", ") + "}"
    end
    def literal(value)
      raise "FalkorDB property is invalid" unless value.is_a?(String) && value.bytesize <= 512
      JSON.generate(value)
    end
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    def canonical(value) = value.is_a?(Hash) ? value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] } : value.is_a?(Array) ? value.map { |item| canonical(item) } : value
  end
end
