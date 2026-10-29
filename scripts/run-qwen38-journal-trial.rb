#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-roster-journal-trial"
require_relative "run-qwen38-native-probe"

class Qwen38JournalTrial < RosterJournalTrial
  def create_output = Dir.mktmpdir("qwen38-journal-trial-",QUALIFICATION)
  def isolated_models = ["qwen3.8-27b"]
  def roster_ids = SoulCore::RosterChatAdapter::MODELS + isolated_models
  def roster_assets = super.merge(Qwen38NativeProbe.allocate.candidate_assets)
  def self.argv(id,path)
    return Qwen38NativeProbe.argv(id,path) if id=="qwen3.8-27b"
    args=super
    args[args.index("--tensor-split")+1]="1,1" if id=="gemma-4-26b-a4b"
    args
  end
  def self.validate_amd!(sample,previous:,owned_pid:)
    DesktopCoexistenceTrial.validate_amd!(sample,previous:previous,owned_pid:owned_pid)
  end
  def validate_resources!(sample,admission:false)
    super
    raise Abort,"NVIDIA runtime reserve below 1024 MiB" if sample.fetch("free_mib")<1024
  end
  def roster_binding
    super.transform_values { |b| b.merge("launch_sha256"=>Digest::SHA256.hexdigest(JSON.generate(
      base:b["launch_sha256"],candidate_driver:Digest::SHA256.file(__FILE__).hexdigest,
      desktop_policy:Digest::SHA256.file(File.join(__dir__,"run-desktop-coexistence-trial.rb")).hexdigest,
      baseline:DesktopCoexistenceTrial::BASELINE_SHA))) }
  end
end
if $PROGRAM_NAME==__FILE__
  abort "Expected isolated journal trial flag" unless ARGV==["--approved-qwen38-journal-trial"]
  exit(Qwen38JournalTrial.new.run ? 0 : 1)
end
