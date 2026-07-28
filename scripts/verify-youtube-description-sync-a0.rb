#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "socket"
require "tmpdir"
require "time"
require "uri"
require_relative "../lib/soul_core/youtube_description_sync_service"

Result = Struct.new(:ok) do
  def success? = ok
end

class DescriptionOAuthApiFixture
  def exchange_code(**_arguments)
    {
      "access_token" => "ya29.description-access-never-output",
      "refresh_token" => "1//description-refresh-never-output",
      "scope" => SoulCore::YouTubeDescriptionSyncService::OAUTH_SCOPES.join(" ")
    }
  end

  def channel(access_token:)
    raise "missing access token" if access_token.to_s.empty?
    { "id" => SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID, "title" => "Soul Slash Synthesis" }
  end
end

class DescriptionOAuthCallbackRunner
  def run(*command, **_options)
    uri = URI.parse(command.last)
    query = URI.decode_www_form(uri.query).to_h
    callback = URI.parse(query.fetch("redirect_uri"))
    Thread.new do
      socket = TCPSocket.new(callback.host, callback.port)
      target = "#{callback.path}?#{URI.encode_www_form("state" => query.fetch("state"), "code" => "description-fixture-code")}"
      socket.write("GET #{target} HTTP/1.1\r\nHost: #{callback.host}\r\nConnection: close\r\n\r\n")
      socket.read
      socket.close
    end
    Result.new(true)
  end
end

class DescriptionOAuthFixture
  def initialize(channel_id: SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID)
    @channel_id = channel_id
  end

  def access_context
    {
      "access_token" => "ya29.sync-fixture-never-output",
      "channel_id" => @channel_id,
      "channel_title" => "Soul Slash Synthesis",
      "project_id" => SoulCore::YouTubeOAuthService::PROJECT_ID
    }
  end
end

class DescriptionApiFixture
  attr_reader :updates, :video_reads
  attr_accessor :fail_on, :interrupt_on

  def initialize(records)
    @records = records.to_h { |record| [record.fetch("id"), deep_copy(record)] }
    @updates = []
    @video_reads = 0
  end

  def videos(access_token:, video_ids:)
    raise "missing access token" if access_token.to_s.empty?
    @video_reads += 1
    video_ids.filter_map { |video_id| deep_copy(@records[video_id]) }
  end

  def update_video_snippet(access_token:, video_id:, snippet:)
    raise "missing access token" if access_token.to_s.empty?
    raise Interrupt if interrupt_on == video_id
    raise SoulCore::YouTubeApiClient::ApiError, "fixture update failure" if fail_on == video_id

    before = @records.fetch(video_id)
    @updates << {
      "video_id" => video_id,
      "before" => deep_copy(before.fetch("snippet")),
      "submitted" => deep_copy(snippet)
    }
    @records[video_id]["snippet"] = deep_copy(snippet).merge("channelId" => before.dig("snippet", "channelId"))
    deep_copy(@records.fetch(video_id))
  end

  def mutate(video_id, key, value)
    @records.fetch(video_id).fetch("snippet")[key] = value
  end

  def description(video_id)
    @records.fetch(video_id).dig("snippet", "description")
  end

  private

  def deep_copy(value) = JSON.parse(JSON.generate(value))
end

def video(video_id, title:, description:, tags: nil, language: nil, channel_id: SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID)
  snippet = {
    "channelId" => channel_id,
    "title" => title,
    "categoryId" => "10",
    "description" => description
  }
  snippet["tags"] = tags if tags
  snippet["defaultLanguage"] = language if language
  { "id" => video_id, "snippet" => snippet }
end

def write_mapping(root, entries, name: "mapping.json")
  path = File.join(root, name)
  File.write(path, JSON.pretty_generate(
    "schema_version" => "soul.youtube.description_links.v1",
    "channel_id" => SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID,
    "videos" => entries
  ) + "\n")
  path
