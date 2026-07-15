# frozen_string_literal: true
require_relative "bounded_command_runner"

module SoulCore
  class RuntimeAssessor
    RUNTIMES = {"ruby"=>["ruby","--version"],"python"=>["python","--version"],"python3"=>["python3","--version"],"node"=>["node","--version"],"npm"=>["npm","--version"],"git"=>["git","--version"],"docker"=>["docker","--version"],"rust"=>["rustc","--version"],"cargo"=>["cargo","--version"],"go"=>["go","version"],"java"=>["java","-version"],"jq"=>["jq","--version"],"curl"=>["curl","--version"],"rg"=>["rg","--version"]}.freeze
    def initialize(runner: BoundedCommandRunner.new)
      @runner = runner
    end
    def assess
      {"status"=>"ok","read_only"=>true,"runtimes"=>RUNTIMES.transform_values { |c| one(c) }}
    end
    private
    def one(cmd)
      path = which(cmd.first)
      return {"detected"=>false,"path"=>nil,"version"=>nil} unless path
      result = @runner.run(*cmd, timeout_seconds: 3, max_output_bytes: 8 * 1024)
      {"detected"=>true,"path"=>path,"version"=>(result.stdout + result.stderr).lines.first.to_s.strip,"check_status"=>result.status}
    rescue StandardError
      {"detected"=>false,"path"=>nil,"version"=>nil}
    end
    def which(name)
      @runner.which(name)
    rescue StandardError
      nil
    end
  end
end
