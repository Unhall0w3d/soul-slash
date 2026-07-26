#!/usr/bin/env ruby
# frozen_string_literal: true

css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
checks = {
  "presence remains part of the transmission rail" =>
    html.index('class="chat-list"') < html.index('class="soul-presence"') &&
      html.index('class="soul-presence"') < html.index('class="rail-footer"'),
  "mobile rail is not height-capped or clipping children" =>
    css.include?(".conversation-rail { min-height:0; max-height:none; margin-bottom:12px; overflow:visible; }"),
  "mobile transmission list has an independent bounded scroll area" =>
    css.include?(".conversation-rail .chat-list { flex:none; min-height:92px; max-height:240px; }") &&
      css.include?(".chat-list { flex:1; overflow-y:auto; overflow-x:hidden;"),
  "mobile presence card becomes a compact readable strip" =>
    css.include?(".soul-presence { min-height:116px; grid-template-columns:78px minmax(0,1fr);") &&
      css.include?(".soul-familiar { width:70px; height:98px; }")
}

checks.each { |label, passed| puts "#{passed ? 'PASS' : 'FAIL'}: #{label}" }
abort "Mobile chat presence layout verification failed." unless checks.values.all?
