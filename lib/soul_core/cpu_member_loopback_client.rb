# frozen_string_literal: true
require 'net/http'
require 'json'
require 'timeout'
module SoulCore
  # Bound to the foreground owner's temporary endpoint. Closing the connection
  # on cancellation propagates disconnect to llama.cpp; the owner verifies idle.
  class CpuMemberLoopbackClient
    class Stopped < StandardError; end
    def request(method,path,payload,deadline:,cancel:)
      raise Stopped,'endpoint refused' unless method=='POST'&&%w[/apply-template /tokenize /v1/chat/completions].include?(path)
      raise Stopped,'deadline' unless deadline.is_a?(Numeric)&&deadline.finite?&&(deadline-now).between?(0.001,180)
      raise Stopped,'canceled' if cancel.call
      http=Net::HTTP.new('127.0.0.1',18084,nil);http.open_timeout=2;http.read_timeout=[deadline-now,120].min;http.write_timeout=2
      result=Queue.new
      thread=Thread.new do
        begin
          http.start
          req=Net::HTTP::Post.new(path,{'Content-Type'=>'application/json'});req.body=JSON.generate(payload)
          raise Stopped,'request bound' if req.body.bytesize>131_072
          bytes=''.b
          http.request(req) do |response|
            raise Stopped,'transport status' unless response.code=='200'
            response.read_body{|chunk|bytes<<chunk;raise Stopped,'response bound' if bytes.bytesize>524_288}
          end
          result<<[:ok,JSON.parse(bytes,allow_duplicate_key:false)]
        rescue StandardError=>e
          result<<[:error,e.class.name]
        ensure
          begin
            http.finish if http.started?
          rescue IOError, SystemCallError
            nil
          end
        end
      end
      loop do
        raise Stopped,'canceled or expired' if cancel.call || now>=deadline
        unless result.empty?
          kind,value=result.pop;raise Stopped,"transport failed (#{value})" unless kind==:ok
          return value
        end
        sleep 0.02
      end
    ensure
      # The worker's ensure closes its socket; it cannot survive this call.
      thread&.kill if thread&.alive?
      thread&.join
    end
    private
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