end

def mapping_entry(video_id, article, expected: "https://nocthoughts.com/")
  {
    "video_id" => video_id,
    "expected_current_url" => expected,
    "article_url" => article
  }
end

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

Dir.mktmpdir("soul-youtube-description-oauth-") do |root|
  client_path = File.join(root, "desktop-client.json")
  client_secret = "description-client-secret-never-output"
  File.write(client_path, JSON.generate(
    "installed" => {
      "client_id" => "fixture.apps.googleusercontent.com",
      "project_id" => SoulCore::YouTubeOAuthService::PROJECT_ID,
      "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
      "token_uri" => "https://oauth2.googleapis.com/token",
      "client_secret" => client_secret,
      "redirect_uris" => ["http://localhost"]
    }
  ), mode: "wx", perm: 0o600)

  upload_oauth = SoulCore::YouTubeOAuthService.new(root: root, api: DescriptionOAuthApiFixture.new)
  description_oauth = SoulCore::YouTubeDescriptionSyncService.oauth(
    root: root,
    api: DescriptionOAuthApiFixture.new,
    runner: DescriptionOAuthCallbackRunner.new,
    callback_timeout: 1,
    clock: -> { Time.utc(2026, 7, 27, 22) }
  )
  upload_preview = upload_oauth.preview(client_path: client_path)
  description_preview = description_oauth.preview(client_path: client_path)
  check.call("upload and description OAuth previews remain separate",
             upload_preview.dig("data", "preview_scope", "scopes") == SoulCore::YouTubeOAuthService::SCOPES &&
             description_preview.dig("data", "preview_scope", "scopes") == SoulCore::YouTubeDescriptionSyncService::OAUTH_SCOPES &&
             upload_preview.dig("data", "preview_scope", "credential_destination") != description_preview.dig("data", "preview_scope", "credential_destination"))
  unapproved_scope_rejected = begin
    SoulCore::YouTubeOAuthService.new(root: root, api: DescriptionOAuthApiFixture.new, scopes: ["https://www.googleapis.com/auth/drive"])
    false
  rescue ArgumentError
    true
  end
  check.call("OAuth profile rejects scopes outside the reviewed YouTube allow-list", unapproved_scope_rejected)

  authorized = description_oauth.execute(
    client_path: client_path,
    confirmation: SoulCore::YouTubeDescriptionSyncService::OAUTH_CONFIRMATION,
    expected_digest: description_preview.dig("data", "expected_digest")
  )
  credential_path = File.join(root, "Soul", "runtime", "youtube_auth", SoulCore::YouTubeDescriptionSyncService::OAUTH_CREDENTIAL_NAME)
  serialized = JSON.generate(authorized)
  check.call("description OAuth stores only its owner-private credential for the exact channel",
             authorized["lifecycle_state"] == "complete" &&
             File.file?(credential_path) &&
             (File.stat(credential_path).mode & 0o077).zero? &&
             !File.exist?(File.join(root, "Soul", "runtime", "youtube_auth", "oauth.json")))
  check.call("description OAuth output exposes no client or token secrets",
             !serialized.include?(client_secret) &&
             !serialized.include?("description-access") &&
             !serialized.include?("description-refresh"))
end

article = "https://nocthoughts.com/2026/07/24/how-soul-slash-turns-an-idea-into-a-song.html"
core_article = "https://nocthoughts.com/2026/07/19/soul-slash-has-more-than-one-brain-now.html"
first_id = "ZFA6t2PAqyI"
second_id = "863-KXJRfyA"
unicode_description = "Opening — machinery wakes.\r\n\r\nSoul/\r\nhttps://github.com/Unhall0w3d/soul-slash\r\n\r\nNOC Thoughts\r\nhttps://nocthoughts.com/\r\n\r\nMusic by Soul/."
second_description = "Nocturnal | Liquid Drum & Bass\n\nNOC Thoughts\nhttps://nocthoughts.com/\n\nMusic, Visual, and Composition created by Soul/."

