# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "uri"
require_relative "youtube_api_client"
require_relative "youtube_oauth_service"

module SoulCore
  class YouTubeDescriptionSyncService
    CONFIRMATION = "UPDATE_YOUTUBE_DESCRIPTIONS"
    OAUTH_CONFIRMATION = "AUTHORIZE_YOUTUBE_DESCRIPTION_SYNC"
    OAUTH_SCOPES = [
      "https://www.googleapis.com/auth/youtube.readonly",
      "https://www.googleapis.com/auth/youtube.force-ssl"
    ].freeze
    OAUTH_CREDENTIAL_NAME = "oauth-description-sync.json"
    MAX_MAPPING_BYTES = 128 * 1024
    MAX_DESCRIPTION_BYTES = 5_000
    MAX_VIDEOS = 50
    VIDEO_ID_PATTERN = /\A[A-Za-z0-9_-]{11}\z/
    NOCTHOUGHTS_HOST = "nocthoughts.com"

    class ValidationError < StandardError; end

    def self.oauth(root: Dir.pwd, api: YouTubeApiClient.new, **options)
      YouTubeOAuthService.new(
        root: root,
        api: api,
        scopes: OAUTH_SCOPES,
        credential_name: OAUTH_CREDENTIAL_NAME,
        confirmation: OAUTH_CONFIRMATION,
        operation: "authorize_youtube_description_sync",
        **options
      )
    end

    def initialize(root: Dir.pwd, oauth: nil, api: YouTubeApiClient.new, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @api = api
      @oauth = oauth || self.class.oauth(root: @root, api: @api, clock: clock)
      @clock = clock
    end

    def preview(mapping_path:)
      mapping = read_mapping(mapping_path)
      access = @oauth.access_context
      verify_expected_channel!(access)
      plan = build_plan(mapping, access)
      scope = sync_scope(mapping, access, plan)
      changes = public_changes(plan)
      if changes.none? { |change| change.fetch("change_required") }
        return outcome("complete", true, "all mapped NOC Thoughts links are already current", data: {
          "mapping_path" => mapping.fetch("path"),
          "mapping_sha256" => mapping.fetch("sha256"),
          "channel_id" => access.fetch("channel_id"),
          "changes" => changes,
          "idempotent_replay" => true
        })
      end

      outcome("blocked_for_human_review", true, "exact YouTube description changes require operator approval", data: {
        "confirmation_phrase" => CONFIRMATION,
        "expected_digest" => digest(scope),
        "preview_scope" => scope,
        "changes" => changes
      })
    rescue ValidationError, YouTubeOAuthService::CredentialError => error
      outcome("awaiting_input", false, safe_message(error))
    rescue YouTubeApiClient::ApiError, KeyError, Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
      outcome("blocked_for_human_review", false, safe_message(error))
    end

    def execute(mapping_path:, confirmation:, expected_digest:)
      lock = nil
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?

      lock = acquire_execution_lock
      mapping = read_mapping(mapping_path)
      access = @oauth.access_context
      verify_expected_channel!(access)
      plan = build_plan(mapping, access)
      scope = sync_scope(mapping, access, plan)
      return outcome("blocked_for_human_review", false, "YouTube description confirmation did not match") unless confirmation == CONFIRMATION
      return outcome("blocked_for_human_review", false, "YouTube description scope changed; preview again") unless secure_compare(expected_digest, digest(scope))

      changes = plan.select { |entry| entry.fetch("change_required") }
      return outcome("complete", true, "all mapped NOC Thoughts links are already current", data: { "changes" => public_changes(plan), "idempotent_replay" => true }) if changes.empty?

      snapshot_path = write_snapshot(mapping, access, scope, plan)
      receipt_path = receipt_path_for(scope)
      completed = []
      attempted = nil
      write_record(receipt_path, receipt_value(mapping, access, scope, plan, snapshot_path, completed, attempted, "in_progress"), replace: true)

      changes.each do |entry|
        attempted = entry.fetch("video_id")
        write_record(receipt_path, receipt_value(mapping, access, scope, plan, snapshot_path, completed, attempted, "in_progress"), replace: true)
        response = @api.update_video_snippet(
          access_token: access.fetch("access_token"),
          video_id: entry.fetch("video_id"),
          snippet: entry.fetch("after_snippet")
        )
        verify_update_response!(response, entry, access)
        completed << entry.fetch("video_id")
        attempted = nil
        write_record(receipt_path, receipt_value(mapping, access, scope, plan, snapshot_path, completed, attempted, "in_progress"), replace: true)
      end

      receipt = receipt_value(mapping, access, scope, plan, snapshot_path, completed, nil, "complete")
      write_record(receipt_path, receipt, replace: true)
      outcome("complete", true, "mapped NOC Thoughts description links were updated", data: {
        "receipt" => public_receipt(receipt),
        "changes" => public_changes(plan)
      }, mutation: "youtube_descriptions_updated")
    rescue Interrupt
      if defined?(receipt_path) && receipt_path && defined?(mapping) && mapping && defined?(access) && access && defined?(scope) && scope && defined?(plan) && plan
        completed ||= []
        attempted ||= nil
        snapshot_path ||= nil
        receipt = receipt_value(mapping, access, scope, plan, snapshot_path, completed, attempted, "canceled")
        write_record(receipt_path, receipt, replace: true)
        mutation = if !attempted.to_s.empty?
                     "youtube_description_remote_state_requires_review"
                   elsif completed.empty?
                     "none"
                   else
                     "youtube_descriptions_partially_updated"
                   end
        outcome("canceled", false, "YouTube description sync was canceled; inspect the receipt and any attempted remote video", data: { "receipt" => public_receipt(receipt) }, mutation: mutation)
      else
        outcome("canceled", false, "YouTube description sync was canceled before mutation")
      end
    rescue ValidationError, YouTubeOAuthService::CredentialError => error
      failure_outcome(error, locals: binding)
    rescue YouTubeApiClient::ApiError, KeyError, Errno::ENOENT, Errno::EACCES, JSON::ParserError, IOError, SystemCallError => error
      failure_outcome(error, locals: binding)
    ensure
      lock&.flock(File::LOCK_UN)
      lock&.close
    end

    private

    def read_mapping(path)
      expanded = File.expand_path(path.to_s)
      raise ValidationError, "YouTube description mapping is required" if path.to_s.empty?
      raise ValidationError, "YouTube description mapping must be a regular non-symlink file" unless File.file?(expanded) && !File.symlink?(expanded)
      raise ValidationError, "YouTube description mapping exceeds size limit" unless File.size(expanded).between?(1, MAX_MAPPING_BYTES)

      document = JSON.parse(File.binread(expanded, MAX_MAPPING_BYTES))
      raise ValidationError, "YouTube description mapping schema is invalid" unless document["schema_version"] == "soul.youtube.description_links.v1"
      raise ValidationError, "YouTube description mapping channel is invalid" unless document["channel_id"] == YouTubeOAuthService::EXPECTED_CHANNEL_ID
      entries = document["videos"]
      raise ValidationError, "YouTube description mapping must contain 1..#{MAX_VIDEOS} videos" unless entries.is_a?(Array) && entries.length.between?(1, MAX_VIDEOS)

      normalized = entries.map do |entry|
        raise ValidationError, "YouTube description mapping entry is invalid" unless entry.is_a?(Hash)
        video_id = entry["video_id"].to_s
        from_url = canonical_nocthoughts_url(entry["expected_current_url"])
        to_url = canonical_nocthoughts_url(entry["article_url"])
        raise ValidationError, "YouTube description mapping video ID is invalid" unless video_id.match?(VIDEO_ID_PATTERN)
        raise ValidationError, "YouTube description mapping replacement must change the URL" if from_url == to_url

        { "video_id" => video_id, "expected_current_url" => from_url, "article_url" => to_url }
      end
      raise ValidationError, "YouTube description mapping contains duplicate video IDs" unless normalized.map { |entry| entry.fetch("video_id") }.uniq.length == normalized.length

      {
        "path" => expanded,
        "sha256" => Digest::SHA256.file(expanded).hexdigest,
        "entries" => normalized
      }
    rescue JSON::ParserError
      raise ValidationError, "YouTube description mapping is invalid JSON"
    end

    def canonical_nocthoughts_url(value)
      text = value.to_s
      uri = URI.parse(text)
      valid = uri.is_a?(URI::HTTPS) &&
              uri.host == NOCTHOUGHTS_HOST &&
              uri.userinfo.nil? &&
              uri.port == 443 &&
              uri.query.nil? &&
              uri.fragment.nil? &&
              !uri.path.to_s.empty?
      raise ValidationError, "YouTube description mapping URL must use https://#{NOCTHOUGHTS_HOST}/" unless valid
      text
    rescue URI::InvalidURIError
      raise ValidationError, "YouTube description mapping URL is invalid"
    end

    def build_plan(mapping, access)
      entries = mapping.fetch("entries")
      videos = @api.videos(access_token: access.fetch("access_token"), video_ids: entries.map { |entry| entry.fetch("video_id") })
      by_id = videos.to_h { |video| [video.fetch("id").to_s, video] }
      expected_ids = entries.map { |entry| entry.fetch("video_id") }
      raise ValidationError, "YouTube did not return every mapped video" unless by_id.keys.sort == expected_ids.sort

      entries.map do |mapping_entry|
        video = by_id.fetch(mapping_entry.fetch("video_id"))
        snippet = video.fetch("snippet")
        raise ValidationError, "mapped YouTube video belongs to an unexpected channel" unless snippet.fetch("channelId").to_s == access.fetch("channel_id")
        before = writable_snippet(snippet)
        after_description, current_url, changed = replace_managed_url(
          before.fetch("description"),
          mapping_entry.fetch("expected_current_url"),
          mapping_entry.fetch("article_url")
        )
        after = deep_copy(before).merge("description" => after_description)
        {
          "video_id" => mapping_entry.fetch("video_id"),
          "title" => before.fetch("title"),
          "before_url" => current_url,
          "after_url" => mapping_entry.fetch("article_url"),
          "before_snippet" => before,
          "after_snippet" => after,
          "before_description_sha256" => Digest::SHA256.hexdigest(before.fetch("description")),
          "after_description_sha256" => Digest::SHA256.hexdigest(after_description),
          "before_snippet_sha256" => digest(before),
          "after_snippet_sha256" => digest(after),
          "change_required" => changed
        }
      end
    end

    def writable_snippet(snippet)
      title = snippet["title"].to_s
      category_id = snippet["categoryId"].to_s
      description = snippet["description"].to_s
      raise ValidationError, "YouTube video title is missing" if title.empty?
      raise ValidationError, "YouTube video category is missing" if category_id.empty?
      raise ValidationError, "YouTube video description is invalid" unless description.valid_encoding? && description.bytesize.between?(1, MAX_DESCRIPTION_BYTES)

      result = {
        "title" => title,
        "categoryId" => category_id,
        "description" => description
      }
      result["tags"] = Array(snippet["tags"]).map(&:to_s) if snippet.key?("tags")
      result["defaultLanguage"] = snippet["defaultLanguage"].to_s if snippet.key?("defaultLanguage")
      result
    end

    def replace_managed_url(description, expected_url, article_url)
      heading_count = description.scan(/(?:\A|\n)NOC Thoughts\r?(?=\n|\z)/).length
      raise ValidationError, "YouTube description must contain exactly one standalone NOC Thoughts heading" unless heading_count == 1

      pattern = /(?:\A|\n)NOC Thoughts\r?\n\Khttps:\/\/nocthoughts\.com\/[^\r\n]*(?=\r?(?:\n|\z))/
      matches = description.enum_for(:scan, pattern).map { Regexp.last_match }
      raise ValidationError, "YouTube description must contain exactly one managed NOC Thoughts URL" unless matches.length == 1
      current_url = matches.first[0]
      unless [expected_url, article_url].include?(current_url)
        raise ValidationError, "YouTube description contains an unexpected NOC Thoughts URL"
      end
      return [description.dup, current_url, false] if current_url == article_url

      start = matches.first.begin(0)
      finish = matches.first.end(0)
      updated = description.dup
      updated[start...finish] = article_url
      raise ValidationError, "YouTube description exceeds size limit after replacement" if updated.bytesize > MAX_DESCRIPTION_BYTES
      [updated, current_url, true]
    end

    def sync_scope(mapping, access, plan)
      {
        "operation" => "update_youtube_descriptions",
        "google_project_id" => access.fetch("project_id"),
        "channel_id" => access.fetch("channel_id"),
        "channel_title" => access.fetch("channel_title"),
        "mapping_sha256" => mapping.fetch("sha256"),
        "videos" => plan.map do |entry|
          entry.slice(
            "video_id", "title", "before_url", "after_url",
            "before_description_sha256", "after_description_sha256",
            "before_snippet_sha256", "after_snippet_sha256", "change_required"
          )
        end,
        "preserve" => %w[title categoryId tags defaultLanguage status],
        "upload" => false,
        "visibility_mutation" => false
      }
    end

    def verify_update_response!(response, entry, access)
      raise ValidationError, "YouTube update returned an unexpected video ID" unless response.fetch("id").to_s == entry.fetch("video_id")
      snippet = response.fetch("snippet")
      returned_channel = snippet["channelId"].to_s
      raise ValidationError, "YouTube update returned an unexpected channel" unless returned_channel.empty? || returned_channel == access.fetch("channel_id")
      returned = writable_snippet(snippet)
      raise ValidationError, "YouTube update response does not match the exact proposed snippet" unless digest(returned) == entry.fetch("after_snippet_sha256")
    end

    def verify_expected_channel!(access)
      raise ValidationError, "OAuth project does not match the authorized publisher project" unless access.fetch("project_id") == YouTubeOAuthService::PROJECT_ID
      raise ValidationError, "authenticated channel does not match Soul Slash Synthesis" unless access.fetch("channel_id") == YouTubeOAuthService::EXPECTED_CHANNEL_ID
    end

    def write_snapshot(mapping, access, scope, plan)
      path = snapshot_path_for(scope)
      secure_directory(File.dirname(path))
      if File.exist?(path) || File.symlink?(path)
        raise ValidationError, "YouTube description snapshot must be a regular non-symlink file" unless File.file?(path) && !File.symlink?(path)
        raise ValidationError, "YouTube description snapshot permissions must be owner-only" unless (File.stat(path).mode & 0o077).zero?
        existing = JSON.parse(File.binread(path, MAX_MAPPING_BYTES))
        raise ValidationError, "existing YouTube description snapshot scope differs" unless existing["scope_digest"] == digest(scope)
        return path
      end
      value = {
        "schema_version" => "soul.youtube.description_snapshot.v1",
        "created_at" => @clock.call.iso8601,
        "channel_id" => access.fetch("channel_id"),
        "mapping_path" => mapping.fetch("path"),
        "mapping_sha256" => mapping.fetch("sha256"),
        "scope_digest" => digest(scope),
        "videos" => plan.map do |entry|
          {
            "video_id" => entry.fetch("video_id"),
            "before_snippet" => entry.fetch("before_snippet"),
            "after_snippet" => entry.fetch("after_snippet"),
            "change_required" => entry.fetch("change_required")
          }
        end
      }
      write_record(path, value, replace: false)
      path
    rescue JSON::ParserError
      raise ValidationError, "existing YouTube description snapshot is invalid"
    end

    def receipt_value(mapping, access, scope, plan, snapshot_path, completed, attempted, state)
      changed_ids = plan.select { |entry| entry.fetch("change_required") }.map { |entry| entry.fetch("video_id") }
      {
        "schema_version" => "soul.youtube.description_sync_receipt.v1",
        "state" => state,
        "updated_at" => @clock.call.iso8601,
        "channel_id" => access.fetch("channel_id"),
        "mapping_sha256" => mapping.fetch("sha256"),
        "scope_digest" => digest(scope),
        "snapshot_path" => snapshot_path,
        "planned_video_ids" => changed_ids,
        "completed_video_ids" => completed.dup,
        "attempted_video_id" => attempted,
        "remaining_video_ids" => changed_ids - completed,
        "automatic_rollback" => false
      }
    end

    def public_receipt(receipt)
      receipt.slice(
        "state", "updated_at", "channel_id", "mapping_sha256", "scope_digest",
        "snapshot_path", "planned_video_ids", "completed_video_ids",
        "attempted_video_id", "remaining_video_ids", "automatic_rollback"
      )
    end

    def public_changes(plan)
      plan.map do |entry|
        entry.slice(
          "video_id", "title", "before_url", "after_url",
          "before_description_sha256", "after_description_sha256", "change_required"
        ).merge("watch_url" => "https://www.youtube.com/watch?v=#{entry.fetch('video_id')}")
      end
    end

    def failure_outcome(error, locals:)
      receipt_path = locals.local_variable_defined?(:receipt_path) ? locals.local_variable_get(:receipt_path) : nil
      mapping = locals.local_variable_defined?(:mapping) ? locals.local_variable_get(:mapping) : nil
      access = locals.local_variable_defined?(:access) ? locals.local_variable_get(:access) : nil
      scope = locals.local_variable_defined?(:scope) ? locals.local_variable_get(:scope) : nil
      plan = locals.local_variable_defined?(:plan) ? locals.local_variable_get(:plan) : nil
      snapshot_path = locals.local_variable_defined?(:snapshot_path) ? locals.local_variable_get(:snapshot_path) : nil
      completed = locals.local_variable_defined?(:completed) ? Array(locals.local_variable_get(:completed)) : []
      attempted = locals.local_variable_defined?(:attempted) ? locals.local_variable_get(:attempted) : nil
      if receipt_path && mapping && access && scope && plan && snapshot_path
        uncertain_remote_state = !attempted.to_s.empty?
        state = completed.empty? && !uncertain_remote_state ? "failed" : "partial"
        receipt = receipt_value(mapping, access, scope, plan, snapshot_path, completed, attempted, state)
        write_record(receipt_path, receipt, replace: true)
        mutation = if uncertain_remote_state
                     "youtube_description_remote_state_requires_review"
                   elsif completed.empty?
                     "none"
                   else
                     "youtube_descriptions_partially_updated"
                   end
        return outcome("blocked_for_human_review", false, safe_message(error), data: { "receipt" => public_receipt(receipt) }, mutation: mutation)
      end
      outcome("blocked_for_human_review", false, safe_message(error))
    rescue IOError, SystemCallError
      outcome("blocked_for_human_review", false, safe_message(error))
    end

    def write_record(path, value, replace:)
      raise ValidationError, "YouTube description record already exists" if !replace && (File.exist?(path) || File.symlink?(path))
      directory = File.dirname(path)
      secure_directory(directory)
      temporary = "#{path}.tmp-#{Process.pid}-#{Digest::SHA256.hexdigest(@clock.call.iso8601)[0, 8]}"
      File.write(temporary, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
      File.rename(temporary, path)
      File.chmod(0o600, path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def acquire_execution_lock
      directory = runtime_directory
      secure_directory(directory)
      lock = File.open(File.join(directory, "execution.lock"), File::RDWR | File::CREAT, 0o600)
      unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        lock.close
        raise ValidationError, "another YouTube description sync is active"
      end
      lock
    end

    def secure_directory(path)
      expanded = File.expand_path(path)
      raise ValidationError, "YouTube description runtime path is outside the Soul root" unless expanded.start_with?(@root + File::SEPARATOR)

      relative = expanded.delete_prefix(@root + File::SEPARATOR)
      current = @root
      relative.split(File::SEPARATOR).each do |component|
        current = File.join(current, component)
        raise ValidationError, "YouTube description runtime path contains a symlink" if File.symlink?(current)
      end
      FileUtils.mkdir_p(expanded, mode: 0o700)
      raise ValidationError, "YouTube description runtime path is not a directory" unless File.directory?(expanded) && !File.symlink?(expanded)
      File.chmod(0o700, expanded)
    end

    def runtime_directory = File.join(@root, "Soul", "runtime", "youtube_description_sync")
    def snapshot_path_for(scope) = File.join(runtime_directory, "snapshots", "#{digest(scope)}.json")
    def receipt_path_for(scope) = File.join(runtime_directory, "receipts", "#{digest(scope)}.json")
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def deep_copy(value) = JSON.parse(JSON.generate(value))
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    def safe_message(error) = error.message.to_s.gsub(/ya29\.[A-Za-z0-9._-]+|1\/\/[A-Za-z0-9._-]+/, "[REDACTED]").slice(0, 500)
    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
