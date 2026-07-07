#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require "uri"
require "open3"
require "shellwords"

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

        query = normalize_query(option_value("--query") || option_value("--song") || positional_query)

        result =
          if query.empty?
            blocked_for_input("Missing song/search query. Provide --query \"Song Name\".")
          elsif query.length > MAX_QUERY_LENGTH
            blocked_for_input("Query is too long. Maximum supported length is #{MAX_QUERY_LENGTH} characters.", query: query)
          else
            process_query(query)
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
            dry_run: dry_run?
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

        if confirm?
          launch(query, url)
        else
          plan(query, url)
        end
      end

      def plan(query, url)
        {
          "skill" => "youtube.song_search",
          "generated_at" => Time.now.iso8601,
          "status" => "ok",
          "outcome" => "awaiting_confirmation",
          "query" => query,
          "url" => url,
          "launcher" => launcher_name,
          "recommendation" => "Review the YouTube search URL and confirm before opening the browser.",
          "verification" => verification(
            read_only: true,
            browser_launch_attempted: false,
            complete: false,
            final_state: "awaiting_confirmation",
            dry_run: dry_run?
          )
        }
      end

      def launch(query, url)
        launcher = launcher_name

        unless launcher_available?(launcher)
          return {
            "skill" => "youtube.song_search",
            "generated_at" => Time.now.iso8601,
            "status" => "error",
            "outcome" => "failed",
            "query" => query,
            "url" => url,
            "launcher" => launcher,
            "recommendation" => "Browser launcher not found. Install xdg-utils or set SOUL_YOUTUBE_LAUNCHER to a valid executable.",
            "verification" => verification(
              read_only: false,
              browser_launch_attempted: false,
              complete: false,
              final_state: "failed",
              dry_run: dry_run?
            )
          }
        end

        if dry_run?
          return {
            "skill" => "youtube.song_search",
            "generated_at" => Time.now.iso8601,
            "status" => "ok",
            "outcome" => "complete",
            "query" => query,
            "url" => url,
            "launcher" => launcher,
            "recommendation" => "Dry-run confirmed. Browser launch was skipped.",
            "verification" => verification(
              read_only: false,
              browser_launch_attempted: false,
              complete: true,
              final_state: "complete",
              dry_run: true
            )
          }
        end

        stdout, stderr, status = Open3.capture3(launcher, url)

        if status.success?
          {
            "skill" => "youtube.song_search",
            "generated_at" => Time.now.iso8601,
            "status" => "ok",
            "outcome" => "complete",
            "query" => query,
            "url" => url,
            "launcher" => launcher,
            "launcher_exit_status" => status.exitstatus,
            "recommendation" => "YouTube search opened in the default browser.",
            "verification" => verification(
              read_only: false,
              browser_launch_attempted: true,
              complete: true,
              final_state: "complete",
              dry_run: false
            )
          }
        else
          {
            "skill" => "youtube.song_search",
            "generated_at" => Time.now.iso8601,
            "status" => "error",
            "outcome" => "failed",
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
              dry_run: false
            )
          }
        end
      end

      def blocked_for_input(message, query: nil)
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
            dry_run: dry_run?
          )
        }
        out["query"] = query if query
        out
      end

      def youtube_search_url(query)
        encoded = URI.encode_www_form_component(query)
        "https://www.youtube.com/results?search_query=#{encoded}"
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
            skip = %w[--query --song].include?(arg) && @argv[idx + 1]
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

      def verification(read_only:, browser_launch_attempted:, complete:, final_state:, dry_run:)
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

          Opens a YouTube search URL for a requested song/query in the default Linux browser.

          Usage:
            ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --plan-only
            ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --confirm
            ruby Soul/skills/youtube/song_search.rb --song "Miles Davis So What" --confirm
            ruby Soul/skills/youtube/song_search.rb --query "Test Song" --confirm --dry-run

          Options:
            --query TEXT      Song/search query.
            --song TEXT       Alias for --query.
            --plan-only       Return an awaiting_confirmation plan. This is the default unless --confirm is provided.
            --confirm         Open the constructed URL using xdg-open or SOUL_YOUTUBE_LAUNCHER.
            --dry-run         Do not launch the browser even when --confirm is provided.
            --help            Show this help.

          Boundary:
            - Linux only.
            - Uses xdg-open by default.
            - Does not download media.
            - Does not scrape YouTube.
            - Does not bypass ads or access controls.
            - Does not start a persistent process inside Soul/.
        TEXT
      end
    end
  end
end

exit SoulSkills::YouTube::SongSearch.new(ARGV).run
