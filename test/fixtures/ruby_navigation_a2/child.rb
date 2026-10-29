require_relative 'alpha'
require_relative 'location'
module NavigationPilot
  class Child < Alpha::Worker
    include Located
    def report
      perform
    end
    def whereabouts
      location
    end
  end
end
