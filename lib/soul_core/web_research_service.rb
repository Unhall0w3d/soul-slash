# frozen_string_literal: true

require "cgi"
require "digest"
require "ipaddr"
require "json"
require "net/http"
require "resolv"
require "securerandom"
require "time"
require "timeout"
require "uri"

module SoulCore
  class WebResearchService
    MAX_QUERY_BYTES = 500
    MAX_LOOKUP_RESPONSE_BYTES = 512 * 1024
    LOOKUP_TIMEOUT = 30
    MAX_QUERIES = 3
    MAX_SOURCES = 8
    MAX_RESPONSE_BYTES = 1024 * 1024
    MAX_TOTAL_BYTES = 4 * 1024 * 1024
    MAX_REDIRECTS = 3
    OVERALL_TIMEOUT = 90
    USER_AGENT = "SoulResearch/1.0 (+local-owner-directed)"
    SOURCE_TYPES = %w[text/html text/plain application/xhtml+xml].freeze
    BLOCKED_NETWORKS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16
      198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 2001:db8::/32
    ].map { |network| IPAddr.new(network) }.freeze
    PRIVATE_PROVIDER_NETWORKS = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/7].map { |network| IPAddr.new(network) }.freeze

    def initialize(env: ENV, clock: -> { Time.now }, resolver: nil, http_factory: nil)
      @env = env.to_h
      @clock = clock
      @resolver = resolver || ->(host) { Resolv.getaddresses(host) }
      @http_factory = http_factory || ->(host, port) { Net::HTTP.new(host, port) }
    end

    def configured?
      %w[searxng brave].include?(provider)
    end

    def configuration
      {
        "provider" => provider.empty? ? "unconfigured" : provider,
        "configured" => configured?,
        "searxng_url_present" => !@env.fetch("SOUL_WEB_SEARXNG_URL", "").strip.empty?,
        "private_searxng_allowed" => private_searxng_allowed?,
        "brave_key_present" => !@env.fetch("SOUL_WEB_BRAVE_API_KEY", "").strip.empty?,
        "limits" => { "queries" => MAX_QUERIES, "sources" => MAX_SOURCES, "response_bytes" => MAX_RESPONSE_BYTES, "total_bytes" => MAX_TOTAL_BYTES, "overall_seconds" => OVERALL_TIMEOUT }
      }
    end

    def research(queries:, source_limit: 5)
      normalized = normalize_queries(queries)
      limit = [[Integer(source_limit), 1].max, MAX_SOURCES].min
      return blocked("web search provider is not configured", data: { "configuration" => configuration }) unless configured?

      Timeout.timeout(OVERALL_TIMEOUT) do
        searches = normalized.map { |query| search(query) }
        failed_search = searches.find { |result| !result["ok"] }
        return failed(failed_search.fetch("reason"), data: { "searches" => searches }) if failed_search

        candidates = searches.flat_map { |result| result.dig("data", "results") || [] }.uniq { |item| item["url"] }.first(limit)
        total = 0
        sources = candidates.map.with_index do |candidate, index|
          fetched = fetch_source(candidate.fetch("url"), remaining_bytes: MAX_TOTAL_BYTES - total)
          total += fetched.dig("data", "bytes").to_i if fetched["ok"]
          source_record(candidate, fetched, index + 1)
        end
        usable = sources.select { |source| source["status"] == "ok" }
        return failed("no selected public source could be retrieved safely", data: { "queries" => normalized, "sources" => sources }) if usable.empty?

        complete({
          "schema_version" => "soul.web_research.v1",
          "research_id" => "res_#{@clock.call.utc.strftime('%Y%m%d%H%M%S')}_#{SecureRandom.hex(4)}",
          "queries" => normalized,
          "provider" => provider,
          "sources" => sources,
          "usable_source_count" => usable.length,
          "retrieved_bytes" => total,
          "collected_at" => @clock.call.iso8601,
          "source_content_is_untrusted" => true,
          "authorization_effect" => "none"
        })
      end
    rescue ArgumentError => error
      awaiting(error.message)
    rescue Timeout::Error
      failed("web research exceeded the #{OVERALL_TIMEOUT}-second foreground limit")
    rescue StandardError => error
      failed("web research failed safely: #{error.class}")
    end

    def lookup(query)
      text = normalize_query(query)
      Timeout.timeout(LOOKUP_TIMEOUT) do
        uri = URI("https://api.duckduckgo.com/")
        uri.query = URI.encode_www_form(q: text, format: "json", no_html: "1", no_redirect: "1", skip_disambig: "1")
        response = request(uri.to_s, accepted_types: ["application/json", "application/x-javascript"], max_bytes: MAX_LOOKUP_RESPONSE_BYTES, allow_loopback: false)
        return response unless response["ok"]

        body = response.dig("data", "body")
        payload = JSON.parse(body)
        answer = instant_answer(payload)
        complete({
          "schema_version" => "soul.web_lookup.v1",
          "query" => text,
          "provider" => "duckduckgo_instant_answer",
          "found" => !answer.nil?,
          "answer" => answer,
          "retrieved_at" => @clock.call.iso8601,
          "response_digest" => Digest::SHA256.hexdigest(body),
          "source_content_is_untrusted" => true,
          "authorization_effect" => "none"
        }.compact)
      end
    rescue ArgumentError => error
      awaiting(error.message)
    rescue JSON::ParserError
      failed("DuckDuckGo Instant Answer returned invalid JSON")
    rescue Timeout::Error
      failed("web lookup exceeded the #{LOOKUP_TIMEOUT}-second foreground limit")
    rescue StandardError => error
      failed("web lookup failed safely: #{error.class}")
    end

    def search(query)
      text = normalize_query(query)
      case provider
      when "searxng" then search_searxng(text)
      when "brave" then search_brave(text)
      else blocked("web search provider is not configured", data: { "configuration" => configuration })
      end
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("web search failed safely: #{error.class}")
    end

    def fetch_source(url, remaining_bytes: MAX_RESPONSE_BYTES)
      remaining = Integer(remaining_bytes)
      return failed("research byte budget is exhausted") unless remaining.positive?

      maximum = [remaining, MAX_RESPONSE_BYTES].min
      response = request(url, accepted_types: SOURCE_TYPES, max_bytes: maximum, allow_loopback: false)
      return failed(response.fetch("reason"), data: response["data"] || {}) unless response["ok"]

      body = response.dig("data", "body")
      media_type = response.dig("data", "media_type")
      text = media_type == "text/plain" ? normalize_text(body) : html_text(body)
      return failed("source contained no usable text", data: response.fetch("data").except("body")) if text.empty?

      complete(response.fetch("data").except("body").merge(
        "text" => text.byteslice(0, MAX_RESPONSE_BYTES),
        "content_digest" => Digest::SHA256.hexdigest(body)
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("source retrieval failed safely: #{error.class}")
    end

    private

    def provider
      @provider ||= @env.fetch("SOUL_WEB_SEARCH_PROVIDER", "").strip.downcase
    end

    def normalize_queries(values)
      list = Array(values)
      raise ArgumentError, "research requires 1 to #{MAX_QUERIES} queries" unless list.length.between?(1, MAX_QUERIES)

      list.map { |value| normalize_query(value) }.uniq
    end

    def normalize_query(value)
      text = value.to_s.strip.gsub(/\s+/, " ")
      raise ArgumentError, "research query is required" if text.empty?
      raise ArgumentError, "research query exceeds #{MAX_QUERY_BYTES} bytes" if text.bytesize > MAX_QUERY_BYTES
      raise ArgumentError, "research query contains control characters" if text.match?(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/)

      text
    end

    def search_searxng(query)
      base = @env.fetch("SOUL_WEB_SEARXNG_URL", "").strip
      return blocked("SOUL_WEB_SEARXNG_URL is required for the configured provider") if base.empty?
      uri = URI.parse(base)
      validate_provider_uri!(uri)
      uri.path = "#{uri.path.sub(%r{/\z}, '')}/search"
      uri.query = URI.encode_www_form(q: query, format: "json", categories: "general", language: "en-US", safesearch: "1")
      response = request(uri.to_s, accepted_types: ["application/json"], max_bytes: MAX_RESPONSE_BYTES, allow_loopback: true)
      return response unless response["ok"]
      payload = JSON.parse(response.dig("data", "body"))
      results = Array(payload["results"]).first(MAX_SOURCES * 2).filter_map { |item| normalize_result(item["title"], item["url"], item["content"]) }
      complete({ "query" => query, "provider" => "searxng", "results" => results, "result_count" => results.length })
    rescue JSON::ParserError
      failed("SearXNG returned invalid JSON")
    end

    def search_brave(query)
      key = @env.fetch("SOUL_WEB_BRAVE_API_KEY", "").strip
      return blocked("SOUL_WEB_BRAVE_API_KEY is required for the configured provider") if key.empty?
      uri = URI("https://api.search.brave.com/res/v1/web/search")
      uri.query = URI.encode_www_form(q: query, count: MAX_SOURCES * 2, safesearch: "moderate")
      response = request(uri.to_s, accepted_types: ["application/json"], max_bytes: MAX_RESPONSE_BYTES, headers: { "X-Subscription-Token" => key }, allow_loopback: false)
      return response unless response["ok"]
      payload = JSON.parse(response.dig("data", "body"))
      results = Array(payload.dig("web", "results")).first(MAX_SOURCES * 2).filter_map { |item| normalize_result(item["title"], item["url"], item["description"]) }
      complete({ "query" => query, "provider" => "brave", "results" => results, "result_count" => results.length })
    rescue JSON::ParserError
      failed("Brave Search returned invalid JSON")
    end

    def normalize_result(title, url, snippet)
      uri = URI.parse(url.to_s)
      validate_source_uri!(uri)
      { "title" => normalize_text(title).byteslice(0, 300), "url" => canonical_url(uri), "snippet" => normalize_text(snippet).byteslice(0, 1_000) }
    rescue ArgumentError, URI::InvalidURIError
      nil
    end

    def instant_answer(payload)
      candidates = [
        [payload["Answer"], payload["AnswerType"], payload["AbstractURL"]],
        [payload["AbstractText"], payload["AbstractSource"], payload["AbstractURL"]],
        [payload["Definition"], payload["DefinitionSource"], payload["DefinitionURL"]]
      ]
      text, source, source_url = candidates.find { |candidate| !normalize_text(candidate[0]).empty? }
      return nil unless text

      url = nil
      unless source_url.to_s.strip.empty?
        uri = URI.parse(source_url.to_s)
        validate_source_uri!(uri)
        url = canonical_url(uri)
      end
      {
        "heading" => normalize_text(payload["Heading"]).byteslice(0, 300),
        "text" => normalize_text(text).byteslice(0, 8_000),
        "source" => normalize_text(source).byteslice(0, 300),
        "source_url" => url
      }.reject { |_key, value| value.nil? || value.empty? }
    rescue ArgumentError, URI::InvalidURIError
      nil
    end

    def request(url, accepted_types:, max_bytes:, headers: {}, allow_loopback:, redirects: 0, provider_authority: nil)
      raise ArgumentError, "redirect limit exceeded" if redirects > MAX_REDIRECTS
      uri = URI.parse(url)
      allow_loopback ? validate_provider_uri!(uri) : validate_source_uri!(uri)
      authority = [uri.host.to_s.downcase, uri.port]
      provider_authority ||= authority if allow_loopback
      if allow_loopback && provider_authority != authority
        raise ArgumentError, "search provider redirect changed the configured authority"
      end
      addresses = Array(@resolver.call(uri.host)).map { |address| IPAddr.new(address) rescue nil }.compact
      raise ArgumentError, "host did not resolve" if addresses.empty?
      allowed = addresses.reject { |address| blocked_address?(address) }
      if allow_loopback && uri.scheme == "http"
        allowed = if loopback_host?(uri.host)
                    addresses.select(&:loopback?)
                  elsif private_searxng_allowed?
                    addresses.select { |address| private_provider_address?(address) }
                  else
                    []
                  end
      elsif allow_loopback && private_searxng_allowed?
        allowed = addresses.select { |address| !blocked_address?(address) || private_provider_address?(address) }
      end
      raise ArgumentError, "host resolves to a blocked network" if allowed.empty?

      http = @http_factory.call(uri.host, uri.port)
      http.ipaddr = allowed.first.to_s if http.respond_to?(:ipaddr=)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 20
      http_request = Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => USER_AGENT, "Accept" => accepted_types.join(", ") }.merge(headers))
      response = nil
      body = +""
      http.request(http_request) do |remote_response|
        response = remote_response
        next unless remote_response.is_a?(Net::HTTPSuccess)

        declared = remote_response["content-length"].to_i
        raise ArgumentError, "remote response exceeds the byte limit" if declared > max_bytes
        remote_response.read_body do |chunk|
          body << chunk
          raise ArgumentError, "remote response exceeds the byte limit" if body.bytesize > max_bytes
        end
      end
      if response.is_a?(Net::HTTPRedirection)
        location = response["location"].to_s
        raise ArgumentError, "redirect location is missing" if location.empty?
        return request(URI.join(uri, location).to_s, accepted_types: accepted_types, max_bytes: max_bytes, headers: headers, allow_loopback: allow_loopback, redirects: redirects + 1, provider_authority: provider_authority)
      end
      return failed("remote source returned HTTP #{response.code}", data: { "url" => canonical_url(uri), "http_status" => response.code.to_i }) unless response.is_a?(Net::HTTPSuccess)

      media_type = response["content-type"].to_s.split(";", 2).first.strip.downcase
      return failed("remote content type is not allowed", data: { "url" => canonical_url(uri), "media_type" => media_type }) unless accepted_types.include?(media_type)
      complete({ "url" => canonical_url(uri), "media_type" => media_type, "http_status" => response.code.to_i, "bytes" => body.bytesize, "body" => body, "redirects" => redirects })
    end

    def validate_source_uri!(uri)
      raise ArgumentError, "source URL must use HTTPS" unless uri.scheme == "https"
      validate_common_uri!(uri)
    end

    def validate_provider_uri!(uri)
      validate_common_uri!(uri)
      return if uri.scheme == "https"
      return if uri.scheme == "http" && (loopback_host?(uri.host) || private_searxng_allowed?)

      raise ArgumentError, "search provider URL must use HTTPS unless private SearXNG HTTP is explicitly allowed"
    end

    def validate_common_uri!(uri)
      raise ArgumentError, "URL host is required" if uri.host.to_s.empty?
      raise ArgumentError, "URL credentials are forbidden" if uri.userinfo
      raise ArgumentError, "URL fragments are forbidden" if uri.fragment
      raise ArgumentError, "URL port is invalid" unless uri.port.between?(1, 65_535)
    end

    def loopback_host?(host)
      host.to_s.casecmp("localhost").zero? || (IPAddr.new(host).loopback? rescue false)
    end

    def blocked_address?(address)
      BLOCKED_NETWORKS.any? { |network| network.include?(address) }
    end

    def private_provider_address?(address)
      PRIVATE_PROVIDER_NETWORKS.any? { |network| network.include?(address) }
    end

    def private_searxng_allowed?
      %w[1 true yes on].include?(@env.fetch("SOUL_WEB_ALLOW_PRIVATE_SEARXNG", "0").strip.downcase)
    end

    def canonical_url(uri)
      clean = uri.dup
      clean.fragment = nil
      clean.to_s
    end

    def source_record(candidate, fetched, number)
      data = fetched["data"] || {}
      {
        "source_id" => "S#{number}", "title" => candidate["title"], "url" => candidate["url"], "search_snippet" => candidate["snippet"],
        "status" => fetched["ok"] ? "ok" : fetched["lifecycle_state"], "reason" => fetched["reason"],
        "retrieved_at" => @clock.call.iso8601, "media_type" => data["media_type"], "bytes" => data["bytes"],
        "content_digest" => data["content_digest"], "text" => data["text"]&.byteslice(0, MAX_RESPONSE_BYTES)
      }.compact
    end

    def html_text(body)
      text = body.to_s.gsub(/<script\b[^>]*>.*?<\/script>/mi, " ").gsub(/<style\b[^>]*>.*?<\/style>/mi, " ")
      normalize_text(CGI.unescapeHTML(text.gsub(/<[^>]+>/, " ")))
    end

    def normalize_text(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ").gsub(/\s+/, " ").strip
    end

    def complete(data) = { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => "none" }
    def awaiting(reason) = { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => {}, "mutation" => "none" }
    def blocked(reason, data: {}) = { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => data, "mutation" => "none" }
    def failed(reason, data: {}) = { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "data" => data, "mutation" => "none" }
  end
end
