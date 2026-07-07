#!/usr/bin/env ruby
# frozen_string_literal: true

path = "docs/skills/YOUTUBE_VIDEO_RESOLVE.md"

unless File.exist?(path)
  warn "Missing #{path}"
  exit 1
end

text = File.read(path)

unless text.include?("provider_error")
  insert = <<~MARKDOWN

    ## Provider error diagnostics

    Live API failures include a sanitized `provider_error` object when Google returns structured error details.

    Possible fields:

    ```text
    provider_error.message
    provider_error.reason
    provider_error.domain
    provider_error.location
    provider_error.location_type
    ```

    These diagnostics are intended to make failures such as invalid API keys, disabled APIs, quota issues, or bad request parameters easier to understand.

    The resolver must not print or log the API key. Provider diagnostics are sanitized before being returned or written to task logs.
  MARKDOWN

  text = text.rstrip + "\n" + insert
  File.write(path, text)
  puts "Patched #{path}: added sanitized provider error diagnostics documentation."
else
  puts "#{path} already documents provider_error diagnostics."
end
