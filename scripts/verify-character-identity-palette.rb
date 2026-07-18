#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require_relative "../lib/soul_core/dashboard_http_application"

ROOT = File.expand_path("..", __dir__)
EXPECTED_GEOMETRY_DIGEST = "8e845c6da7738f29aaf2fe936903604dd935cadb60205a326b748e19f4b65855"
EXPECTED_ASSETS = {
  "assets/brand/character/soul-full-body.png" => "0ec66837f85ad0cd08a98ad962327c657481d53a40c619a63f7683c7d5cf832b",
  "assets/brand/character/soul-portrait-masked.png" => "9526461ed0b5d3f9425fef76230dc7a66fce489c6a1cb52fdfaf8767b172d554",
  "assets/brand/character/soul-portrait-unmasked.png" => "846ba3ed9b384aaf8343845032d8d4028b7adb939fbd8eac9d778ec4184ad414"
}.freeze

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def png_dimensions(path)
  data = File.binread(path, 24)
  raise "not PNG" unless data.start_with?("\x89PNG\r\n\x1A\n".b) && data.byteslice(12, 4) == "IHDR"

  data.byteslice(16, 8).unpack("NN")
end

def relative_luminance(hex)
  hex.scan(/../).map { |part| part.to_i(16) / 255.0 }.map { |value| value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4 }
     .then { |red, green, blue| (0.2126 * red) + (0.7152 * green) + (0.0722 * blue) }
end

def contrast(foreground, background)
  high, low = [relative_luminance(foreground), relative_luminance(background)].sort.reverse
  (high + 0.05) / (low + 0.05)
end

puts "Soul character identity and palette verification:"

EXPECTED_ASSETS.each do |relative, digest|
  path = File.join(ROOT, relative)
  check.call("#{File.basename(path)} is the exact reviewed source", File.file?(path) && Digest::SHA256.file(path).hexdigest == digest)
  check.call("#{File.basename(path)} retains 941x1672 PNG geometry", File.file?(path) && png_dimensions(path) == [941, 1672])
end

routes = SoulCore::DashboardHttpApplication::STATIC_ROUTES
expected_routes = {
  "/brand/character/soul-full-body.png" => "assets/brand/character/soul-full-body.png",
  "/brand/character/soul-portrait-masked.png" => "assets/brand/character/soul-portrait-masked.png",
  "/brand/character/soul-portrait-unmasked.png" => "assets/brand/character/soul-portrait-unmasked.png"
}
check.call("all character assets use explicit same-origin PNG routes", expected_routes.all? { |route, path| routes[route] == [path, "image/png"] })

application = SoulCore::DashboardHttpApplication.new(root: ROOT, facade: Object.new, bind_host: "127.0.0.1", port: 4567, authentication: Object.new)
delivered = expected_routes.all? do |route, relative|
  response = application.call(method: "GET", target: route, headers: { "Host" => "127.0.0.1:4567" })
  response.status == 200 && response.headers["Content-Type"] == "image/png" && response.body == File.binread(File.join(ROOT, relative))
end
check.call("dashboard serves exact character bytes without remote dependencies", delivered)

html = File.read(File.join(ROOT, "assets/dashboard/index.html"))
css = File.read(File.join(ROOT, "assets/dashboard/dashboard.css"))
js = File.read(File.join(ROOT, "assets/dashboard/dashboard.js"))
svg = File.read(File.join(ROOT, "assets/brand/soul-slash-micro-mark.svg"))
brief = File.read(File.join(ROOT, "docs/soul/CHARACTER_IDENTITY_AND_PALETTE_BRIEF.md"))

check.call("chat familiar contains both reviewed portrait states", html.include?('class="familiar-portrait familiar-portrait--unmasked"') && html.include?('class="familiar-portrait familiar-portrait--masked"'))
check.call("idle is masked and subdued while active requests reveal the brighter unmasked portrait", css.include?('.familiar-portrait--unmasked { opacity:0; filter:brightness(.7)') && css.include?('.familiar-portrait--masked { opacity:1; filter:brightness(.58)') && css.include?(':not([data-state="received"])') && css.include?('.familiar-portrait--unmasked { opacity:1; filter:brightness(1.08)') && !js.match?(/setInterval|setTimeout|requestAnimationFrame/))
check.call("portrait remains decorative while textual status stays live", html.include?('class="soul-familiar" aria-hidden="true"') && html.include?('id="soul-activity-summary" aria-live="polite"'))
check.call("portrait framing is responsive and motion-safe", css.include?("object-fit:cover") && css.include?("object-position:50% 29%") && css.include?("prefers-reduced-motion:reduce"))

palette = %w[#0B0D13 #161B25 #19222C #273746 #303867 #3AAEDF #64A8D2 #A9D1E4 #D4E2EA #93A5B9 #A77B5B #5B4033 #D0A785]
check.call("dashboard declares the portrait-derived palette", palette.all? { |color| css.downcase.include?(color.downcase) || brief.include?(color) })
check.call("prior neon and yellow structural accents are absent", ![css, js, svg].join.match?(/#00E5FF|#D4AF37|#F0D46F|0,229,255|212,175,55/i))
check.call("destructive crimson remains semantically distinct", css.include?("--danger:#FF1744") && css.include?(".danger-button"))

contrast_pairs = {
  "primary copy" => %w[A9D1E4 273746],
  "strong copy" => %w[D4E2EA 273746],
  "muted copy" => %w[93A5B9 273746],
  "cerulean accent" => %w[3AAEDF 273746],
  "bronze label" => %w[A77B5B 161B25],
  "bronze highlight" => %w[D0A785 273746]
}
contrast_pairs.each { |label, (foreground, background)| check.call("#{label} meets 4.5:1 text contrast", contrast(foreground, background) >= 4.5) }

geometry = {
  view_box: svg[/viewBox="([^"]+)"/, 1],
  paths: svg.scan(/<path\b[^>]*\bd="([^"]+)"/).flatten,
  circles: svg.scan(/<circle\b[^>]*\bcx="([^"]+)"[^>]*\bcy="([^"]+)"[^>]*\br="([^"]+)"/),
  stroke_widths: svg.scan(/stroke-width="([^"]+)"/).flatten
}
check.call("favicon geometry is unchanged while its palette is recolored", Digest::SHA256.hexdigest(JSON.generate(geometry)) == EXPECTED_GEOMETRY_DIGEST && svg.include?("#3aaedf") && svg.include?("#a77b5b"))
check.call("implementation brief forbids behavioral and remote-asset expansion", brief.include?("No conversation, model, memory, skill, Core, service, authentication, or") && brief.include?("No external image generation"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Character identity and palette are candidate-ready for human review."
