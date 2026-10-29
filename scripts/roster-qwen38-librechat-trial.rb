#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "roster-warm-librechat-trial"
require_relative "run-qwen38-journal-trial"

# Explicit candidate-only entry point; normal two-model entry points stay intact.
class RosterQwen38LibreChatTrial < RosterWarmLibreChatTrial
  def create_output = Dir.mktmpdir("roster-qwen38-librechat-",QUALIFICATION)
  def isolated_models = ["qwen3.8-27b"]
  def roster_ids = SoulCore::RosterChatAdapter::MODELS + isolated_models
  def roster_assets = super.merge(Qwen38NativeProbe.allocate.candidate_assets)
  def self.argv(id,path) = Qwen38JournalTrial.argv(id,path)
  def roster_binding
    super.transform_values { |b| b.merge("launch_sha256"=>Digest::SHA256.hexdigest(JSON.generate(
      base:b["launch_sha256"],candidate_driver:Digest::SHA256.file(__FILE__).hexdigest,
      journal_driver:Digest::SHA256.file(File.join(__dir__,"run-qwen38-journal-trial.rb")).hexdigest))) }
  end
end
if $PROGRAM_NAME==__FILE__
  abort "Expected candidate LibreChat flag and key path" unless ARGV.length==3 && ARGV.first(2)==%w[--approved-qwen38-librechat --key-file]
  exit(RosterQwen38LibreChatTrial.new.serve(key_file:ARGV.last) ? 0 : 1)
end
