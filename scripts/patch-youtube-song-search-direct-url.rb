#!/usr/bin/env ruby
# frozen_string_literal: true

path = "Soul/skills/youtube/song_search.rb"

unless File.exist?(path)
  warn "Missing #{path}"
  exit 1
end

text = File.read(path)

# Replace the whole file. The previous implementation is small, and a full replacement
# is less brittle than surgically patching a dozen helper methods.
replacement = <<~'RUBY'
  #!/usr/bin/env ruby
  # frozen_string_literal: true

  require "json"
  require "time"
  require "fileutils"
  require "uri"
  require "open3"

  ROOT = File.expand_path("../../..", __dir__)

  module SoulSkills
    module YouTube
      class SongSearch
        MAX_QUERY_LENGTH = 240
        DEFAULT_LAUNCHER = "xdg-open"

        def initialize(argv, env = ENV)
          @argv = argv
          @env = env
        end

        def run
          if @argv.include?("--help") || @argv.include?("-h")
            puts help_text
            return 0
          end

          raw_url = option_value("--url")
          raw_query = option_value("--query") || option_value("--song") || positional_query

          result =
            if raw_url && !raw_url.to_s.strip.empty?
              process_direct_url(raw_url)
            else
              query = normalize_query(raw_query)
              if query.empty?
                blocked_for_input("Missing song/search query or YouTube URL. Provide --query \"Song Name\" or --url \"https://www.youtube.com/watch?v=...\".")
              elsif query.length > MAX_QUERY_LENGTH
                blocked_for_input("Query is too long. Maximum supported length is #{MAX_QUERY_LENGTH} characters.", query: query)
              else
                process_query(query)
              end
            end

          log_path = write_log(result)
          result["task_log"] = log_path if log_path
          puts JSON.pretty_generate(result)

          terminal_success?(result) ? 0 : 1
        rescue StandardError => e
          result = {
            "skill" => "youtube.song_search",
            "generated_at" => Time.now.iso8601,
            "status" => "error",
            "outcome" => "failed",
            "error" => {
              "class" => e.class.name,
              "message" => e.message
            },
            "verification" => verification(
              read_only: false,
              browser_launch_attempted: false,
              complete: false,
              final_state: "failed",
              dry_run: dry_run?,
              input_type: "unknown"
            )
          }
          log_path = write_log(result)
          result["task_log"] = log_path if log_path
          puts JSON.pretty_generate(result)
          1
        end

        private

        def process_query(query)
          url = youtube_search_url(query)
          confirm? ? launch(input_type: "search_query", query: query, url: url) : plan(input_type: "search_query", query: query, url: url)
        end

        def process_direct_url(raw_url)
          normalized = normalize_youtube_url(raw_url)

          unless normalized["ok"]
            return blocked_for_input(
              normalized["error"],
              input_type: "youtube_url",
              raw_url: raw_url.to_s.strip
            )
          end

          url = normalized["url"]
          confirm? ? launch(input_type: "youtube_url", query: nil, url: url) : plan(input_type: "youtube_url", query: nil, url: url)
        end

        def plan(input_type:, query:, url:)
          out = {
            "skill" => "youtube.song_search",
            "generated_at" => Time.now.iso8601,
            "status" => "ok",
            "outcome" => "awaiting_confirmation",
            "input_type" => input_type,
            "url" => url,
            "launcher" => launcher_name,
            "recommendation" => confirmation_recommendation(input_type),
            "verification" => verification(
              read_only: true,
              browser_launch_attempted: false,
              complete: false,
              final_state: "awaiting_confirmation",
              dry_run: dry_run?,
              input_type: input_type
            )
          }
          out["query"] = query if query
          out
        end

        def launch(input_type:, query:, url:)
          launcher = launcher_name

          unless launcher_available?(launcher)
            return {
              "skill" => "youtube.song_search",
              "generated_at" => Time.now.iso8601,
              "status" => "error",
              "outcome" => "failed",
              "input_type" => input_type,
              "query" => query,
              "url" => url,
              "launcher" => launcher,
              "recommendation" => "Browser launcher not found. Install xdg-utils or set SOUL_YOUTUBE_LAUNCHER to a valid executable.",
              "verification" => verification(
                read_only: false,
                browser_launch_attempted: false,
                complete: false,
                final_state: "failed",
                dry_run: dry_run?,
                input_type: input_type
              )
            }.compact
          end

          if dry_run?
            return {
              "skill" => "youtube.song_search",
              "generated_at" => Time.now.iso8601,
              "status" => "ok",
              "outcome" => "complete",
              "input_type" => input_type,
              "query" => query,
              "url" => url,
              "launcher" => launcher,
              "recommendation" => "Dry-run confirmed. Browser launch was skipped.",
              "verification" => verification(
                read_only: false,
                browser_launch_attempted: false,
                complete: true,
                final_state: "complete",
                dry_run: true,
                input_type: input_type
              )
            }.compact
          end

          stdout, stderr, status = Open3.capture3(launcher, url)

          if status.success?
            {
              "skill" => "youtube.song_search",
              "generated_at" => Time.now.iso8601,
              "status" => "ok",
              "outcome" => "complete",
              "input_type" => input_type,
              "query" => query,
              "url" => url,
              "launcher" => launcher,
              "launcher_exit_status" => status.exitstatus,
              "recommendation" => launch_recommendation(input_type),
              "verification" => verification(
                read_only: false,
                browser_launch_attempted: true,
                complete: true,
                final_state: "complete",
                dry_run: false,
                input_type: input_type
              )
            }.compact
          else
            {
              "skill" => "youtube.song_search",
              "generated_at" => Time.now.iso8601,
              "status" => "error",
              "outcome" => "failed",
              "input_type" => input_type,
              "query" => query,
              "url" => url,
              "launcher" => launcher,
              "launcher_exit_status" => status.exitstatus,
              "launcher_stdout" => scrub_output(stdout),
              "launcher_stderr" => scrub_output(stderr),
              "recommendation" => "Browser launch failed. Review launcher output and desktop environment configuration.",
              "verification" => verification(
                read_only: false,
                browser_launch_attempted: true,
                complete: false,
                final_state: "failed",
                dry_run: false,
                input_type: input_type
              )
            }.compact
          end
        end

        def blocked_for_input(message, query: nil, input_type: nil, raw_url: nil)
          out = {
            "skill" => "youtube.song_search",
            "generated_at" => Time.now.iso8601,
            "status" => "warning",
            "outcome" => "blocked_for_input",
            "recommendation" => message,
            "verification" => verification(
              read_only: true,
              browser_launch_attempted: false,
              complete: false,
              final_state: "blocked_for_input",
              dry_run: dry_run?,
              input_type: input_type || "unknown"
            )
          }
          out["query"] = query if query
          out["input_type"] = input_type if input_type
          out["raw_url"] = raw_url if raw_url
          out
        end

        def youtube_search_url(query)
          encoded = URI.encode_www_form_component(query)
          "https://www.youtube.com/results?search_query=#{encoded}"
        end

        def normalize_youtube_url(raw_url)
          value = raw_url.to_s.strip
          return { "ok" => false, "error" => "Missing YouTube URL." } if value.empty?

          uri = parse_uri(value)
          return { "ok" => false, "error" => "Invalid URL. Provide a YouTube watch URL or youtu.be share URL." } unless uri

          host = uri.host.to_s.downcase.sub(/\Awww\./, "")
          case host
          when "youtube.com", "m.youtube.com", "music.youtube.com"
            normalize_youtube_dot_com(uri)
          when "youtu.be"
            normalize_youtu_be(uri)
          else
            { "ok" => false, "error" => "Unsupported URL host. Only youtube.com, music.youtube.com, m.youtube.com, and youtu.be are accepted." }
          end
        end

        def normalize_youtube_dot_com(uri)
          if uri.path == "/watch"
            video_id = query_params(uri)["v"].to_s.strip
            return invalid_video_id unless valid_video_id?(video_id)

            { "ok" => true, "url" => "https://www.youtube.com/watch?v=#{video_id}" }
          elsif uri.path.start_with?("/shorts/")
            video_id = uri.path.split("/")[2].to_s.strip
            return invalid_video_id unless valid_video_id?(video_id)

            { "ok" => true, "url" => "https://www.youtube.com/watch?v=#{video_id}" }
          else
            { "ok" => false, "error" => "Unsupported YouTube URL path. Use /watch?v=<video_id>, /shorts/<video_id>, or youtu.be/<video_id>." }
          end
        end

        def normalize_youtu_be(uri)
          video_id = uri.path.to_s.sub(%r{\A/}, "").split("/").first.to_s.strip
          return invalid_video_id unless valid_video_id?(video_id)

          { "ok" => true, "url" => "https://www.youtube.com/watch?v=#{video_id}" }
        end

        def invalid_video_id
          { "ok" => false, "error" => "Invalid or missing YouTube video ID." }
        end

        def valid_video_id?(video_id)
          video_id.match?(/\A[A-Za-z0-9_-]{6,20}\z/)
        end

        def parse_uri(value)
          uri = URI.parse(value)
          return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          return nil unless %w[http https].include?(uri.scheme)

          uri
        rescue URI::InvalidURIError
          nil
        end

        def query_params(uri)
          URI.decode_www_form(uri.query.to_s).to_h
        rescue ArgumentError
          {}
        end

        def normalize_query(value)
          value.to_s.strip.gsub(/\s+/, " ")
        end

        def option_value(flag)
          idx = @argv.index(flag)
          return nil unless idx

          @argv[idx + 1]
        end

        def positional_query
          remaining = []
          skip = false

          @argv.each_with_index do |arg, idx|
            if skip
              skip = false
              next
            end

            if arg.start_with?("--")
              skip = %w[--query --song --url].include?(arg) && @argv[idx + 1]
              next
            end

            remaining << arg
          end

          remaining.join(" ")
        end

        def confirm?
          @argv.include?("--confirm")
        end

        def dry_run?
          @argv.include?("--dry-run")
        end

        def launcher_name
          @env["SOUL_YOUTUBE_LAUNCHER"].to_s.strip.empty? ? DEFAULT_LAUNCHER : @env["SOUL_YOUTUBE_LAUNCHER"].to_s.strip
        end

        def launcher_available?(launcher)
          return File.executable?(launcher) if launcher.include?("/")

          @env.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
            File.executable?(File.join(dir, launcher))
          end
        end

        def confirmation_recommendation(input_type)
          if input_type == "youtube_url"
            "Review the normalized YouTube watch URL and confirm before opening the browser."
          else
            "Review the YouTube search URL and confirm before opening the browser. Song-name queries open search results unless a resolver is added later."
          end
        end

        def launch_recommendation(input_type)
          if input_type == "youtube_url"
            "YouTube watch URL opened in the default browser."
          else
            "YouTube search opened in the default browser."
          end
        end

        def verification(read_only:, browser_launch_attempted:, complete:, final_state:, dry_run:, input_type:)
          {
            "read_only" => read_only,
            "network_used" => false,
            "browser_launch_attempted" => browser_launch_attempted,
            "download_attempted" => false,
            "scraping_attempted" => false,
            "ad_bypass_attempted" => false,
            "persistent_process_started" => false,
            "secrets_printed" => false,
            "api_key_values_printed" => false,
            "direct_video_url_supported" => true,
            "search_query_resolves_video" => false,
            "input_type" => input_type,
            "dry_run" => dry_run,
            "complete" => complete,
            "final_state" => final_state
          }
        end

        def terminal_success?(result)
          return true if result["status"] == "ok"
          return true if result["outcome"] == "awaiting_confirmation"

          false
        end

        def write_log(result)
          dir = File.join(ROOT, "Soul", "logs", "tasks")
          FileUtils.mkdir_p(dir)
          stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
          path = File.join(dir, "#{stamp}-youtube.song_search.json")
          File.write(path, JSON.pretty_generate(result) + "\n")
          path.sub("#{ROOT}/", "")
        rescue StandardError
          nil
        end

        def scrub_output(value)
          text = value.to_s
          return "" if text.empty?

          text.lines.first(20).join.strip
        end

        def help_text
          <<~TEXT
            youtube.song_search

            Opens either:
              - a YouTube search URL for a requested song/query, or
              - a normalized direct YouTube watch URL when --url is provided.

            Supported platform:
              Linux only.

            Usage:
              ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --plan-only
              ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --confirm
              ruby Soul/skills/youtube/song_search.rb --url "https://youtu.be/dQw4w9WgXcQ" --plan-only
              ruby Soul/skills/youtube/song_search.rb --url "https://www.youtube.com/watch?v=dQw4w9WgXcQ" --confirm
              ruby Soul/skills/youtube/song_search.rb --query "Test Song" --confirm --dry-run

            Options:
              --query TEXT      Song/search query.
              --song TEXT       Alias for --query.
              --url URL         YouTube watch/share/shorts URL. Normalized to a watch URL.
              --plan-only       Return an awaiting_confirmation plan. This is the default unless --confirm is provided.
              --confirm         Open the constructed URL using xdg-open or SOUL_YOUTUBE_LAUNCHER.
              --dry-run         Do not launch the browser even when --confirm is provided.
              --help            Show this help.

            Boundary:
              - Linux only.
              - Uses xdg-open by default.
              - Does not download media.
              - Does not scrape YouTube.
              - Does not resolve song-name searches to video IDs.
              - Does not bypass ads or access controls.
              - Does not start a persistent process inside Soul/.
          TEXT
        end
      end
    end
  end

  exit SoulSkills::YouTube::SongSearch.new(ARGV).run
RUBY

File.write(path, replacement)
puts "Replaced #{path}: added direct YouTube URL support."
exit(system("ruby", "-c", path) ? 0 : 1)
