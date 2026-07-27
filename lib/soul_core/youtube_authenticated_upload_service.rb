# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "music_project_store"
require_relative "youtube_api_client"
require_relative "youtube_oauth_service"

module SoulCore
  class YouTubeAuthenticatedUploadService
    CONFIRMATION = "UPLOAD_YOUTUBE_VIDEO"
    VISIBILITIES = %w[private unlisted public].freeze
    REQUIRED_FILES = %w[video.mp4 thumbnail.png youtube-description.txt upload.json].freeze
    MAX_RECORD_BYTES = 8 * 1024 * 1024
    MAX_DESCRIPTION_BYTES = 5_000
    MAX_TITLE_CHARACTERS = 100
    MAX_THUMBNAIL_BYTES = 2 * 1024 * 1024
    MAX_VIDEO_BYTES = 256 * 1024 * 1024 * 1024

    class ValidationError < StandardError; end

    def initialize(root: Dir.pwd, export_root: File.join(Dir.home, "Music", "soul-music"), project_store: nil, oauth: nil, api: YouTubeApiClient.new, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @export_root = File.expand_path(export_root)
      @store = project_store || MusicProjectStore.new(root: @root)
      @api = api
      @oauth = oauth || YouTubeOAuthService.new(root: @root, api: @api, clock: clock)
      @clock = clock
    end

    def preview(project_id:, candidate_id:, visual_id:, visibility: "private")
      context = package_context(project_id, candidate_id, visual_id, visibility)
      existing = existing_receipt(context)
      return outcome("complete", true, "this exact YouTube package already has an upload receipt", data: { "upload" => public_receipt(existing), "idempotent_replay" => true }) if existing

      access = @oauth.access_context
      verify_expected_channel!(access)
      scope = upload_scope(context, access)
      outcome("blocked_for_human_review", true, "one exact YouTube upload requires operator approval", data: {
        "confirmation_phrase" => CONFIRMATION,
        "expected_digest" => digest(scope),
        "preview_scope" => scope,
        "notice" => "Google may restrict uploads from an unaudited API project to private viewing."
      })
    rescue ValidationError, YouTubeOAuthService::CredentialError => error
      outcome("awaiting_input", false, safe_message(error))
    rescue YouTubeApiClient::ApiError, KeyError, Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
      outcome("blocked_for_human_review", false, safe_message(error))
    end

    def execute(project_id:, candidate_id:, visual_id:, visibility: "private", confirmation:, expected_digest:, progress: nil)
      video_id = nil
      context = nil
      scope = nil
      access = nil
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      context = package_context(project_id, candidate_id, visual_id, visibility)
      existing = existing_receipt(context)
      return outcome("complete", true, "this exact YouTube package already has an upload receipt", data: { "upload" => public_receipt(existing), "idempotent_replay" => true }) if existing

      access = @oauth.access_context
      verify_expected_channel!(access)
      scope = upload_scope(context, access)
      return outcome("blocked_for_human_review", false, "YouTube upload confirmation did not match") unless confirmation == CONFIRMATION
      return outcome("blocked_for_human_review", false, "YouTube upload scope changed; preview again") unless secure_compare(expected_digest, digest(scope))

      metadata = {
        "snippet" => {
          "title" => context.fetch("title"),
          "description" => context.fetch("description"),
          "categoryId" => context.fetch("category_id")
        },
        "status" => {
          "privacyStatus" => context.fetch("visibility"),
          "selfDeclaredMadeForKids" => context.fetch("made_for_kids"),
          "containsSyntheticMedia" => context.fetch("contains_synthetic_media")
        }
      }
      upload_url = @api.initiate_upload(
        access_token: access.fetch("access_token"),
        metadata: metadata,
        video_size: context.fetch("video_bytes"),
        mime_type: "video/mp4"
      )
      video = @api.upload_video(
        access_token: access.fetch("access_token"),
        upload_url: upload_url,
        path: context.fetch("video_path"),
        mime_type: "video/mp4",
        progress: progress
      )
      video_id = video.fetch("id").to_s
      raise ValidationError, "YouTube returned an invalid video identifier" unless video_id.match?(/\A[A-Za-z0-9_-]{6,20}\z/)
      returned_channel = video.dig("snippet", "channelId").to_s
      raise ValidationError, "YouTube returned a video for an unexpected channel" unless returned_channel.empty? || returned_channel == access.fetch("channel_id")

      actual_privacy = video.dig("status", "privacyStatus").to_s
      actual_privacy = "unknown" unless VISIBILITIES.include?(actual_privacy)
      begin
        @api.set_thumbnail(
          access_token: access.fetch("access_token"),
          video_id: video_id,
          path: context.fetch("thumbnail_path")
        )
      rescue YouTubeApiClient::ApiError => error
        partial = receipt_value(context, scope, access, video_id, actual_privacy, thumbnail_applied: false, state: "partial")
        write_receipt(context.fetch("receipt_path"), partial)
        return outcome("blocked_for_human_review", false, "video uploaded but thumbnail application failed; inspect the private YouTube draft", data: {
          "upload" => public_receipt(partial),
          "api_error" => safe_message(error)
        }, mutation: "youtube_video_uploaded_thumbnail_failed")
      end

      receipt = receipt_value(context, scope, access, video_id, actual_privacy, thumbnail_applied: true, state: "complete")
      write_receipt(context.fetch("receipt_path"), receipt)
      reason = actual_privacy == context.fetch("visibility") ? "YouTube upload completed for human review" : "YouTube uploaded the video with a different visibility; human review is required"
      lifecycle = actual_privacy == context.fetch("visibility") ? "complete" : "blocked_for_human_review"
      outcome(lifecycle, lifecycle == "complete", reason, data: { "upload" => public_receipt(receipt) }, mutation: "youtube_video_uploaded")
    rescue Interrupt
      if video_id && context && scope && access
        canceled = receipt_value(context, scope, access, video_id, "unknown", thumbnail_applied: false, state: "canceled")
        write_receipt(context.fetch("receipt_path"), canceled) unless File.exist?(context.fetch("receipt_path"))
        outcome("canceled", false, "upload was canceled after YouTube returned a video; inspect the remote draft", data: { "upload" => public_receipt(canceled) }, mutation: "youtube_upload_canceled_remote_video")
      else
        outcome("canceled", false, "YouTube upload was canceled; remote state may require human review")
      end
    rescue ValidationError, YouTubeOAuthService::CredentialError => error
      outcome("awaiting_input", false, safe_message(error))
    rescue YouTubeApiClient::ApiError, KeyError, Errno::ENOENT, Errno::EACCES, JSON::ParserError, IOError, SystemCallError => error
      outcome("blocked_for_human_review", false, safe_message(error))
    end

    private

    def package_context(project_id, candidate_id, visual_id, visibility)
      selected_visibility = visibility.to_s
      raise ValidationError, "visibility must be private, unlisted, or public" unless VISIBILITIES.include?(selected_visibility)
      project_path = @store.project_path(project_id)
      receipt_path = File.join(project_path, "publications", "#{candidate_id}-#{visual_id}.json")
      package_receipt = read_json(receipt_path, "YouTube package receipt")
      raise ValidationError, "YouTube package receipt identifies a different project" unless package_receipt["project_id"] == project_id
      raise ValidationError, "YouTube package receipt identifies a different candidate" unless package_receipt["candidate_id"] == candidate_id
      raise ValidationError, "YouTube package receipt identifies a different visual" unless package_receipt["visual_id"] == visual_id

      destination = File.expand_path(package_receipt.fetch("destination"))
      raise ValidationError, "YouTube package destination is outside the finished export root" unless within?(destination, @export_root)
      raise ValidationError, "YouTube package destination must be a regular directory" unless File.directory?(destination) && !File.symlink?(destination)
      files = package_receipt.fetch("files")
      raise ValidationError, "YouTube package file inventory is invalid" unless files.is_a?(Hash) && REQUIRED_FILES.all? { |name| files[name].to_s.match?(/\A[a-f0-9]{64}\z/) }

      paths = REQUIRED_FILES.to_h { |name| [name, File.join(destination, name)] }
      paths.each do |name, path|
        raise ValidationError, "YouTube package #{name} must be a regular non-symlink file" unless File.file?(path) && !File.symlink?(path)
        raise ValidationError, "YouTube package #{name} digest changed" unless Digest::SHA256.file(path).hexdigest == files.fetch(name)
      end

      upload = read_json(paths.fetch("upload.json"), "YouTube upload metadata")
      description = File.binread(paths.fetch("youtube-description.txt"), MAX_DESCRIPTION_BYTES + 1).strip
      title = upload.fetch("title").to_s.strip
      raise ValidationError, "YouTube title must contain 1..#{MAX_TITLE_CHARACTERS} characters" unless title.length.between?(1, MAX_TITLE_CHARACTERS)
      raise ValidationError, "YouTube title contains invalid text" unless title.valid_encoding? && !title.match?(/[<>]/)
      raise ValidationError, "YouTube description must contain 1..#{MAX_DESCRIPTION_BYTES} UTF-8 bytes" unless description.bytesize.between?(1, MAX_DESCRIPTION_BYTES) && description.valid_encoding?
      raise ValidationError, "YouTube description contains invalid text" if description.match?(/[<>]/)
      raise ValidationError, "YouTube upload category must be Music" unless upload["category_id"].to_s == "10"
      raise ValidationError, "YouTube audience declaration is invalid" unless [true, false].include?(upload["made_for_kids"])
      raise ValidationError, "YouTube synthetic-media declaration is invalid" unless [true, false].include?(upload["contains_synthetic_media"])
      video_bytes = File.size(paths.fetch("video.mp4"))
      thumbnail_bytes = File.size(paths.fetch("thumbnail.png"))
      raise ValidationError, "YouTube video must contain 1 byte through 256 GiB" unless video_bytes.between?(1, MAX_VIDEO_BYTES)
      raise ValidationError, "YouTube thumbnail must contain 1 byte through 2 MiB" unless thumbnail_bytes.between?(1, MAX_THUMBNAIL_BYTES)

      {
        "project_id" => project_id,
        "candidate_id" => candidate_id,
        "visual_id" => visual_id,
        "package_destination" => destination,
        "package_receipt_path" => receipt_path,
        "package_receipt_sha256" => Digest::SHA256.file(receipt_path).hexdigest,
        "file_sha256" => REQUIRED_FILES.to_h { |name| [name, files.fetch(name)] },
        "title" => title,
        "description" => description,
        "description_sha256" => Digest::SHA256.hexdigest(description),
        "category_id" => "10",
        "made_for_kids" => upload.fetch("made_for_kids"),
        "contains_synthetic_media" => upload.fetch("contains_synthetic_media"),
        "visibility" => selected_visibility,
        "video_path" => paths.fetch("video.mp4"),
        "video_bytes" => video_bytes,
        "thumbnail_path" => paths.fetch("thumbnail.png"),
        "thumbnail_bytes" => thumbnail_bytes,
        "receipt_path" => File.join(project_path, "publications", "#{candidate_id}-#{visual_id}-youtube-upload.json")
      }
    rescue EOFError
      raise ValidationError, "YouTube description exceeds size limit"
    end

    def upload_scope(context, access)
      {
        "operation" => "upload_youtube_video",
        "project_id" => context.fetch("project_id"),
        "candidate_id" => context.fetch("candidate_id"),
        "visual_id" => context.fetch("visual_id"),
        "google_project_id" => access.fetch("project_id"),
        "channel_id" => access.fetch("channel_id"),
        "channel_title" => access.fetch("channel_title"),
        "package_destination" => context.fetch("package_destination"),
        "package_receipt_sha256" => context.fetch("package_receipt_sha256"),
        "file_sha256" => context.fetch("file_sha256"),
        "title" => context.fetch("title"),
        "description_sha256" => context.fetch("description_sha256"),
        "category_id" => context.fetch("category_id"),
        "made_for_kids" => context.fetch("made_for_kids"),
        "contains_synthetic_media" => context.fetch("contains_synthetic_media"),
        "visibility" => context.fetch("visibility"),
        "video_bytes" => context.fetch("video_bytes"),
        "thumbnail_bytes" => context.fetch("thumbnail_bytes"),
        "notify_subscribers" => false,
        "overwrite" => false
      }
    end

    def verify_expected_channel!(access)
      raise ValidationError, "OAuth project does not match the authorized publisher project" unless access.fetch("project_id") == YouTubeOAuthService::PROJECT_ID
      raise ValidationError, "authenticated channel does not match Soul Slash Synthesis" unless access.fetch("channel_id") == YouTubeOAuthService::EXPECTED_CHANNEL_ID
    end

    def receipt_value(context, scope, access, video_id, actual_privacy, thumbnail_applied:, state:)
      {
        "schema_version" => "soul.youtube.upload_receipt.v1",
        "state" => state,
        "project_id" => context.fetch("project_id"),
        "candidate_id" => context.fetch("candidate_id"),
        "visual_id" => context.fetch("visual_id"),
        "scope_digest" => digest(scope),
        "package_receipt_sha256" => context.fetch("package_receipt_sha256"),
        "video_id" => video_id,
        "channel_id" => access.fetch("channel_id"),
        "requested_privacy" => context.fetch("visibility"),
        "actual_privacy" => actual_privacy,
        "thumbnail_applied" => thumbnail_applied,
        "uploaded_at" => @clock.call.iso8601,
        "human_publication_required" => true
      }
    end

    def existing_receipt(context)
      path = context.fetch("receipt_path")
      return nil unless File.exist?(path)
      receipt = read_json(path, "YouTube upload receipt")
      raise ValidationError, "YouTube upload receipt package digest changed" unless receipt["package_receipt_sha256"] == context.fetch("package_receipt_sha256")
      receipt
    end

    def public_receipt(receipt)
      receipt.slice(
        "state", "project_id", "candidate_id", "visual_id", "video_id", "channel_id",
        "requested_privacy", "actual_privacy", "thumbnail_applied", "uploaded_at",
        "human_publication_required"
      ).merge(
        "watch_url" => "https://www.youtube.com/watch?v=#{receipt.fetch('video_id')}",
        "studio_url" => "https://studio.youtube.com/video/#{receipt.fetch('video_id')}/edit"
      )
    end

    def read_json(path, label)
      raise ValidationError, "#{label} must be a regular non-symlink file" unless File.file?(path) && !File.symlink?(path)
      raise ValidationError, "#{label} exceeds size limit" unless File.size(path).between?(1, MAX_RECORD_BYTES)
      JSON.parse(File.binread(path, MAX_RECORD_BYTES))
    rescue JSON::ParserError
      raise ValidationError, "#{label} is invalid"
    end

    def write_receipt(path, value)
      raise ValidationError, "YouTube upload receipt already exists" if File.exist?(path) || File.symlink?(path)
      FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      File.write(path, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
    end

    def within?(path, parent) = path == parent || path.start_with?(parent + File::SEPARATOR)
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    def safe_message(error) = error.message.to_s.gsub(/ya29\.[A-Za-z0-9._-]+|1\/\/[A-Za-z0-9._-]+/, "[REDACTED]").slice(0, 500)
    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
