#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/camera_gesture_assets"
require_relative "../lib/soul_core/dashboard_http_application"

def check(name, condition)
  raise "FAIL #{name}" unless condition
  puts "PASS #{name}"
end

root = File.expand_path("..", __dir__)
assets = SoulCore::CameraGestureAssets.new(root: root)
check("all pinned gesture assets installed", SoulCore::CameraGestureAssets::ASSETS.keys.all? { |name| assets.read(name) })
check("unknown asset refused", assets.read("../dashboard.js").nil?)

auth = Class.new do
  def session(token) = token == "fixture" ? { "password_change_required" => false } : nil
end.new
app = SoulCore::DashboardHttpApplication.new(root: root, facade: Object.new,
  bind_host: "127.0.0.1", port: 4567, authentication: auth)
plain = { "host" => "127.0.0.1:4567" }
signed = plain.merge("cookie" => "soul_session=fixture")
main = app.call(method: "GET", target: "/", headers: plain)
camera_unauth = app.call(method: "GET", target: "/camera", headers: plain)
camera = app.call(method: "GET", target: "/camera", headers: signed)
asset_unauth = app.call(method: "GET", target: "/api/v1/camera/gesture/vision_bundle.mjs", headers: plain)
asset = app.call(method: "GET", target: "/api/v1/camera/gesture/vision_bundle.mjs", headers: signed)
wasm = app.call(method: "GET", target: "/api/v1/camera/gesture/wasm/vision_wasm_internal.wasm", headers: signed)
post = app.call(method: "POST", target: "/camera", headers: signed)
traversal = app.call(method: "GET", target: "/api/v1/camera/gesture/../dashboard.js", headers: signed)
check("camera page requires dashboard login", camera_unauth.status == 401 && asset_unauth.status == 401)
check("camera page has scoped camera and wasm policy",
  camera.status == 200 && camera.headers["Permissions-Policy"].include?("camera=(self)") &&
    camera.headers["Content-Security-Policy"].include?("'wasm-unsafe-eval'"))
check("main dashboard keeps camera and wasm disabled",
  main.headers["Permissions-Policy"].include?("camera=()") &&
    !main.headers["Content-Security-Policy"].include?("wasm-unsafe-eval"))
check("only pinned local gesture resources are served",
  asset.status == 200 && asset.headers["Content-Type"].start_with?("text/javascript") &&
    wasm.status == 200 && wasm.headers["Content-Type"] == "application/wasm")
check("camera route method and traversal refused", post.status == 405 && traversal.status == 404)
html = File.read(File.join(root, "assets/dashboard/index.html"))
js = File.read(File.join(root, "assets/dashboard/dashboard.js"))
check("Chat camera preview validates origin, source, and token",
  html.include?('id="open-camera"') && js.include?("event.origin !== location.origin") &&
    js.include?("event.source !== state.cameraPopup") && js.include?("data.token !== state.cameraToken"))