Dir.mktmpdir("soul-youtube-description-sync-") do |root|
  mapping = write_mapping(root, [
    mapping_entry(first_id, article),
    mapping_entry(second_id, core_article)
  ])
  records = [
    video(first_id, title: "The Hallway Moves First", description: unicode_description, tags: %w[soul breakcore], language: "en"),
    video(second_id, title: "Afterimage Current", description: second_description)
  ]
  api = DescriptionApiFixture.new(records)
  service = SoulCore::YouTubeDescriptionSyncService.new(
    root: root, oauth: DescriptionOAuthFixture.new, api: api,
    clock: -> { Time.utc(2026, 7, 27, 22, 1) }
  )

  preview = service.preview(mapping_path: mapping)
  check.call("preview binds two exact URL-only changes",
             preview["lifecycle_state"] == "blocked_for_human_review" &&
             preview.dig("data", "changes").length == 2 &&
             preview.dig("data", "changes").all? { |entry| entry["change_required"] } &&
             preview.dig("data", "preview_scope", "visibility_mutation") == false)

  wrong = service.execute(
    mapping_path: mapping, confirmation: "WRONG",
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("wrong confirmation performs no video update",
             wrong["lifecycle_state"] == "blocked_for_human_review" && api.updates.empty?)

  complete = service.execute(
    mapping_path: mapping,
    confirmation: SoulCore::YouTubeDescriptionSyncService::CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("exact execution updates each mapped video once",
             complete["lifecycle_state"] == "complete" &&
             api.updates.map { |update| update.fetch("video_id") } == [first_id, second_id])
  first_update = api.updates.first
  expected_first = unicode_description.sub("https://nocthoughts.com/", article)
  check.call("only managed URL bytes change while metadata and CRLF survive",
             api.description(first_id) == expected_first &&
             first_update.fetch("submitted").slice("title", "categoryId", "tags", "defaultLanguage") ==
               first_update.fetch("before").slice("title", "categoryId", "tags", "defaultLanguage") &&
             !first_update.fetch("submitted").key?("status"))

  receipt = complete.dig("data", "receipt")
  snapshot_path = receipt.fetch("snapshot_path")
  receipt_path = File.join(root, "Soul", "runtime", "youtube_description_sync", "receipts", "#{receipt.fetch('scope_digest')}.json")
  private_material = File.binread(snapshot_path) + File.binread(receipt_path) + JSON.generate(complete)
  check.call("owner-private snapshot and receipt retain rollback evidence without tokens",
             File.file?(snapshot_path) &&
             (File.stat(snapshot_path).mode & 0o077).zero? &&
             (File.stat(receipt_path).mode & 0o077).zero? &&
             JSON.parse(File.binread(snapshot_path)).dig("videos", 0, "before_snippet", "description") == unicode_description &&
             !private_material.include?("ya29.") &&
             !private_material.include?("1//"))

  replay = service.preview(mapping_path: mapping)
  check.call("already-current mapping is idempotent",
             replay["lifecycle_state"] == "complete" &&
             replay.dig("data", "idempotent_replay") == true &&
             api.updates.length == 2)
end

Dir.mktmpdir("soul-youtube-description-stale-") do |root|
  mapping = write_mapping(root, [mapping_entry(first_id, article)])
  api = DescriptionApiFixture.new([
    video(first_id, title: "Original Title", description: "NOC Thoughts\nhttps://nocthoughts.com/\n")
  ])
  service = SoulCore::YouTubeDescriptionSyncService.new(root: root, oauth: DescriptionOAuthFixture.new, api: api)
  preview = service.preview(mapping_path: mapping)
  api.mutate(first_id, "title", "Changed Elsewhere")
  stale = service.execute(
    mapping_path: mapping,
    confirmation: SoulCore::YouTubeDescriptionSyncService::CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("stale title invalidates the preview before mutation",
             stale["lifecycle_state"] == "blocked_for_human_review" && api.updates.empty?)
end

Dir.mktmpdir("soul-youtube-description-validation-") do |root|
  api = DescriptionApiFixture.new([
    video(first_id, title: "Fixture", description: "NOC Thoughts\nhttps://nocthoughts.com/\n")
  ])
  service = SoulCore::YouTubeDescriptionSyncService.new(root: root, oauth: DescriptionOAuthFixture.new, api: api)
  duplicate = write_mapping(root, [mapping_entry(first_id, article), mapping_entry(first_id, core_article)], name: "duplicate.json")
  invalid_domain = write_mapping(root, [mapping_entry(first_id, "https://example.com/article")], name: "domain.json")
  duplicate_result = service.preview(mapping_path: duplicate)
  domain_result = service.preview(mapping_path: invalid_domain)
  check.call("duplicate IDs and foreign article domains stop before API reads",
             !duplicate_result["ok"] && !domain_result["ok"] && api.video_reads.zero?)

  missing_api = DescriptionApiFixture.new([
    video(first_id, title: "Fixture", description: "Soul/\nhttps://github.com/Unhall0w3d/soul-slash\n")
  ])
  missing_service = SoulCore::YouTubeDescriptionSyncService.new(root: root, oauth: DescriptionOAuthFixture.new, api: missing_api)
  valid_mapping = write_mapping(root, [mapping_entry(first_id, article)], name: "missing.json")
  missing = missing_service.preview(mapping_path: valid_mapping)

  multiple_api = DescriptionApiFixture.new([
    video(first_id, title: "Fixture", description: "NOC Thoughts\nhttps://nocthoughts.com/\n\nNOC Thoughts\nhttps://nocthoughts.com/\n")
  ])
  multiple_service = SoulCore::YouTubeDescriptionSyncService.new(root: root, oauth: DescriptionOAuthFixture.new, api: multiple_api)
  multiple = multiple_service.preview(mapping_path: valid_mapping)
  check.call("missing or multiple managed blocks cause no update",
             !missing["ok"] && !multiple["ok"] &&
             missing_api.updates.empty? && multiple_api.updates.empty?)

  unexpected_api = DescriptionApiFixture.new([
    video(first_id, title: "Fixture", description: "NOC Thoughts\nhttps://nocthoughts.com/an-unreviewed-page.html\n")
  ])
  unexpected_service = SoulCore::YouTubeDescriptionSyncService.new(root: root, oauth: DescriptionOAuthFixture.new, api: unexpected_api)
  unexpected = unexpected_service.preview(mapping_path: valid_mapping)
  wrong_channel_api = DescriptionApiFixture.new([
    video(first_id, title: "Fixture", description: "NOC Thoughts\nhttps://nocthoughts.com/\n")
  ])
  wrong_channel_service = SoulCore::YouTubeDescriptionSyncService.new(
    root: root, oauth: DescriptionOAuthFixture.new(channel_id: "UCwrongchannel0000000000"), api: wrong_channel_api
  )
  wrong_channel = wrong_channel_service.preview(mapping_path: valid_mapping)
  check.call("unexpected current URL and wrong OAuth channel cause no update",
             !unexpected["ok"] && !wrong_channel["ok"] &&
             unexpected_api.updates.empty? && wrong_channel_api.updates.empty?)
end

Dir.mktmpdir("soul-youtube-description-lock-") do |root|
  mapping = write_mapping(root, [mapping_entry(first_id, article)])
  api = DescriptionApiFixture.new([
    video(first_id, title: "Fixture", description: "NOC Thoughts\nhttps://nocthoughts.com/\n")
  ])
  service = SoulCore::YouTubeDescriptionSyncService.new(root: root, oauth: DescriptionOAuthFixture.new, api: api)
  preview = service.preview(mapping_path: mapping)
  lock_directory = File.join(root, "Soul", "runtime", "youtube_description_sync")
  FileUtils.mkdir_p(lock_directory)
  lock = File.open(File.join(lock_directory, "execution.lock"), File::RDWR | File::CREAT, 0o600)
  lock.flock(File::LOCK_EX | File::LOCK_NB)
  concurrent = service.execute(
    mapping_path: mapping,
    confirmation: SoulCore::YouTubeDescriptionSyncService::CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("concurrent execution is rejected before remote mutation",
             !concurrent["ok"] && concurrent["reason"].include?("another YouTube description sync") && api.updates.empty?)
ensure
  lock&.flock(File::LOCK_UN)
  lock&.close
end

Dir.mktmpdir("soul-youtube-description-partial-") do |root|
  third_id = "q35PDSyTwA0"
  mapping = write_mapping(root, [
    mapping_entry(first_id, article),
    mapping_entry(second_id, core_article),
    mapping_entry(third_id, article)
  ])
  records = [
    video(first_id, title: "First", description: "NOC Thoughts\nhttps://nocthoughts.com/\n"),
    video(second_id, title: "Second", description: "NOC Thoughts\nhttps://nocthoughts.com/\n"),
    video(third_id, title: "Third", description: "NOC Thoughts\nhttps://nocthoughts.com/\n")
  ]
  api = DescriptionApiFixture.new(records)
  api.fail_on = second_id
  service = SoulCore::YouTubeDescriptionSyncService.new(root: root, oauth: DescriptionOAuthFixture.new, api: api)
  preview = service.preview(mapping_path: mapping)
  partial = service.execute(
    mapping_path: mapping,
    confirmation: SoulCore::YouTubeDescriptionSyncService::CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("partial API failure stops future updates and records remaining videos",
             partial["lifecycle_state"] == "blocked_for_human_review" &&
             api.updates.map { |update| update.fetch("video_id") } == [first_id] &&
             partial.dig("data", "receipt", "state") == "partial" &&
             partial.dig("data", "receipt", "remaining_video_ids") == [second_id, third_id])
end

Dir.mktmpdir("soul-youtube-description-cancel-") do |root|
  mapping = write_mapping(root, [
    mapping_entry(first_id, article),
    mapping_entry(second_id, core_article)
  ])
  api = DescriptionApiFixture.new([
    video(first_id, title: "First", description: "NOC Thoughts\nhttps://nocthoughts.com/\n"),
    video(second_id, title: "Second", description: "NOC Thoughts\nhttps://nocthoughts.com/\n")
  ])
  api.interrupt_on = second_id
  service = SoulCore::YouTubeDescriptionSyncService.new(root: root, oauth: DescriptionOAuthFixture.new, api: api)
  preview = service.preview(mapping_path: mapping)
  canceled = service.execute(
    mapping_path: mapping,
    confirmation: SoulCore::YouTubeDescriptionSyncService::CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("cancellation stops future updates and records completed work",
             canceled["lifecycle_state"] == "canceled" &&
             api.updates.map { |update| update.fetch("video_id") } == [first_id] &&
             canceled.dig("data", "receipt", "completed_video_ids") == [first_id] &&
             canceled.dig("data", "receipt", "remaining_video_ids") == [second_id])
end

source = File.binread(File.expand_path("../lib/soul_core/youtube_description_sync_service.rb", __dir__))
brief = File.binread(File.expand_path("../docs/soul/YOUTUBE_DESCRIPTION_SYNC_A0_BRIEF.md", __dir__))
check.call("source and brief prohibit upload status mutation and background sync",
           source.include?("\"visibility_mutation\" => false") &&
           !source.include?("initiate_upload") &&
           brief.include?("No daemon, watcher, schedule") &&
           brief.include?("never includes `status`"))

abort "YouTube description sync A0 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "YouTube description sync A0 deterministic verification passed."
