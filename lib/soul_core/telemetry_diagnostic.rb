# frozen_string_literal: true
require 'timeout'
require_relative 'gpu_accounting_snapshot'
module SoulCore
  module TelemetryDiagnostic
    MESSAGES = {
      'accounting request already active'=>'accounting_busy',
      'accounting helper returned no data'=>'helper_empty',
      'accounting output bound'=>'helper_output_bound',
      'accounting trailing output'=>'helper_trailing_output',
      'accounting helper failed'=>'helper_failed',
      'accounting shape'=>'accounting_shape',
      'stale or invalid accounting'=>'accounting_stale',
      'incomplete accounting'=>'accounting_incomplete',
      'accounting unavailable: Timeout::Error'=>'helper_timeout',
      'accounting unavailable: JSON::ParserError'=>'helper_invalid_json',
      'accounting unavailable: KeyError'=>'accounting_missing_field'
    }.merge(GpuAccountingSnapshot::FAILURE_CODES.to_h { |code| ["accounting helper failed: #{code}", "helper_#{code}"] }).freeze
    CODES=(MESSAGES.values+%w[accounting_unavailable control_unavailable transport_timeout transport_error http_refused]).freeze
    class Refused < StandardError
      attr_reader :code
      def initialize(code)
        @code=CODES.include?(code) ? code : 'http_refused'
        super(@code)
      end
    end
    def self.code(error)
      return error.code if error.is_a?(Refused)
      return MESSAGES.fetch(error.message,'accounting_unavailable') if error.is_a?(GpuAccountingSnapshot::Unavailable)
      return 'transport_timeout' if error.is_a?(Timeout::Error)
      return 'transport_error' if error.is_a?(SystemCallError) || error.is_a?(IOError)
      'control_unavailable'
    end
  end
end
