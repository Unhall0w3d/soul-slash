# frozen_string_literal: true
require "open3"

module SoulCore
  class RuntimeAssessor
    RUNTIMES = {"ruby"=>["ruby","--version"],"python"=>["python","--version"],"python3"=>["python3","--version"],"node"=>["node","--version"],"npm"=>["npm","--version"],"git"=>["git","--version"],"docker"=>["docker","--version"],"rust"=>["rustc","--version"],"cargo"=>["cargo","--version"],"go"=>["go","version"],"java"=>["java","-version"],"jq"=>["jq","--version"],"curl"=>["curl","--version"],"rg"=>["rg","--version"]}.freeze
    def assess
      {"status"=>"ok","read_only"=>true,"runtimes"=>RUNTIMES.transform_values { |c| one(c) }}
    end
    private
    def one(cmd)
      path = which(cmd.first)
      return {"detected"=>false,"path"=>nil,"version"=>nil} unless path
      out, err, = Open3.capture3(*cmd)
      {"detected"=>true,"path"=>path,"version"=>(out + err).lines.first.to_s.strip}
    rescue StandardError
      {"detected"=>false,"path"=>nil,"version"=>nil}
    end
    def which(name)
      out, st = Open3.capture2("sh","-lc","command -v #{name}")
      st.success? ? out.strip : nil
    rescue StandardError
      nil
    end
  end
end
