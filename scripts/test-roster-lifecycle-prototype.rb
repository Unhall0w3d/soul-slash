# frozen_string_literal: true
require "minitest/autorun"
require_relative "support/roster_lifecycle_prototype"

class RosterLifecyclePrototypeTest < Minitest::Test
  P=RosterLifecyclePrototype
  def setup = @p=P.new
  def idle(model=P::MODELS.first, now:0)
    assert_equal :load,@p.request(model,now:now)[:action]
    assert_equal :admit,@p.loaded(@p.ticket,now:now)[:action]
    assert_equal :generate,@p.admitted(@p.ticket,now:now)[:action]
    @p.finished(@p.ticket,now:now)
  end

  def test_reuse_still_requires_admission_and_expiry_is_exact
    idle
    assert_equal :none,@p.tick(now:239.999)[:action]
    assert_equal :admit,@p.request(P::MODELS.first,now:239.999)[:action]
    assert_equal :generate,@p.admitted(@p.ticket,now:240)[:action]
    assert_equal :none,@p.tick(now:1000)[:action] # busy work never idle-evicted
    @p.finished(@p.ticket,now:1001)
    assert_equal :unload,@p.tick(now:1241)[:action]
  end

  def test_switch_cannot_load_until_release_confirmed
    idle
    assert_equal :unload,@p.request(P::MODELS.last,now:1)[:action]
    release_ticket=@p.ticket
    assert_raises(P::Refused) { @p.request(P::MODELS.last,now:1) }
    assert_raises(P::Refused) { @p.loaded(release_ticket,now:1) }
    assert_equal :load,@p.released(release_ticket,now:2)[:action]
    assert_equal P::MODELS.last,@p.model
    assert_raises(P::Refused) { @p.released(release_ticket,now:2) }
  end

  def test_cancel_during_switch_drops_pending_load
    idle
    @p.request(P::MODELS.last,now:1)
    ticket=@p.ticket
    @p.cancel(now:2)
    assert_equal :none,@p.released(ticket,now:3)[:action]
    assert_equal :unloaded,@p.state
  end

  def test_uncertain_release_blocks_every_new_request
    idle
    @p.cancel(now:1)
    assert_equal :review_required,@p.release_failed(@p.ticket,now:2)[:action]
    P::MODELS.each { |m| assert_raises(P::Refused) { @p.request(m,now:3) } }
    assert_equal :none,@p.shutdown(now:4)[:action]
    assert_equal :blocked,@p.state
  end

  def test_canceled_load_cannot_complete_late
    @p.request(P::MODELS.first,now:0)
    old=@p.ticket
    @p.cancel(now:1)
    assert_raises(P::Refused) { @p.loaded(old,now:2) }
    @p.released(@p.ticket,now:3)
    assert_equal :unloaded,@p.state
  end

  def test_shutdown_never_autoloads_or_accepts_new_work
    idle
    @p.request(P::MODELS.last,now:1)
    ticket=@p.ticket
    @p.shutdown(now:2)
    assert_equal :none,@p.released(ticket,now:3)[:action]
    assert_raises(P::Refused) { @p.request(P::MODELS.first,now:4) }
  end

  def test_seeded_idle_and_stale_callback_boundaries
    rng=Random.new(20261023)
    100.times do
      @p=P.new(idle_seconds:rng.rand(180..300))
      idle(now:0)
      old=@p.ticket-1
      assert_raises(P::Refused) { @p.finished(old,now:1) }
      assert_equal :idle,@p.state
      action=@p.tick(now:301)
      assert_equal :unload,action[:action]
      assert_equal :none,@p.released(@p.ticket,now:302)[:action]
      assert_equal :unloaded,@p.state
    end
  end

  def test_invalid_time_and_configuration
    [179,301,240.5].each { |n| assert_raises(ArgumentError) { P.new(idle_seconds:n) } }
    [Float::NAN,Float::INFINITY,-1,"1"].each { |n| assert_raises(P::Refused) { @p.tick(now:n) } }
    @p.tick(now:10)
    assert_raises(P::Refused) { @p.tick(now:9) }
  end
end
