#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "roster-librechat-trial"
require_relative "run-desktop-coexistence-trial"

# Separate foreground cancellation trial; never changes the installed presets.
class RosterDesktopLibreChatTrial < RosterLibreChatTrial
  BUDGET_SECONDS = 900
  class GuardStopped < StandardError; end
  def self.allowed_model = "gpt-oss-20b"
  def create_output = Dir.mktmpdir("roster-desktop-librechat-",QUALIFICATION)
  def self.validate_amd!(sample,previous:,owned_pid:)
    DesktopCoexistenceTrial.validate_amd!(sample,previous:previous,owned_pid:owned_pid)
  end
  def validate_resources!(sample,admission:false)
    super
    raise Abort,"NVIDIA runtime reserve below 1024 MiB" if sample.fetch("free_mib") < 1024
  end
  def roster_binding
    super.transform_values do |binding|
      binding.merge("launch_sha256"=>Digest::SHA256.hexdigest(JSON.generate({
        "base"=>binding["launch_sha256"],"desktop_driver"=>Digest::SHA256.file(__FILE__).hexdigest,
        "desktop_policy"=>Digest::SHA256.file(File.join(__dir__,"run-desktop-coexistence-trial.rb")).hexdigest,
        "baseline"=>DesktopCoexistenceTrial::BASELINE_SHA})))
    end
  end
  def roster_start(**args)
    unless args.fetch(:adapter).model==self.class.allowed_model
      # The owner still verifies release after a refused startup.
      @ownership=args.fetch(:ownership_id)
      raise GuardStopped,"#{self.class.allowed_model}-only cancellation trial"
    end
    super
  rescue ChatReplacementTrial::Abort => error
    # Private fixed-path diagnostics, not an HTTP disclosure or retry grant.
    save("startup-guard-refusal.json",{"error_class"=>error.class.name,"reason"=>error.message.slice(0,1024)})
    raise GuardStopped,"startup guard refused; inspect private receipt"
  end
end

class GemmaDesktopLibreChatTrial < RosterDesktopLibreChatTrial
  def self.allowed_model = "gemma-4-26b-a4b"
  def create_output = Dir.mktmpdir("gemma-desktop-librechat-",QUALIFICATION)
  def self.argv(candidate,model)
    args=super
    args[args.index("--tensor-split")+1]="1,1" if candidate==allowed_model
    args
  end
end

if $PROGRAM_NAME==__FILE__
  klass={"--approved-desktop-librechat"=>RosterDesktopLibreChatTrial,
    "--approved-gemma-desktop-librechat"=>GemmaDesktopLibreChatTrial}[ARGV.first]
  abort "Expected explicit desktop LibreChat trial flag --key-file OWNER_PRIVATE_KEY" unless klass && ARGV.length==3 && ARGV[1]=="--key-file"
  exit(klass.new.serve(key_file:ARGV.last) ? 0 : 1)
end
