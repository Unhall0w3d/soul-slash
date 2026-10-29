# frozen_string_literal: true
require "json"
require "digest"
require "tempfile"

module SoulCore
  # Callers hold ModelRuntimeLeaseStore's control lock. This policy never grants
  # execution authority: exact workload approvals and GPU admission still apply.
  class SharedComputePolicy
    class Refused < StandardError; end
    def initialize(directory:)
      @directory=directory
      @path=File.join(directory,"shared_compute.json")
    end

    def read
      return {"version"=>1,"revision"=>0,"policy"=>"available","handoff"=>nil} unless File.exist?(@path) || File.symlink?(@path)
      st=File.lstat(@path)
      raise Refused,"unsafe compute policy" unless st.file? && !st.symlink? && st.nlink==1 && st.size<=8192 && st.uid==Process.uid && (st.mode & 0o077).zero?
      value=File.open(@path,File::RDONLY|File::NOFOLLOW) { |f| JSON.parse(f.read(8193)) }
      validate!(value)
      value
    rescue JSON::ParserError, SystemCallError => error
      raise Refused,"compute policy unreadable: #{error.class}"
    end

    def digest(value=read) = Digest::SHA256.hexdigest(JSON.generate(value))

    def write(value)
      validate!(value)
      Tempfile.create([".compute-",".json"],@directory,mode:0o600) do |f|
        f.chmod(0o600); f.write(JSON.generate(value)); f.flush; f.fsync
        File.rename(f.path,@path)
        File.open(@directory,File::RDONLY) { |d| d.fsync }
      end
      value
    end

    def admit!(provider_id:,request_id:,conversation_id:)
      state=read
      raise Refused,"GPUs reserved for the user" unless state["policy"]=="available"
      h=state["handoff"]
      if h && (h["state"]!="released" || h.values_at("provider_id","request_id","conversation_id") != [provider_id,request_id,conversation_id])
        raise Refused,"compute held for an exact workload handoff"
      end
      # Consume admission before writing the lease: an interrupted write retains
      # a hold instead of granting a second execution for the same candidate.
      write(state.merge("handoff"=>h.merge("state"=>"running"),"revision"=>state["revision"]+1)) if h
      true
    end

    def record_handoff(record)
      id=record.fetch("handoff_id")
      raise Refused,"handoff identity invalid" unless id.match?(/\A[a-f0-9]{32}\z/)
      path=File.join(@directory,"handoff-#{id}.json")
      File.open(path,File::WRONLY|File::CREAT|File::EXCL|File::NOFOLLOW,0o600) do |f|
        f.write(JSON.generate(record)); f.flush; f.fsync
      end
      File.open(@directory,File::RDONLY) { |d| d.fsync }
    end

    private
    def validate!(v)
      raise Refused,"invalid compute policy" unless v.is_a?(Hash) && v.keys.sort==%w[handoff policy revision version] && v["version"]==1 && v["revision"].is_a?(Integer) && v["revision"]>=0 && %w[available reserved].include?(v["policy"])
      h=v["handoff"]
      return if h.nil?
      keys=%w[conversation_id handoff_id input_digest member origin_conversation_id provider_id request_id state]
      raise Refused,"invalid workload handoff" unless h.is_a?(Hash) && h.keys.sort==keys && h.values.all? { |s| s.is_a?(String) && s.valid_encoding? && s.bytesize.between?(1,160) } && h["input_digest"].match?(/\A[a-f0-9]{64}\z/) && h["handoff_id"].match?(/\A[a-f0-9]{32}\z/) && %w[prepared released running].include?(h["state"])
    end
  end
end
