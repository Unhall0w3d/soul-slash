# frozen_string_literal: true
require_relative "test-roster-warm-session"
require_relative "../lib/soul_core/roster_service_session"

class RosterServiceSessionTest < RosterWarmSessionTest
  def setup
    super
    @owner=SoulCore::RosterServiceSession.new(leases:@leases,driver:@driver,clock:-> {@time})
  end
  def test_service_starts_unloaded_and_remains_available_after_ten_minutes
    @owner.session do
      assert_equal "unloaded",@owner.status["state"]
      @time+=1000
      assert_equal :unloaded,@owner.tick
      assert_equal "answer",request
    end
  end
  def test_residency_renewal_releases_before_next_request
    @owner.session do
      request
      @time+=210
      request
      @time+=211
      request
      assert_equal 2,@driver.events.count { |e|e.first==:start }
      assert_equal 1,@driver.events.count { |e|e.first==:stop }
    end
    assert_empty retained
  end
  def test_session_deadline_cleanup_and_no_reentry_while_busy
    @owner.session do
      request do
        assert_raises(S::Unavailable) { request }
        assert_raises(S::Unavailable) { @owner.tick }
      end
      @time+=601
      assert_equal "answer",request
    end
    assert_empty retained
    assert_equal 2,@driver.events.count { |e|e.first==:stop }
  end
  def test_nested_request_cannot_release_active_residency
    @owner.session do
      request
      @time+=200
      request
      @time+=190
      request do
        @time+=31
        assert_raises(S::Unavailable) { request }
        assert_equal 0,@driver.events.count { |e|e.first==:stop }
      end
    end
  end
end
