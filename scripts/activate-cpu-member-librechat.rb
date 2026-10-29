#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'activate-continuity-librechat-a24'
if $PROGRAM_NAME==__FILE__
  exit ContinuityLibreChatA24.run(staged_path:File.join(ContinuityLibreChatA24::ROOT,'docs/examples/cpu-member-librechat.yaml'))
end
