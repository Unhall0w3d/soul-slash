# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../lib/soul_core/cpu_member_loopback_client'
class CpuMemberLoopbackClientTest < Minitest::Test
 C=SoulCore::CpuMemberLoopbackClient
 class Http
  attr_accessor :open_timeout,:read_timeout,:write_timeout
  attr_reader :finished
  def start;@started=true;end
  def started?;@started;end
  def request(*);sleep 5;end
  def finish;@finished=true;@started=false;end
 end
 def with_http(http)
  original=Net::HTTP.method(:new)
  Net::HTTP.define_singleton_method(:new){|*|http}
  yield
 ensure
  Net::HTTP.define_singleton_method(:new,original)
 end
 def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
 def test_cancel_closes_worker_socket
  http=Http.new;cancel=false;timer=Thread.new{sleep 0.08;cancel=true}
  with_http(http) do
   assert_raises(C::Stopped){C.new.request('POST','/v1/chat/completions',{},deadline:now+1,cancel:->{cancel})}
  end
  timer.join;assert http.finished
 end
 def test_deadline_closes_worker_socket
  http=Http.new
  with_http(http) do
   assert_raises(C::Stopped){C.new.request('POST','/v1/chat/completions',{},deadline:now+0.08,cancel:->{false})}
  end
  assert http.finished
 end
 def test_fixed_endpoint_and_initial_cancel
  assert_raises(C::Stopped){C.new.request('POST','http://example.com',{},deadline:now+1,cancel:->{false})}
  assert_raises(C::Stopped){C.new.request('POST','/tokenize',{},deadline:now+1,cancel:->{true})}
 end
end
