"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const elements = new Map();
function element(id) {
  if (!elements.has(id)) {
    const listeners = {};
    const value = { id, listeners, disabled: false, hidden: false, checked: false,
      textContent: "", readyState: 4, videoWidth: 640, videoHeight: 480,
      classList: { toggle() {} }, addEventListener(name, callback) { listeners[name] = callback; },
      play: async () => {}, pause() {}, getContext: () => ({ drawImage() {} }),
      toDataURL: () => "data:image/jpeg;base64,YWJj" };
    elements.set(id, value);
  }
  return elements.get(id);
}
const sent = [];
const deadlines = [];
let tracks = [];
const opener = { closed: false, postMessage: (payload, origin) => sent.push({ payload, origin }) };
const document = { hidden: false, getElementById: element,
  createElement: () => element("canvas"), addEventListener(name, callback) { this[name] = callback; } };
const window = { isSecureContext: true, opener, close() {}, addEventListener(name, callback) { this[name] = callback; } };
const navigator = { mediaDevices: { getUserMedia: async (request) => {
  assert.strictEqual(request.audio, false);
  assert(request.video);
  const track = { stopped: false, stop() { this.stopped = true; }, addEventListener() {} };
  tracks.push(track);
  return { getTracks: () => [track], getVideoTracks: () => [track] };
} } };
const context = { document, window, navigator, location: { hash: "#" + "a".repeat(32), origin: "http://127.0.0.1:4567" },
  performance: { now: () => 1000 }, setInterval: () => 1, clearInterval() {}, setTimeout: (callback) => { deadlines.push(callback); return deadlines.length; }, clearTimeout() {}, console };
vm.runInNewContext(fs.readFileSync("assets/camera/camera.js", "utf8"), context);
(async () => {
  await element("start-camera").listeners.click();
  assert.strictEqual(element("camera-indicator").textContent, "Camera on");
  element("stop-camera").listeners.click();
  assert(tracks[0].stopped);
  await element("start-camera").listeners.click();
  element("capture-frame").listeners.click();
  assert(tracks[1].stopped);
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(sent[0].payload.type, "soul.camera.snapshot.v1");
  assert.strictEqual(sent[0].origin, "http://127.0.0.1:4567");
  await element("start-camera").listeners.click();
  document.hidden = true;
  document.visibilitychange();
  assert(tracks[2].stopped);
  context.performance.now = () => 3000;
  const gesture = (name, score) => ({ gestures: [[{ categoryName: name, score }]] });
  context.evaluateGesture(gesture("Closed_Fist", 0.99));
  context.evaluateGesture(gesture("Open_Palm", 0.49));
  context.evaluateGesture(gesture("Open_Palm", 0.58));
  context.evaluateGesture(gesture("None", 0.91));
  context.evaluateGesture(gesture("Open_Palm", 0.58));
  assert(!element("gesture-status").textContent.includes("Open palm"));
  context.evaluateGesture(gesture("Open_Palm", 0.58));
  assert(element("gesture-status").textContent.includes("Open palm"));
  context.stopGestures();
  for (let index = 0; index < 8; index++) context.evaluateGesture(gesture("None", 0.99));
  assert(!element("gesture-status").textContent.includes("Open palm"));
  document.hidden = false;
  let resumePlayback;
  element("camera-video").play = () => new Promise((resolve) => { resumePlayback = resolve; });
  const pendingStart = element("start-camera").listeners.click();
  await new Promise((resolve) => setImmediate(resolve));
  const stalledTrack = tracks.at(-1);
  assert.strictEqual(element("stop-camera").disabled, false, "stop must work while video.play is pending");
  assert.strictEqual(element("camera-indicator").textContent, "Camera on");
  deadlines.at(-1)();
  assert(stalledTrack.stopped, "two-minute deadline must stop a stalled playback stream");
  resumePlayback();
  await pendingStart;
  assert.strictEqual(element("camera-indicator").textContent, "Camera off");
  element("camera-video").play = async () => {};
  element("camera-video").videoWidth = 0;
  await element("start-camera").listeners.click();
  const notReadyTrack = tracks.at(-1);
  element("capture-frame").listeners.click();
  assert(notReadyTrack.stopped, "capture without a ready frame must stop the stream");
  element("camera-video").videoWidth = 640;
  element("camera-video").readyState = 1;
  const sentBeforeUnready = sent.length;
  await element("start-camera").listeners.click();
  const unreadyTrack = tracks.at(-1);
  element("capture-frame").listeners.click();
  assert(unreadyTrack.stopped, "capture before a current video frame must stop the stream");
  assert.strictEqual(sent.length, sentBeforeUnready, "capture before a current video frame must not send stale pixels");
  element("camera-video").readyState = 4;
  const originalEncode = element("canvas").toDataURL;
  element("canvas").toDataURL = () => { throw new Error("canvas unavailable"); };
  await element("start-camera").listeners.click();
  const failedEncodeTrack = tracks.at(-1);
  element("capture-frame").listeners.click();
  assert(failedEncodeTrack.stopped, "canvas failure must stop the stream");
  element("canvas").toDataURL = originalEncode;
  console.log("PASS explicit camera start/stop, one-frame transfer, hidden-window shutdown, intermittent local palm cue, stalled playback, and capture failures");
})().catch((error) => { console.error(error); process.exitCode = 1; });
