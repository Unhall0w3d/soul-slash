# frozen_string_literal: true
require "open3"

module SoulCore
  class SoulProjectAssessor
    def initialize(root: Dir.pwd); @root = File.expand_path(root); end
    def assess
      {"status"=>"ok","read_only"=>true,"root"=>@root,"git"=>git,"directories"=>dirs,"verifiers"=>verifiers,"overlay_debris"=>debris}
    end
    private
    def git
      return {"detected"=>false,"inside_work_tree"=>false} unless ok?("git","rev-parse","--is-inside-work-tree")
      st = cap("git","status","--short").to_s
      {"detected"=>true,"inside_work_tree"=>true,"branch"=>cap("git","branch","--show-current"),"head"=>cap("git","rev-parse","--short","HEAD"),"dirty"=>!st.strip.empty?,"status_short"=>st.lines.map(&:strip).reject(&:empty?)}
    end
    def dirs
      %w[Soul Soul/logs Soul/workflows Soul/workflows/sessions Soul/proposals lib/soul_core lib/soul_core/workflows scripts docs docs/workflows].to_h { |d| [d, Dir.exist?(File.join(@root,d))] }
    end
    def verifiers
      s = Dir.glob(File.join(@root,"scripts","verify-*.rb")).map { |p| p.sub(@root+"/","") }.sort
      {"count"=>s.length,"items"=>s}
    end
    def debris
      pats = ["README_*PHASE*.md","README_*REPAIR*.md","overlay_files","scripts/patch-*.rb","scripts/repair-*.rb"]
      items = pats.flat_map { |pat| Dir.glob(File.join(@root,pat)).map { |p| p.sub(@root+"/","") } }.sort
      {"count"=>items.length,"items"=>items}
    end
    def ok?(*cmd); Open3.capture3(*cmd, chdir: @root)[2].success? rescue false; end
    def cap(*cmd)
      out, _err, st = Open3.capture3(*cmd, chdir: @root)
      st.success? ? out.strip : nil
    rescue StandardError
      nil
    end
  end
end
