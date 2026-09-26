"use strict";

const byId = (id) => document.getElementById(id);
const token = location.hash.slice(1);
let stream = null;
let session = 0;
let deadlineTimer = null;
let openerTimer = null;
let gestureTimer = null;
let recognizer = null;
let gestureLoad = 0;
let recentGestureFrames = [];
let lastCueAt = 0;
const MIN_GESTURE_SCORE = 0.5;
const GESTURE_WINDOW_FRAMES = 8;
const REQUIRED_GESTURE_HITS = 3;
const gestureLabels = Object.freeze({
  Open_Palm: "Open palm · hello",
  Thumb_Up: "Thumbs up · acknowledged",
  Victory: "Victory · peace"
});

function status(message) { byId("camera-status").textContent = message; }
function gestureStatus(message) { byId("gesture-status").textContent = message; }
function setControls(active) {
  byId("start-camera").disabled = active;
  byId("stop-camera").disabled = !active;
  byId("capture-frame").disabled = !active || !window.opener || !/^[a-f0-9]{32}$/.test(token);
  byId("enable-gestures").disabled = !active;
  byId("camera-indicator").textContent = active ? "Camera on" : "Camera off";
  byId("camera-indicator").classList.toggle("on", active);
  byId("camera-placeholder").hidden = active;
}
function stopGestures() {
  gestureLoad += 1;
  if (gestureTimer) clearInterval(gestureTimer);
  gestureTimer = null;
  if (recognizer) { try { recognizer.close(); } catch (_error) {} }
  recognizer = null;
  byId("enable-gestures").checked = false;
  recentGestureFrames = [];
  lastCueAt = 0;
  gestureStatus("Gesture recognition is off.");
}
function stopCamera(message = "Camera stopped. No frame was sent.") {
  session += 1;
  if (deadlineTimer) clearTimeout(deadlineTimer);
  if (openerTimer) clearInterval(openerTimer);
  deadlineTimer = null;
  openerTimer = null;
  stopGestures();
  if (stream) stream.getTracks().forEach((track) => track.stop());
  stream = null;
  const video = byId("camera-video");
  video.pause();
  video.srcObject = null;
  setControls(false);
  status(message);
}
async function startCamera() {
  if (stream || !navigator.mediaDevices?.getUserMedia || !window.isSecureContext) {
    status("Camera access requires a secure local browser context and an available camera.");
    return;
  }
  const ticket = ++session;
  byId("start-camera").disabled = true;
  status("Requesting one visible camera session…");
  try {
    const opened = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 15, max: 30 } },
      audio: false
    });
    if (ticket !== session) {
      opened.getTracks().forEach((track) => track.stop());
      return;
    }
    stream = opened;
    const video = byId("camera-video");
    video.srcObject = stream;
    const track = stream.getVideoTracks()[0];
    if (!track) { stopCamera("Camera returned no video track."); return; }
    track.addEventListener("ended", () => stopCamera("Camera device disconnected or permission ended."), { once: true });
    setControls(true);
    deadlineTimer = setTimeout(() => stopCamera("Two-minute camera session ended automatically."), 120000);
    openerTimer = setInterval(() => {
      if (window.opener && window.opener.closed) stopCamera("Soul Chat closed; camera stopped.");
    }, 1000);
    status("Camera preview is starting. Stop it at any time; it will also stop after two minutes.");
    await video.play();
    if (ticket !== session) return;
    status("Camera preview is live. Stop it at any time; it will also stop after two minutes.");
  } catch (error) {
    if (ticket === session) {
      stopCamera("Camera could not start: " + (error?.name || "Unavailable") + ". Check device connection and browser permission.");
    }
  }
}
function evaluateGesture(result) {
  const first = result?.gestures?.[0]?.[0];
  const name = first?.categoryName || "";
  const score = Number(first?.score || 0);
  const candidate = Object.hasOwn(gestureLabels, name) && score >= MIN_GESTURE_SCORE ? name : "";
  recentGestureFrames.push(candidate);
  if (recentGestureFrames.length > GESTURE_WINDOW_FRAMES) recentGestureFrames.shift();
  if (!candidate) return;
  const hits = recentGestureFrames.filter((item) => item === candidate).length;
  const now = performance.now();
  if (hits >= REQUIRED_GESTURE_HITS && now - lastCueAt >= 2000) {
    gestureStatus(gestureLabels[name] + " · local visual cue only");
    lastCueAt = now;
  }
}
async function startGestures() {
  if (!stream || recognizer) return;
  const ticket = ++gestureLoad;
  gestureStatus("Loading pinned local hand-gesture model…");
  try {
    const visionModule = await import("/api/v1/camera/gesture/vision_bundle.mjs");
    const vision = await visionModule.FilesetResolver.forVisionTasks("/api/v1/camera/gesture/wasm");
    const created = await visionModule.GestureRecognizer.createFromOptions(vision, {
      baseOptions: { modelAssetPath: "/api/v1/camera/gesture/gesture_recognizer.task" },
      runningMode: "VIDEO",
      numHands: 1
    });
    if (ticket !== gestureLoad || !stream || !byId("enable-gestures").checked) {
      created.close();
      return;
    }
    recognizer = created;
    gestureStatus("Ready · show an open palm, thumbs up, or victory sign.");
    gestureTimer = setInterval(() => {
      if (!stream || !recognizer || byId("camera-video").readyState < 2 || document.hidden) return;
      try { evaluateGesture(recognizer.recognizeForVideo(byId("camera-video"), performance.now())); }
      catch (_error) { stopGestures(); gestureStatus("Local gesture recognition stopped safely."); }
    }, 350);
  } catch (_error) {
    if (ticket === gestureLoad) {
      stopGestures();
      gestureStatus("Pinned local gesture model is unavailable; camera preview still works.");
    }
  }
}
function captureFrame() {
  if (!stream) {
    status("Start the camera before capturing a frame.");
    return;
  }
  if (!window.opener || window.opener.closed || !/^[a-f0-9]{32}$/.test(token)) {
    stopCamera("Open this window from Soul Chat to stage a picture preview.");
    return;
  }
  const video = byId("camera-video");
  if (video.readyState < 2 || !video.videoWidth || !video.videoHeight) {
    stopCamera("No camera frame was ready. Start the camera to try again.");
    return;
  }
  let outcome = "Camera capture failed. No frame was sent.";
  try {
    const scale = Math.min(1, 960 / video.videoWidth, 720 / video.videoHeight);
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
    const encoded = canvas.toDataURL("image/jpeg", 0.82).split(",")[1];
    if (!encoded || encoded.length > 14 * 1024 * 1024) {
      outcome = "The frame exceeds the local picture limit. Camera stopped.";
      return;
    }
    window.opener.postMessage({
      type: "soul.camera.snapshot.v1", token, mediaType: "image/jpeg",
      imageBase64: encoded, width: canvas.width, height: canvas.height
    }, location.origin);
    outcome = "One frame sent to Soul Chat as a preview. The camera is stopped.";
  } catch (_error) {
    outcome = "Camera capture failed. No frame was sent.";
  } finally {
    stopCamera(outcome);
  }
}
byId("start-camera").addEventListener("click", startCamera);
byId("stop-camera").addEventListener("click", () => stopCamera());
byId("capture-frame").addEventListener("click", captureFrame);
byId("enable-gestures").addEventListener("change", (event) => {
  if (event.target.checked) startGestures(); else stopGestures();
});
byId("close-camera").addEventListener("click", () => { stopCamera(); window.close(); });
document.addEventListener("visibilitychange", () => {
  if (document.hidden && stream) stopCamera("Camera stopped when the window was hidden.");
});
window.addEventListener("message", (event) => {
  const data = event.data;
  if (event.origin === location.origin && event.source === window.opener &&
      data?.type === "soul.camera.snapshot.ack" && data.token === token) {
    status(data.message || (data.ok ? "Frame staged in Soul Chat." : "Frame was not staged."));
  }
});
window.addEventListener("pagehide", () => stopCamera());
setControls(false);
if (!window.opener || !/^[a-f0-9]{32}$/.test(token)) {
  status("Start a local camera preview or gestures here. Open from Soul Chat to capture a frame into Chat.");
}
