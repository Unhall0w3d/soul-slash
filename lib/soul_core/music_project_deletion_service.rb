# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "music_project_store"
require_relative "music_resource_coordinator"

module SoulCore
  class MusicProjectDeletionService
    CONFIRMATION = "DELETE_MUSIC_PROJECT"
    MAX_FILES = 5_000
    MAX_BYTES = 10 * 1024 * 1024 * 1024

    def initialize(root: Dir.pwd, project_store: nil, coordinator: nil)
      @store = project_store || MusicProjectStore.new(root: root)
      @coordinator = coordinator || MusicResourceCoordinator.new(root: root)
    end

    def preview(project_id:)
      project = @store.read(project_id)
      return blocked("music project has active foreground work; finish or cancel it before deletion") if @coordinator.active_project?(project_id)
      scope = deletion_scope(project)
      outcome("blocked_for_human_review", true, "exact music project deletion confirmation required", data: {
        "confirmation_phrase" => CONFIRMATION, "expected_digest" => digest(scope), "preview_scope" => scope
      })
    rescue MusicProjectStore::ValidationError => error
      awaiting(error.message)
    rescue MusicProjectStore::IntegrityError, MusicResourceCoordinator::IntegrityError, SystemCallError => error
      blocked(error.message)
    end

    def execute(project_id:, confirmation:, expected_digest:)
      return awaiting("confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      project = @store.read(project_id)
      return blocked("music project has active foreground work; finish or cancel it before deletion") if @coordinator.active_project?(project_id)
      scope = deletion_scope(project)
      return blocked("exact music project deletion confirmation did not match") unless confirmation == CONFIRMATION
      return blocked("music project state changed; preview deletion again") unless secure_compare(expected_digest, digest(scope))
      path = @store.project_path(project_id)
      FileUtils.remove_entry_secure(path)
      return blocked("music project deletion could not be verified") if File.exist?(path) || File.symlink?(path)
      outcome("complete", true, "music project permanently deleted from the Composition Archive", data: {
        "project_id" => project_id, "title" => project.fetch("title"),
        "deleted_file_count" => scope.fetch("file_count"), "deleted_bytes" => scope.fetch("total_bytes"),
        "retained_finished_exports" => scope.fetch("retained_finished_exports")
      }, mutation: "music_project_deleted")
    rescue MusicProjectStore::ValidationError => error
      awaiting(error.message)
    rescue MusicProjectStore::IntegrityError, MusicResourceCoordinator::Busy, MusicResourceCoordinator::IntegrityError, SystemCallError => error
      blocked(error.message)
    end

    private

    def deletion_scope(project)
      root = @store.project_path(project.fetch("project_id"))
      entries = inventory(root)
      exports = entries.filter_map do |entry|
        next unless entry.fetch("path").match?(%r{\Aexports/[^/]+\.json\z})
        value = JSON.parse(File.binread(File.join(root, entry.fetch("path")), MusicProjectStore::MAX_PROJECT_BYTES))
        destination = value["destination"].to_s
        destination unless destination.empty?
      rescue JSON::ParserError
        raise MusicProjectStore::IntegrityError, "music export receipt is invalid"
      end.uniq.sort
      {
        "operation" => "delete_music_project", "project_id" => project.fetch("project_id"),
        "title" => project.fetch("title"), "project_digest" => Digest::SHA256.hexdigest(JSON.generate(project)),
        "file_count" => entries.length, "total_bytes" => entries.sum { |entry| entry.fetch("bytes") },
        "tree_digest" => Digest::SHA256.hexdigest(JSON.generate(entries)),
        "deletes" => %w[project_record generated_candidates archive_audio generation_inputs logs transcription_evidence reviews review_history rejection_receipts export_receipts],
        "retained_finished_exports" => exports, "external_finished_exports_deleted" => false
      }
    end

    def inventory(root)
      files = []; total = 0
      walk = lambda do |directory, relative|
        Dir.children(directory).sort.each do |name|
          path = File.join(directory, name); child_relative = relative.empty? ? name : File.join(relative, name); stat = File.lstat(path)
          raise MusicProjectStore::IntegrityError, "music project tree contains a symlink" if stat.symlink?
          if stat.directory?
            walk.call(path, child_relative)
          elsif stat.file?
            raise MusicProjectStore::IntegrityError, "music project file inventory exceeds #{MAX_FILES}" if files.length >= MAX_FILES
            total += stat.size
            raise MusicProjectStore::IntegrityError, "music project byte inventory exceeds #{MAX_BYTES}" if total > MAX_BYTES
            files << { "path" => child_relative, "bytes" => stat.size, "sha256" => Digest::SHA256.file(path).hexdigest }
          else
            raise MusicProjectStore::IntegrityError, "music project tree contains an unsupported filesystem object"
          end
        end
      end
      walk.call(root, ""); files
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def secure_compare(left, right) = left.to_s.bytesize == right.bytesize && left.to_s.bytes.zip(right.bytes).all? { |a, b| a == b }
    def awaiting(reason) = outcome("awaiting_input", false, reason)
    def blocked(reason) = outcome("blocked_for_human_review", false, reason)
    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
