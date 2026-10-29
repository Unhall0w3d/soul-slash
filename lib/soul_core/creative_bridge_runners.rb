# frozen_string_literal: true
require_relative 'bounded_command_runner'
require_relative 'music_generation_service'
module SoulCore
  # Compose cancellation with the original thermal/memory monitor. Returning
  # from the owned runners means their child process group has been reaped.
  class CreativeBridgeCommandRunner
    def initialize(cancel:,runner:BoundedCommandRunner.new);@cancel,@runner=cancel,runner;end
    def which(name)=@runner.which(name)
    def run(*command,**options,&block)
      raise 'Creative generation canceled before spawn' if @cancel.call
      monitor=options.delete(:monitor)
      @runner.run(*command,**options,monitor:->(pid){raise 'Creative generation canceled' if @cancel.call;monitor&.call(pid)},&block)
    end
  end
  class CreativeBridgeMusicRunner
    def initialize(cancel:,runner:MusicGenerationService::ForegroundProcessRunner.new);@cancel,@runner=cancel,runner;end
    def run(command,**options)
      native=options.fetch(:canceled)
      @runner.run(command,**options.merge(canceled:->{@cancel.call||native.call}))
    end
  end
end
