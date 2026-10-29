# frozen_string_literal: true
require_relative 'roster_runtime_owner'
module SoulCore
  # Raised only before owning a job or entering its durable journal.
  class RosterAdmissionBusy < RosterRuntimeOwner::Unavailable
    MESSAGE = 'Soul is busy with another request. Your request was not started. Wait for the current request to finish, then try again.'
  end
end
