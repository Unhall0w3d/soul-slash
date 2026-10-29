# frozen_string_literal: true
module CreativeStartPolicy
  def self.validate!(temperatures, mode:)
    limits = case mode
    when 'cold' then {'edge'=>45, 'junction'=>55, 'mem'=>90}
    when 'workday-warm' then {'edge'=>65, 'junction'=>75, 'mem'=>70}
    else raise ArgumentError, 'unknown start policy'
    end
    limits.each do |name, limit|
      value=temperatures.fetch(name)
      raise "#{mode} start temperature refused: #{name}" unless value.is_a?(Numeric) && value.finite? && value>=0 && value<limit
    end
    true
  end
end
