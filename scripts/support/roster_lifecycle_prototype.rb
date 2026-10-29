# frozen_string_literal: true

# Pure experimental state machine. It owns no process, lease, socket, timer or
# storage. Its actions are test proposals, NOT permission to execute anything.
class RosterLifecyclePrototype
  MODELS=%w[gpt-oss-20b gemma-4-26b-a4b].freeze
  class Refused < StandardError; end
  attr_reader :state, :model, :ticket

  def initialize(idle_seconds: 240)
    raise ArgumentError unless idle_seconds.is_a?(Integer) && idle_seconds.between?(180,300)
    @idle_seconds=idle_seconds
    @state=:unloaded
    @ticket=0
    @closed=false
  end

  def request(model, now:)
    time!(now)
    raise Refused,"unknown model" unless MODELS.include?(model)
    raise Refused,"session closed" if @closed
    case state
    when :unloaded then load(model)
    when :idle
      if now>=@idle_until || model!=@model
        @pending=model.dup.freeze
        release
      else
        transition(:admitting,:admit)
      end
    else raise Refused,"busy or retained uncertainty; no hidden queue"
    end
  end

  def loaded(ticket, now:)
    check!(:loading,ticket,now)
    transition(:admitting,:admit)
  end

  def admitted(ticket, now:)
    check!(:admitting,ticket,now)
    transition(:busy,:generate)
  end

  def finished(ticket, now:)
    check!(:busy,ticket,now)
    @idle_until=now+@idle_seconds
    transition(:idle,:idle)
  end

  def tick(now:)
    time!(now)
    state==:idle && now>=@idle_until ? release : action(:none)
  end

  def cancel(now:)
    time!(now)
    @pending=nil
    return action(:none) if %i[unloaded releasing blocked].include?(state)
    release
  end

  def shutdown(now:)
    time!(now)
    @closed=true
    cancel(now:now)
  end

  def released(ticket, now:)
    check!(:releasing,ticket,now)
    target=@pending
    @pending=@model=nil
    @state=:unloaded
    target && !@closed ? load(target) : transition(:unloaded,:none)
  end

  def release_failed(ticket, now:)
    check!(:releasing,ticket,now)
    @pending=nil
    transition(:blocked,:review_required)
  end

  private

  def time!(now)
    raise Refused,"invalid monotonic time" unless now.is_a?(Numeric) && now.finite? && now>=0 && (!@last_time || now>=@last_time)
    @last_time=now
  end

  def check!(expected,ticket,now)
    time!(now)
    raise Refused,"stale or unexpected completion" unless state==expected && ticket==@ticket
  end

  def load(model)
    @model=model.dup.freeze
    transition(:loading,:load)
  end

  def release = transition(:releasing,:unload)

  def transition(state,action)
    @state=state
    @ticket+=1
    self.action(action)
  end

  def action(kind) = {action:kind,model:@model,ticket:@ticket,state:@state}.freeze
end
