# frozen_string_literal: true

require "json"
require "optparse"
require_relative "dev_worker_command"
require_relative "dev_worker_vault_context_service"

module SoulCore
  class DevWorkerVaultContextCommand < DevWorkerCommand
    def initialize(argv:, root: Dir.pwd, env: ENV, output: $stdout, service: nil)
      super(
        argv: argv,
        root: root,
        env: env,
        output: output,
        service: service || DevWorkerVaultContextService.new(root: root, env: env)
      )
    end
  end
end
