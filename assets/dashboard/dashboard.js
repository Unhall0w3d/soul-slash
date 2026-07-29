"use strict";

const csrf = document.querySelector('meta[name="soul-csrf"]').content;
const TAB_LOCATIONS = Object.freeze({ chat: "#chat-panel", timeline: "#timeline-panel", studio: "#studio-panel", improvement: "#improvement-panel", augmentation: "#augmentation-panel", music: "#music-panel", visual: "#visual-panel", maintenance: "#maintenance-panel", backup: "#backup-panel" });
const state = { authenticated: false, bootstrapped: false, chats: [], activeChat: null, busy: false, voiceRecorder: null, voiceStream: null, voiceChunks: [], voiceStartedAt: 0, voiceDiscard: false, voiceTranscribing: false, voicePlayback: null, voicePlaybackUrl: null, voiceSynthesisController: null, voiceSynthesisButton: null, clearPreview: null, forgetPreview: null, coreStatus: null, modelRuntime: null, modelRuntimePreview: null, studioLoaded: false, proposals: [], betas: [], productionSkills: [], linkedProductionSkill: null, selectedProposal: null, selectedBeta: null, proposalApproval: null, betaBuildPreview: null, proposalClosePreview: null, betaRunPreview: null, betaPromotionPreview: null, productionPromotionPreview: null, improvementLoaded: false, improvementProposalPreview: null, hostPlanPreview: null, selectedHostPlan: null, augmentationLoaded: false, augmentationPreview: null, augmentationProposals: [], selectedAugmentationProposal: null, augmentationExperiments: [], selectedAugmentationExperiment: null, augmentationExperimentPreview: null, augmentationGateA2Preview: null, augmentationCleanupPreview: null, augmentationModelPreview: null, musicLoaded: false, musicProjects: [], musicProjectView: "active", musicReferences: { artists: [], tracks: [], fusions: [] }, musicReferencePreview: null, musicReferenceAnalyzing: false, selectedMusicReference: null, musicReferenceDelete: null, musicReferenceReanalysis: null, musicSynthesisApproval: null, musicSynthesisRejection: null, musicSynthesisBusy: false, musicFusionSources: new Set(), selectedMusicProject: null, musicProjectDeletePreview: null, musicPreview: null, musicGenerating: false, musicCandidateId: null, reviewLoaded: false, approvals: [], activities: [], activitySummary: [], activityFilter: "all", selectedApproval: null, selectedActivity: null, reviewOpener: null };
const byId = (id) => document.getElementById(id);
state.musicJobId = null;
state.voiceRoundTripPending = false;
state.pictureAttachment = null;
state.screenCapturing = false;
Object.assign(state, { visualLoaded: false, visualProjects: [], visualProjectView: "active", selectedVisualProject: null, visualPreview: null, visualGenerating: false, visualProjectDeletePreview: null });
Object.assign(state, { timelineLoaded: false, projectTracker: null, selectedTimelineItem: null });
Object.assign(state, { invocationRecords: [], invocationCategories: [], selectedInvocation: null, invocationOpener: null });
Object.assign(state, { backupLoaded: false, backupSnapshots: [], backupCreatePreview: null, backupRetentionPreview: null, backupRestorePreview: null, backupBusy: false });
state.maintenancePreview = null;
state.maintenanceFleet = null;
state.maintenanceFleetLoaded = false;
state.maintenanceDevicePreview = null;
state.maintenanceDiscoveryCandidates = [];
state.maintenanceDiscoveryRegistry = [];
state.maintenanceEnrollmentPreview = null;
state.maintenanceRemovalPreview = null;
state.chatProgress = new Map();
state.localChatRequests = new Set();
const VOICE_OUTPUT_PROFILES = new Set(["F3", "M3"]);
const VOICE_OUTPUT_QUALITIES = new Set(["responsive", "expressive"]);
const NOTIFICATION_MODES = ["voice", "cues", "muted"];
const NOTIFICATION_EVENTS = Object.freeze({
  submit: { cue: "submit" },
  chat_ready: { cue: "complete", spoken: "chat-ready" },
  music_ready: { cue: "complete", spoken: "music-ready" },
  visual_ready: { cue: "complete", spoken: "visual-ready" },
  lyrics_ready: { cue: "complete", spoken: "lyrics-ready" },
  attention: { cue: "attention", spoken: "attention" }
});
try { const storedVoice = localStorage.getItem("soul.voice.output.profile"); state.voiceOutputProfile = VOICE_OUTPUT_PROFILES.has(storedVoice) ? storedVoice : "F3"; } catch (_error) { state.voiceOutputProfile = "F3"; }
try { const storedQuality = localStorage.getItem("soul.voice.output.quality"); state.voiceOutputQuality = VOICE_OUTPUT_QUALITIES.has(storedQuality) ? storedQuality : "responsive"; } catch (_error) { state.voiceOutputQuality = "responsive"; }
try { const storedMode = localStorage.getItem("soul.notifications.mode"); state.notificationMode = NOTIFICATION_MODES.includes(storedMode) ? storedMode : "voice"; } catch (_error) { state.notificationMode = "voice"; }
state.notificationPlayback = null;
state.notificationKeys = new Set();

function renderNotificationMode() {
  const button = byId("notification-mode"); if (!button) return;
  const labels = { voice: "Alerts Voice", cues: "Alerts Cues", muted: "Alerts Muted" };
  button.querySelector("span").textContent = labels[state.notificationMode];
  button.dataset.mode = state.notificationMode;
  button.title = state.notificationMode === "voice"
    ? "Cues plus pre-generated speech while Voice Presence is open and idle · click to change"
    : (state.notificationMode === "cues" ? "Nonverbal notification cues only · click to change" : "Local notifications muted · click to change");
}

function cycleNotificationMode() {
  const index = NOTIFICATION_MODES.indexOf(state.notificationMode);
  state.notificationMode = NOTIFICATION_MODES[(index + 1) % NOTIFICATION_MODES.length];
  try { localStorage.setItem("soul.notifications.mode", state.notificationMode); } catch (_error) { /* session preference remains */ }
  renderNotificationMode();
  announce(`${byId("notification-mode").querySelector("span").textContent} selected`);
}

function playNotificationFile(path, volume) {
  return new Promise((resolve) => {
    if (state.notificationPlayback) {
      state.notificationPlayback.pause();
      state.notificationPlayback.src = "";
    }
    const audio = new Audio(path); state.notificationPlayback = audio; audio.volume = volume;
    const finish = () => { if (state.notificationPlayback === audio) state.notificationPlayback = null; resolve(); };
    audio.addEventListener("ended", finish, { once: true });
    audio.addEventListener("error", finish, { once: true });
    audio.play().catch(finish);
  });
}

async function voicePresenceReceipt() {
  try {
    const response = await fetch("/api/v1/voice/presence/status", { credentials: "same-origin", cache: "no-store" });
    const result = await response.json();
    return response.ok ? result.data || {} : {};
  } catch (_error) { return {}; }
}

async function emitSoulNotification(eventName, uniqueKey = null) {
  const event = NOTIFICATION_EVENTS[eventName]; if (!event || state.notificationMode === "muted") return;
  if (uniqueKey && state.notificationKeys.has(uniqueKey)) return;
  if (uniqueKey) {
    state.notificationKeys.add(uniqueKey);
    if (state.notificationKeys.size > 100) state.notificationKeys.delete(state.notificationKeys.values().next().value);
  }
  await playNotificationFile(`/notifications/cue-${event.cue}.wav`, 0.48);
  if (state.notificationMode !== "voice" || !event.spoken) return;
  const presence = await voicePresenceReceipt();
  if (presence.running !== true || presence.presence_state !== "listening") return;
  const voice = presence.notification_voice === "M3" ? "m3" : "f3";
  await playNotificationFile(`/notifications/${voice}-${event.spoken}.wav`, 0.78);
}

function formatBytes(value) {
  const bytes = Number(value); if (!Number.isFinite(bytes) || bytes < 0) return "unavailable";
  const units = ["B", "KiB", "MiB", "GiB", "TiB"]; let amount = bytes; let unit = 0;
  while (amount >= 1024 && unit < units.length - 1) { amount /= 1024; unit += 1; }
  return `${amount >= 10 || unit === 0 ? amount.toFixed(0) : amount.toFixed(1)} ${units[unit]}`;
}

function invocationDetailRow(term, value) {
  const row = document.createElement("div");
  const dt = document.createElement("dt"); dt.textContent = term;
  const dd = document.createElement("dd"); dd.textContent = value;
  row.append(dt, dd); return row;
}

function renderInvocationDetail(record) {
  state.selectedInvocation = record;
  const detail = byId("invocation-detail"); detail.replaceChildren();
  const eyebrow = document.createElement("p"); eyebrow.className = "eyebrow"; eyebrow.textContent = `${record.category} · ${record.status}`;
  const heading = document.createElement("h3"); heading.textContent = record.label;
  const summary = document.createElement("p"); summary.className = "invocation-summary"; summary.textContent = record.summary;
  const facts = document.createElement("dl"); facts.className = "invocation-facts";
  facts.append(
    invocationDetailRow("Required", record.required_inputs?.length ? record.required_inputs.join(" · ") : "No required fields"),
    invocationDetailRow("Optional", record.optional_inputs?.length ? record.optional_inputs.join(" · ") : "None"),
    invocationDetailRow("Core", record.core),
    invocationDetailRow("Approval", record.approval),
    invocationDetailRow("Result", record.output),
    invocationDetailRow("Boundary", record.boundary)
  );
  const exampleHeading = document.createElement("p"); exampleHeading.className = "eyebrow"; exampleHeading.textContent = "Example wording · inert";
  const example = document.createElement("code"); example.className = "invocation-example"; example.textContent = record.examples?.[0] || "No example supplied.";
  const note = document.createElement("p"); note.className = "muted"; note.textContent = "Reading or copying this example provides no authority. A later request still enters the owning deterministic gate.";
  detail.append(eyebrow, heading, summary, facts, exampleHeading, example, note);
  byId("invocation-list").querySelectorAll("button").forEach((button) => button.classList.toggle("is-active", button.dataset.invocationId === record.id));
}

function renderInvocationCatalog() {
  const category = byId("invocation-category").value;
  const query = byId("invocation-query").value.trim().toLowerCase();
  const records = state.invocationRecords.filter((record) => (!category || record.category === category) && (!query || [record.label, record.summary, record.core, record.category, ...(record.required_inputs || []), ...(record.optional_inputs || [])].join(" ").toLowerCase().includes(query)));
  const list = byId("invocation-list"); list.replaceChildren();
  if (!records.length) {
    const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No curated invocation matches this filter."; list.append(empty);
    return;
  }
  records.forEach((record) => {
    const button = document.createElement("button"); button.type = "button"; button.dataset.invocationId = record.id; button.className = "invocation-item";
    const title = document.createElement("strong"); title.textContent = record.label;
    const meta = document.createElement("small"); meta.textContent = `${record.category} · ${record.core}`;
    const summary = document.createElement("span"); summary.textContent = record.summary;
    button.append(title, meta, summary); button.addEventListener("click", () => renderInvocationDetail(record)); list.append(button);
  });
  const selected = records.find((record) => record.id === state.selectedInvocation?.id) || records[0];
  renderInvocationDetail(selected);
}

async function loadInvocationCatalog() {
  const status = byId("invocation-catalog-status"); status.textContent = "Loading the curated read-only map…";
  try {
    const envelope = await callSoul("invocations.list"); const data = dataOf(envelope);
    state.invocationRecords = data.records || []; state.invocationCategories = data.categories || [];
    byId("invocation-count").textContent = String(data.count || 0);
    const select = byId("invocation-category"); const current = select.value; select.replaceChildren();
    const all = document.createElement("option"); all.value = ""; all.textContent = "All categories"; select.append(all);
    state.invocationCategories.forEach((category) => { const option = document.createElement("option"); option.value = category; option.textContent = category; select.append(option); });
    if (state.invocationCategories.includes(current)) select.value = current;
    renderInvocationCatalog();
    status.textContent = `${data.count || 0} invocations loaded. Inspection performed no mutation.`;
  } catch (error) {
    status.textContent = error.message || "Invocation Guide failed safely.";
  }
}

function openInvocationCatalog() {
  state.invocationOpener = document.activeElement;
  byId("invocation-catalog").showModal();
  loadInvocationCatalog();
}

function closeInvocationCatalog() {
  byId("invocation-catalog").close();
  if (state.invocationOpener?.focus) state.invocationOpener.focus();
}

function requestId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") return `dash-${globalThis.crypto.randomUUID()}`;
  return `dash-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
}

async function callSoul(operation, parameters = {}, context = {}, requestOptions = {}) {
  const response = await fetch("/api/v1/call", {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf },
    body: JSON.stringify({ schema_version: "soul.application.v1", request_id: requestId(), operation, parameters, context: { interface: "dashboard", ...context } }),
    signal: requestOptions.signal,
    cache: "no-store"
  });
  const envelope = await response.json();
  if (response.status === 401 || envelope.error?.code === "password_change_required") { window.location.reload(); throw new Error("Dashboard session expired"); }
  if (response.status === 403 && envelope.error?.code === "csrf") { window.location.reload(); throw new Error("Dashboard security token refreshed"); }
  if (!response.ok) throw new Error(envelope.error?.reason || "Dashboard transport failed");
  return envelope;
}

async function callNdjson(endpoint, operation, parameters = {}, context = {}, onProgress = () => {}, requestOptions = {}) {
  if (endpoint === "/api/v1/music-stream" && ["music.generation.execute", "music.candidates.revision.execute"].includes(operation)) endpoint = "/api/v1/music-job-stream";
  const response = await fetch(endpoint, {
    method: "POST", credentials: "same-origin",
    headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf },
    body: JSON.stringify({ schema_version: "soul.application.v1", request_id: requestOptions.requestId || requestId(), operation, parameters, context: { interface: "dashboard", ...context } }),
    cache: "no-store"
  });
  if (!response.ok || !response.body) {
    const failure = await response.json().catch(() => ({}));
    if (response.status === 401 || failure.error?.code === "password_change_required") { window.location.reload(); throw new Error("Dashboard session expired"); }
    if (response.status === 403 && failure.error?.code === "csrf") { window.location.reload(); throw new Error("Dashboard security token refreshed; preview the exact action again"); }
    throw new Error(failure.error?.reason || "Chat stream failed safely");
  }
  const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = ""; let finalEnvelope = null;
  while (true) {
    const { value, done } = await reader.read(); buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
    const lines = buffer.split("\n"); buffer = lines.pop() || "";
    lines.filter(Boolean).forEach((line) => { const event = JSON.parse(line); if (event.record?.job_id) state.musicJobId = event.record.job_id; if (event.type === "progress") onProgress(event.event || {}); if (event.type === "result") finalEnvelope = event.envelope; });
    if (done) break;
  }
  if (buffer.trim()) { const event = JSON.parse(buffer); if (event.record?.job_id) state.musicJobId = event.record.job_id; if (event.type === "result") finalEnvelope = event.envelope; }
  if (!finalEnvelope) throw new Error("Foreground stream ended without a terminal result");
  return finalEnvelope;
}

async function followMusicJob(jobId, onProgress = () => {}) {
  const response = await fetch("/api/v1/music-job-follow", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf }, body: JSON.stringify({ job_id: jobId }), cache: "no-store" });
  if (!response.ok || !response.body) { const failure = await response.json().catch(() => ({})); throw new Error(failure.error?.reason || "Music job follow failed safely"); }
  const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = ""; let finalEnvelope = null;
  while (true) { const { value, done } = await reader.read(); buffer += decoder.decode(value || new Uint8Array(), { stream: !done }); const lines = buffer.split("\n"); buffer = lines.pop() || ""; lines.filter(Boolean).forEach((line) => { const event = JSON.parse(line); if (event.type === "progress") onProgress(event.event || {}); if (event.type === "result") finalEnvelope = event.envelope; }); if (done) break; }
  if (buffer.trim()) { const event = JSON.parse(buffer); if (event.type === "result") finalEnvelope = event.envelope; }
  if (!finalEnvelope) throw new Error("Music job follow ended without a terminal result");
  return finalEnvelope;
}

async function activeMusicJobs(projectId) {
  const response = await fetch("/api/v1/music-job-status", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf }, body: JSON.stringify({ project_id: projectId }), cache: "no-store" });
  const result = await response.json(); if (!response.ok) throw new Error(result.error?.reason || "Music job status failed safely"); return result.jobs || [];
}

const callSoulStream = (operation, parameters = {}, context = {}, onProgress = () => {}, requestOptions = {}) => callNdjson("/api/v1/chat-stream", operation, parameters, context, onProgress, requestOptions);

async function callPictureStream(payload, onProgress = () => {}) {
  const response = await fetch("/api/v1/perception/picture-stream", {
    method: "POST", credentials: "same-origin",
    headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf },
    body: JSON.stringify(payload), cache: "no-store"
  });
  if (!response.ok || !response.body) {
    const failure = await response.json().catch(() => ({}));
    if (response.status === 401 || failure.error?.code === "password_change_required") window.location.reload();
    if (response.status === 403 && failure.error?.code === "csrf") window.location.reload();
    throw new Error(failure.error?.reason || "Picture understanding failed safely");
  }
  const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = ""; let result = null;
  while (true) {
    const { value, done } = await reader.read(); buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
    const lines = buffer.split("\n"); buffer = lines.pop() || "";
    lines.filter(Boolean).forEach((line) => { const event = JSON.parse(line); if (event.type === "progress") onProgress(event.event || {}); if (event.type === "result") result = event.result; });
    if (done) break;
  }
  if (buffer.trim()) { const event = JSON.parse(buffer); if (event.type === "result") result = event.result; }
  if (!result) throw new Error("Picture stream ended without a terminal result");
  return result;
}

async function callScreenCapture(mode) {
  const response = await fetch("/api/v1/perception/screen-capture", {
    method: "POST", credentials: "same-origin",
    headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf },
    body: JSON.stringify({ mode }), cache: "no-store"
  });
  const result = await response.json().catch(() => ({}));
  if (response.status === 401 || result.error?.code === "password_change_required") { window.location.reload(); throw new Error("Dashboard session expired"); }
  if (response.status === 403 && result.error?.code === "csrf") { window.location.reload(); throw new Error("Dashboard security token refreshed"); }
  if (!response.ok || result.lifecycle_state !== "complete") throw new Error(result.reason || result.error?.reason || "Screen capture stopped safely");
  return result;
}

async function authRequest(path, body) {
  const options = { credentials: "same-origin", headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf } };
  if (body !== undefined) { options.method = "POST"; options.body = JSON.stringify(body); }
  const response = await fetch(path, options);
  const envelope = await response.json();
  if (response.status === 403 && envelope.error?.code === "csrf") { window.location.reload(); throw new Error("Dashboard security token refreshed"); }
  if (!response.ok) throw new Error(envelope.error?.reason || "Authentication failed safely");
  return envelope;
}

function setDashboardLocked(locked) {
  document.body.classList.toggle("auth-locked", locked);
  const gate = byId("auth-gate"); gate.hidden = !locked;
  [document.querySelector(".app-header"), document.querySelector("main"), byId("review-center"), byId("clear-dialog"), byId("model-runtime-dialog"), byId("screen-capture-dialog")].forEach((element) => { if (element) element.inert = locked; });
  if (!locked) { byId("logout-button").hidden = false; byId("auth-status").textContent = ""; }
}

function showPasswordChange(required) {
  byId("login-form").hidden = required;
  byId("password-change-form").hidden = !required;
  byId("auth-status").textContent = required ? "Bootstrap credential accepted. Set a private password to continue." : "";
  if (required) byId("current-password").focus(); else byId("auth-password").focus();
}

async function initializeAuthentication() {
  setDashboardLocked(true);
  try {
    const session = await authRequest("/auth/v1/session");
    if (!session.authenticated) { showPasswordChange(false); return; }
    if (session.password_change_required) { showPasswordChange(true); return; }
    state.authenticated = true; setDashboardLocked(false); await bootstrap();
  } catch (error) { byId("auth-status").textContent = error.message; showPasswordChange(false); }
}

async function login(event) {
  event.preventDefault(); const button = byId("login-button"); button.disabled = true; byId("auth-status").textContent = "Verifying local administrator…";
  try {
    const session = await authRequest("/auth/v1/login", { username: byId("auth-username").value, password: byId("auth-password").value });
    byId("auth-password").value = "";
    if (session.password_change_required) { showPasswordChange(true); return; }
    state.authenticated = true; setDashboardLocked(false); await bootstrap();
  } catch (error) { byId("auth-password").select(); byId("auth-status").textContent = error.message; }
  finally { button.disabled = false; }
}

async function changePassword(event) {
  event.preventDefault(); const button = byId("change-password-button"); button.disabled = true; byId("auth-status").textContent = "Replacing bootstrap credential…";
  try {
    const session = await authRequest("/auth/v1/change-password", { current_password: byId("current-password").value, new_password: byId("new-password").value, confirmation: byId("confirm-password").value });
    ["current-password", "new-password", "confirm-password"].forEach((id) => { byId(id).value = ""; });
    state.authenticated = session.authenticated; setDashboardLocked(false); await bootstrap();
  } catch (error) { byId("auth-status").textContent = error.message; }
  finally { button.disabled = false; }
}

async function logout() {
  if (state.voiceRecorder) cancelVoiceRecording("Voice capture canceled at logout.");
  stopVoicePlayback();
  byId("logout-button").disabled = true;
  try { await authRequest("/auth/v1/logout", {}); } finally { window.location.reload(); }
}

function announce(message) { byId("live-status").textContent = message; }
function dataOf(envelope) { return envelope.data || {}; }
function prefillApprovalGate(inputOrId, buttonOrId, phrase, enabled = true) {
  const input = typeof inputOrId === "string" ? byId(inputOrId) : inputOrId;
  const button = typeof buttonOrId === "string" ? byId(buttonOrId) : buttonOrId;
  const exact = String(phrase || "");
  input.value = enabled ? exact : "";
  input.readOnly = enabled;
  input.dataset.approvalMode = enabled ? "click" : "typed";
  const label = input.id ? document.querySelector(`label[for="${input.id}"]`) : null;
  const labelText = label && Array.from(label.childNodes).find((node) => node.nodeType === Node.TEXT_NODE);
  if (enabled && labelText) labelText.textContent = "Approval phrase ";
  button.disabled = !enabled || exact.length === 0;
}
function lifecycle(envelope) {
  const value = envelope.lifecycle_state || "failed";
  byId("lifecycle-state").textContent = value.replaceAll("_", " ");
  document.querySelector(".state-ribbon").dataset.lifecycle = value;
  document.querySelector(".conversation").dataset.lifecycle = value;
  byId("mutation-state").textContent = `mutation ${envelope.meta?.mutation || "none"}`;
  return value;
}

function requireLifecycle(envelope, accepted, fallback) {
  const value = lifecycle(envelope);
  if (!accepted.includes(value)) throw new Error(envelope.errors?.[0]?.message || fallback);
  return value;
}

function createGenerationProgress() {
  const progress = document.createElement("div"); progress.className = "generation-progress"; progress.hidden = true; progress.setAttribute("role", "status"); progress.setAttribute("aria-live", "polite");
  const signal = document.createElement("i"); signal.setAttribute("aria-hidden", "true");
  const stage = document.createElement("strong"); stage.dataset.generationStage = ""; stage.textContent = "Preparing";
  const message = document.createElement("span"); message.dataset.generationMessage = ""; message.textContent = "Waiting for the local lane.";
  progress.append(signal, stage, message); return progress;
}

function showGenerationProgress(progress, event = {}) {
  if (!progress) return;
  progress.hidden = false;
  const stage = progress.querySelector("[data-generation-stage]"); const message = progress.querySelector("[data-generation-message]");
  if (stage) stage.textContent = String(event.stage || "working").replaceAll("_", " ");
  const line = String(event.message || "").trim().split("\n").filter(Boolean).pop();
  if (message) message.textContent = (line || "Bounded local generation remains in progress.").slice(0, 240);
}

function hideGenerationProgress(progress) { if (progress) progress.hidden = true; }

function setSoulActivity(activityState, summary) {
  const presence = byId("soul-presence"); if (!presence) return;
  presence.dataset.state = activityState || "idle";
  const titles = { idle: "Soul is listening.", received: "Transmission received.", context: "Reading the thread.", planning: "Tracing a path.", inspecting: "Inspecting local evidence.", researching: "Following public signals.", synthesizing: "Shaping a response.", speaking: "Soul is speaking.", drafting: "Preparing an artifact.", reviewing: "Reviewing the result.", finalizing: "Sealing continuity.", complete: "Soul is present.", failed: "The path closed safely." };
  byId("soul-presence-title").textContent = titles[activityState] || "Soul is working.";
  byId("soul-activity-summary").textContent = summary || "Foreground work remains bounded to this request.";
}

function chatWorkActive() { return state.localChatRequests.size > 0 || state.chatProgress.size > 0; }

function setBusy(busy, message = "") {
  state.busy = Boolean(busy || chatWorkActive());
  byId("send-message").disabled = state.busy || state.voiceTranscribing || Boolean(state.voiceRecorder) || !state.activeChat;
  byId("message-input").disabled = !state.activeChat;
  byId("attach-picture").disabled = state.busy || state.voiceTranscribing || Boolean(state.voiceRecorder) || !state.activeChat;
  byId("capture-screen").disabled = state.busy || state.screenCapturing || state.voiceTranscribing || Boolean(state.voiceRecorder) || !state.activeChat;
  byId("send-message").querySelector("span").textContent = state.busy ? "Working" : "Send";
  byId("composer-hint").textContent = state.busy ? "Soul is working · you may draft, but ordinary Enter will not interrupt" : (state.activeChat ? "Ready · local continuity enabled" : "No conversation selected");
  updateVoiceControl();
  if (message) announce(message);
}

function updateVoiceControl() {
  const button = byId("record-voice"); if (!button) return;
  const recording = Boolean(state.voiceRecorder);
  button.disabled = !recording && (!state.activeChat || state.busy || state.voiceTranscribing || !state.authenticated);
  button.setAttribute("aria-pressed", String(recording));
  button.setAttribute("aria-label", recording ? "Stop push-to-talk recording" : "Start push-to-talk recording");
  button.querySelector("span:last-child").textContent = recording ? "Stop" : (state.voiceTranscribing ? "Hearing" : "Speak");
}

async function refreshVoicePresence() {
  const button = byId("voice-presence-launch"); if (!button || !state.authenticated) return;
  try {
    const response = await fetch("/api/v1/voice/presence/status", { credentials: "same-origin", cache: "no-store" });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error?.reason || "Voice Presence status unavailable");
    const running = result.data?.running === true;
    button.dataset.running = String(running);
    button.querySelector("span").textContent = running ? "Voice Listening" : "Voice Presence";
    button.title = running ? "Soul Voice Presence is open on the local desktop" : "Open the visible local Hey Soul window";
  } catch (_error) {
    button.dataset.running = "false";
    button.querySelector("span").textContent = "Voice Unavailable";
  }
}

async function launchVoicePresence() {
  const button = byId("voice-presence-launch"); button.disabled = true;
  try {
    const response = await fetch("/api/v1/voice/presence/launch", {
      method: "POST", credentials: "same-origin", cache: "no-store",
      headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf },
      body: JSON.stringify({ action: "launch" })
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.message || result.error?.reason || "Voice Presence did not open");
    announce(result.message || "Voice Presence opened on the local desktop");
    await refreshVoicePresence();
  } catch (error) { showError(error); }
  finally { button.disabled = false; }
}

function tabFromLocation() { return Object.entries(TAB_LOCATIONS).find(([, hash]) => hash === window.location.hash)?.[0] || null; }

function switchTab(name, { updateLocation = true } = {}) {
  if (!Object.hasOwn(TAB_LOCATIONS, name)) name = "chat";
  const chat = name === "chat";
  const timeline = name === "timeline";
  if (!chat && state.voiceRecorder) cancelVoiceRecording("Voice capture stopped because Chat was closed.");
  if (!chat) stopVoicePlayback();
  const studio = name === "studio";
  const improvement = name === "improvement";
  const augmentation = name === "augmentation";
  const music = name === "music";
  const visual = name === "visual";
  const maintenance = name === "maintenance";
  const backup = name === "backup";
  const selfImprovement = studio || improvement || augmentation;
  const creative = music || visual;
  const administration = timeline || maintenance || backup;
  byId("chat-panel").hidden = !chat;
  byId("timeline-panel").hidden = !timeline;
  byId("studio-panel").hidden = !studio;
  byId("improvement-panel").hidden = !improvement;
  byId("augmentation-panel").hidden = !augmentation;
  byId("music-panel").hidden = !music;
  byId("visual-panel").hidden = !visual;
  byId("maintenance-panel").hidden = !maintenance;
  byId("backup-panel").hidden = !backup;
  byId("chat-tab").classList.toggle("is-active", chat);
  byId("timeline-tab").classList.toggle("is-active", timeline);
  byId("self-improvement-tab").classList.toggle("is-active", selfImprovement);
  byId("studio-tab").classList.toggle("is-active", studio);
  byId("improvement-tab").classList.toggle("is-active", improvement);
  byId("augmentation-tab").classList.toggle("is-active", augmentation);
  byId("creative-tab").classList.toggle("is-active", creative);
  byId("music-tab").classList.toggle("is-active", music);
  byId("visual-tab").classList.toggle("is-active", visual);
  byId("administration-tab").classList.toggle("is-active", administration);
  byId("maintenance-tab").classList.toggle("is-active", maintenance);
  byId("backup-tab").classList.toggle("is-active", backup);
  byId("chat-tab").setAttribute("aria-selected", String(chat));
  byId("timeline-tab").setAttribute("aria-current", timeline ? "page" : "false");
  byId("self-improvement-tab").setAttribute("aria-selected", String(selfImprovement));
  byId("studio-tab").classList.toggle("is-active", studio);
  byId("improvement-tab").classList.toggle("is-active", improvement);
  byId("augmentation-tab").classList.toggle("is-active", augmentation);
  byId("studio-tab").setAttribute("aria-current", studio ? "page" : "false");
  byId("improvement-tab").setAttribute("aria-current", improvement ? "page" : "false");
  byId("augmentation-tab").setAttribute("aria-current", augmentation ? "page" : "false");
  byId("creative-tab").setAttribute("aria-selected", String(creative));
  byId("music-tab").setAttribute("aria-current", music ? "page" : "false");
  byId("visual-tab").setAttribute("aria-current", visual ? "page" : "false");
  byId("administration-tab").setAttribute("aria-selected", String(administration));
  byId("maintenance-tab").setAttribute("aria-current", maintenance ? "page" : "false");
  byId("backup-tab").setAttribute("aria-current", backup ? "page" : "false");
  setSelfImprovementMenu(false);
  setCreativeMenu(false);
  setAdministrationMenu(false);
  if (updateLocation && window.location.hash !== TAB_LOCATIONS[name]) window.history.replaceState(null, "", TAB_LOCATIONS[name]);
  if (studio && state.authenticated && !state.studioLoaded) loadSkillStudio();
  if (improvement && state.authenticated && !state.improvementLoaded) loadSelfImprovement();
  if (augmentation && state.authenticated && !state.augmentationLoaded) loadSelfAugmentation();
  if (music && state.authenticated && !state.musicLoaded) loadMusicStudio();
  if (visual && state.authenticated && !state.visualLoaded) loadVisualStudio();
  if (timeline && state.authenticated && !state.timelineLoaded) loadProjectTimeline();
  if (maintenance && state.authenticated) {
    if (!state.maintenanceFleetLoaded) loadMaintenanceFleetSnapshot();
    loadMaintenanceDiscovery();
    loadMaintenanceReceipts();
    loadMaintenanceRebootStatus();
  }
  if (backup && state.authenticated && !state.backupLoaded) loadBackupAdministration();
}

function setSelfImprovementMenu(open) {
  byId("self-improvement-menu").hidden = !open;
  byId("self-improvement-tab").setAttribute("aria-expanded", String(open));
  byId("self-improvement-navigation").classList.toggle("is-open", open);
}

function setCreativeMenu(open) {
  byId("creative-menu").hidden = !open;
  byId("creative-tab").setAttribute("aria-expanded", String(open));
  byId("creative-navigation").classList.toggle("is-open", open);
}

function setAdministrationMenu(open) {
  byId("administration-menu").hidden = !open;
  byId("administration-tab").setAttribute("aria-expanded", String(open));
  byId("administration-navigation").classList.toggle("is-open", open);
}

const TIMELINE_HORIZONS = ["now", "next", "later", "backlog"];
const TIMELINE_STATUS_LABELS = Object.freeze({
  planned: "Planned", in_progress: "In progress", blocked: "Blocked",
  needs_review: "Needs review", validated: "Validated", done: "Done", deferred: "Deferred"
});

function timelineItems() { return Array.isArray(state.projectTracker?.items) ? state.projectTracker.items : []; }

function buildTimelineCard(item) {
  const card = document.createElement("button"); card.type = "button"; card.className = "timeline-item"; card.dataset.status = item.status;
  const status = document.createElement("span"); status.textContent = `${TIMELINE_STATUS_LABELS[item.status] || item.status} · ${item.priority} · ${item.area}`;
  const title = document.createElement("strong"); title.textContent = item.title;
  const summary = document.createElement("small"); summary.textContent = item.summary;
  card.append(status, title, summary); card.addEventListener("click", () => openTimelineEditor(item));
  return card;
}

function renderProjectTimeline() {
  const items = timelineItems();
  byId("timeline-total").textContent = String(items.length);
  byId("timeline-active").textContent = String(items.filter((item) => item.status === "in_progress").length);
  byId("timeline-review").textContent = String(items.filter((item) => item.status === "needs_review").length);
  byId("timeline-blocked").textContent = String(items.filter((item) => item.status === "blocked").length);
  byId("timeline-done").textContent = String(items.filter((item) => ["validated", "done"].includes(item.status)).length);
  const filter = byId("timeline-status-filter").value;
  const inventoryMode = ["implemented", "done", "validated"].includes(filter);
  byId("timeline-board").hidden = inventoryMode;
  byId("timeline-inventory").hidden = !inventoryMode;
  const inventoryList = byId("timeline-implemented-items"); inventoryList.replaceChildren();
  if (inventoryMode) {
    const implemented = items
      .filter((item) => ["validated", "done"].includes(item.status) && (filter === "implemented" || item.status === filter))
      .sort((left, right) => left.area.localeCompare(right.area) || left.title.localeCompare(right.title));
    if (!implemented.length) {
      const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No completed or validated feature records."; inventoryList.append(empty);
    } else {
      implemented.forEach((item) => inventoryList.append(buildTimelineCard(item)));
    }
  }
  TIMELINE_HORIZONS.forEach((horizon) => {
    const column = byId(`timeline-${horizon}`); column.replaceChildren();
    const visible = items
      .filter((item) => item.horizon === horizon && (
        filter === "all" ||
        (filter === "active" && !["validated", "done", "deferred"].includes(item.status)) ||
        (filter === "implemented" && ["validated", "done"].includes(item.status)) ||
        item.status === filter
      ))
      .sort((left, right) => (({ high: 0, medium: 1, low: 2 })[left.priority] - ({ high: 0, medium: 1, low: 2 })[right.priority]) || left.title.localeCompare(right.title));
    if (!visible.length) {
      const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = filter === "all" ? "No entries in this horizon." : "No matching entries."; column.append(empty); return;
    }
    visible.forEach((item) => column.append(buildTimelineCard(item)));
  });
}

async function loadProjectTimeline({ announceLoad = false } = {}) {
  byId("timeline-status").textContent = "Reading owner-local project state…";
  try {
    const envelope = await callSoul("project_tracker.snapshot");
    requireLifecycle(envelope, ["complete"], "Project timeline could not be loaded");
    state.projectTracker = dataOf(envelope); state.timelineLoaded = true; renderProjectTimeline();
    const message = `Timeline ready · ${timelineItems().length} tracked items · revision ${state.projectTracker.revision}`;
    byId("timeline-status").textContent = message; if (announceLoad) announce(message);
  } catch (error) { state.timelineLoaded = false; byId("timeline-status").textContent = error.message; }
}

function openTimelineEditor(item = null) {
  state.selectedTimelineItem = item;
  byId("timeline-editor").hidden = false; byId("timeline-board").parentElement.classList.add("has-editor");
  byId("timeline-editor-title").textContent = item ? "Feature record" : "New timeline item";
  byId("timeline-item-id").value = item?.item_id || "";
  byId("timeline-item-revision").value = item?.revision || "";
  byId("timeline-item-title").value = item?.title || "";
  byId("timeline-item-area").value = item?.area || "";
  byId("timeline-item-horizon").value = item?.horizon || "next";
  byId("timeline-item-status").value = item?.status || "planned";
  byId("timeline-item-priority").value = item?.priority || "medium";
  byId("timeline-item-summary").value = item?.summary || "";
  byId("timeline-item-implementation").value = item?.implementation || "";
  byId("timeline-item-technologies").value = item?.technologies || "";
  byId("timeline-item-interfaces").value = item?.interfaces || "";
  byId("timeline-item-commands").value = item?.commands || "";
  byId("timeline-item-references").value = item?.references || "";
  byId("timeline-item-acceptance").value = item?.acceptance || "";
  byId("timeline-item-notes").value = item?.notes || "";
  byId("timeline-item-source").value = item?.source || "Operator";
  byId("timeline-editor-status").textContent = item ? `Editing ${item.item_id} · revision ${item.revision}` : "Create one explicit ledger entry.";
  byId("timeline-item-title").focus();
}

function closeTimelineEditor() {
  state.selectedTimelineItem = null; byId("timeline-editor").hidden = true;
  byId("timeline-board").parentElement.classList.remove("has-editor"); byId("timeline-editor-status").textContent = "";
}

function timelineFormItem() {
  return {
    title: byId("timeline-item-title").value, area: byId("timeline-item-area").value,
    horizon: byId("timeline-item-horizon").value, status: byId("timeline-item-status").value,
    priority: byId("timeline-item-priority").value, summary: byId("timeline-item-summary").value,
    implementation: byId("timeline-item-implementation").value,
    technologies: byId("timeline-item-technologies").value,
    interfaces: byId("timeline-item-interfaces").value,
    commands: byId("timeline-item-commands").value,
    references: byId("timeline-item-references").value,
    acceptance: byId("timeline-item-acceptance").value, notes: byId("timeline-item-notes").value,
    source: byId("timeline-item-source").value
  };
}

async function saveTimelineItem(event) {
  event.preventDefault(); const button = byId("save-timeline-item"); button.disabled = true;
  byId("timeline-editor-status").textContent = "Writing one bounded ledger revision…";
  try {
    const itemId = byId("timeline-item-id").value;
    const parameters = itemId
      ? { item_id: itemId, item: timelineFormItem(), expected_revision: Number(byId("timeline-item-revision").value) }
      : { item: timelineFormItem() };
    const envelope = await callSoul(itemId ? "project_tracker.items.update" : "project_tracker.items.create", parameters);
    requireLifecycle(envelope, ["complete"], envelope.errors?.[0]?.message || "Timeline item was not saved");
    state.projectTracker = dataOf(envelope).tracker; renderProjectTimeline(); closeTimelineEditor();
    const message = itemId ? "Timeline item updated." : "Timeline item created.";
    byId("timeline-status").textContent = `${message} Revision ${state.projectTracker.revision}.`; announce(message);
  } catch (error) { byId("timeline-editor-status").textContent = error.message; }
  finally { button.disabled = false; }
}

function replaceChatProgress(records, chatId = null) {
  if (chatId) state.chatProgress.delete(chatId);
  else state.chatProgress.clear();
  (records || []).forEach((record) => {
    if (record.operation === "chats.send" && /^chat_[A-Za-z0-9_.-]+$/.test(record.identity || "") && record.status === "reserved") {
      state.chatProgress.set(record.identity, record);
    }
  });
}

function recordChatProgress(chatId, requestIdValue, progress = {}) {
  const summary = String(progress.summary || "Bounded foreground work remains active.").trim().slice(0, 240);
  const record = {
    request_id: requestIdValue, operation: "chats.send", identity: chatId, status: "reserved",
    progress_state: String(progress.state || "planning"), progress_summary: summary
  };
  state.chatProgress.set(chatId, record);
  if (state.activeChat?.id === chatId) {
    if (record.progress_state === "received") markPendingMessageAccepted(requestIdValue);
    renderChatProgress(record);
    setSoulActivity(record.progress_state, summary);
  }
  renderChatList();
  setBusy(false);
}

function renderChatList() {
  const list = byId("chat-list");
  list.replaceChildren();
  if (!state.chats.length) {
    const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No conversations yet. Create one to begin."; list.append(empty); return;
  }
  state.chats.forEach((chat) => {
    const button = document.createElement("button"); button.type = "button"; button.className = "chat-item";
    if (state.activeChat?.id === chat.id) button.classList.add("is-active");
    const sigil = document.createElement("span"); sigil.className = "sigil"; sigil.textContent = "◆";
    const copy = document.createElement("span");
    const title = document.createElement("strong"); title.textContent = chat.title || "Untitled conversation";
    const progress = state.chatProgress.get(chat.id);
    if (progress) button.classList.add("is-working");
    const meta = document.createElement("small"); meta.textContent = progress ? `${String(progress.progress_state || "working").replaceAll("_", " ")} · active` : (chat.updated_at ? `updated ${formatTime(chat.updated_at)}` : chat.id);
    copy.append(title, meta); button.append(sigil, copy);
    if (chat.pinned) { const pin = document.createElement("span"); pin.className = "pin"; pin.textContent = "PIN"; button.append(pin); }
    button.addEventListener("click", () => selectChat(chat)); list.append(button);
  });
}

function formatTime(value) {
  const date = new Date(value); return Number.isNaN(date.valueOf()) ? "recently" : date.toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

async function loadChats(selectFirst = true) {
  const [envelope, progress] = await Promise.all([
    callSoul("chats.list", { limit: 50 }),
    callSoul("chats.progress", { limit: 20 })
  ]);
  lifecycle(envelope); replaceChatProgress(dataOf(progress).records || []);
  state.chats = dataOf(envelope).records || []; renderChatList();
  if (selectFirst && !state.activeChat && state.chats.length) await selectChat(state.chats[0]);
  if (!state.chats.length) resetConversationView();
}

function resetConversationView() {
  if (state.voiceRecorder) cancelVoiceRecording("Voice capture stopped because the conversation closed.");
  clearPictureAttachment();
  state.activeChat = null;
  byId("active-chat-kicker").textContent = "No active thread";
  byId("active-chat-title").textContent = "Open a conversation";
  byId("pin-chat").disabled = true;
  byId("pin-chat").textContent = "Pin";
  byId("message-input").disabled = true;
  byId("message-input").placeholder = "Create a conversation to begin…";
  byId("send-message").disabled = true;
  updateVoiceControl();
  byId("composer-hint").textContent = "No conversation selected";
  renderMessages([], true); renderWorkspace([]); renderInbox({ records: [] });
}

async function selectChat(chat) {
  stopVoicePlayback();
  if (state.activeChat?.id && state.activeChat.id !== chat.id) clearPictureAttachment();
  state.activeChat = chat; renderChatList();
  byId("active-chat-kicker").textContent = chat.id;
  byId("active-chat-title").textContent = chat.title || "Untitled conversation";
  byId("pin-chat").disabled = false; byId("pin-chat").textContent = chat.pinned ? "Unpin" : "Pin";
  byId("composer-hint").textContent = "Local provider request · foreground only";
  byId("message-input").placeholder = "Write a message to Soul…"; setBusy(true, "Loading conversation");
  try {
    const [messages, workspace, inbox, progress] = await Promise.all([
      callSoul("chats.messages", { chat_id: chat.id, limit: 200 }, { current_chat_id: chat.id }),
      callSoul("workspace.chat", { chat_id: chat.id, limit: 50 }, { current_chat_id: chat.id }),
      callSoul("inbox.list", { chat_id: chat.id, limit: 50 }, { current_chat_id: chat.id }),
      callSoul("chats.progress", { chat_id: chat.id, limit: 1 }, { current_chat_id: chat.id })
    ]);
    lifecycle(messages); replaceChatProgress(dataOf(progress).records || [], chat.id); renderMessages(dataOf(messages).records || []);
    renderChatProgress(state.chatProgress.get(chat.id)); renderWorkspace(dataOf(workspace).records || []); renderInbox(dataOf(inbox)); renderChatList();
    announce(`Opened ${chat.title || "conversation"}`);
  } catch (error) { showError(error); } finally { setBusy(false); }
}

function messageArticle(record, { pending = false, working = false } = {}) {
  const article = document.createElement("article"); const role = record.role === "user" ? "user" : "assistant"; article.className = `message message--${role}`;
  if (pending) article.classList.add("message--pending"); if (working) article.classList.add("message--working");
  const label = document.createElement("div"); label.className = "message-label"; label.textContent = role === "user" ? (pending ? "You · sending" : "You") : "Soul /";
  const body = document.createElement("div"); body.className = "message-body"; body.textContent = record.content || record.text || ""; article.append(label, body);
  if (role === "assistant" && !working) {
    const spoken = String(record.content || record.text || "").trim();
    if (spoken && spoken.length <= 2000 && !/^[\[{]/.test(spoken)) article.append(messageSpeakButton(spoken, speechContextForMessage(record)));
  }
  const runtime = record.metadata?.runtime || {};
  renderMessageAttachments(article, Array.isArray(runtime.attachments) ? runtime.attachments : []);
  if (runtime.perception) {
    const meta = document.createElement("p"); meta.className = "message-perception-meta";
    const dimensions = runtime.perception.width && runtime.perception.height ? `${runtime.perception.width}×${runtime.perception.height}` : null;
    meta.textContent = [runtime.perception.model, dimensions, runtime.perception.retained ? "retained locally" : "source discarded", runtime.perception.latency_ms ? `${(Number(runtime.perception.latency_ms) / 1000).toFixed(1)}s` : null].filter(Boolean).join(" · ");
    article.append(meta);
  }
  renderMessageActions(article, Array.isArray(runtime.actions) ? runtime.actions : []);
  return article;
}

function speechContextForMessage(record) {
  const orchestration = record?.metadata?.runtime?.orchestration || {};
  const toolIds = Array.isArray(orchestration.tool_ids) ? orchestration.tool_ids : [];
  return toolIds.includes("weather.report") ? "weather_report" : "general";
}

function messageSpeakButton(text, speechContext = "general") {
  const button = document.createElement("button"); button.type = "button"; button.className = "message-speak-button"; button.textContent = "Speak"; button.setAttribute("aria-pressed", "false");
  button.addEventListener("click", () => {
    if (state.voiceSynthesisButton === button) { stopVoicePlayback(); return; }
    synthesizeMessageSpeech(text, button, speechContext);
  });
  return button;
}

function stopVoicePlayback() {
  state.voiceSynthesisController?.abort();
  state.voiceSynthesisController = null;
  if (state.voicePlayback) { state.voicePlayback.pause(); state.voicePlayback.src = ""; }
  state.voicePlayback = null;
  if (state.voicePlaybackUrl) URL.revokeObjectURL(state.voicePlaybackUrl);
  state.voicePlaybackUrl = null;
  if (state.voiceSynthesisButton) {
    state.voiceSynthesisButton.disabled = false;
    state.voiceSynthesisButton.textContent = "Speak";
    state.voiceSynthesisButton.setAttribute("aria-pressed", "false");
  }
  state.voiceSynthesisButton = null;
  if (!state.busy && !state.voiceTranscribing && !state.voiceRecorder) setSoulActivity("idle", "Foreground work remains bounded to this request.");
}

async function synthesizeMessageSpeech(text, button, speechContext = "general") {
  stopVoicePlayback();
  const controller = new AbortController(); state.voiceSynthesisController = controller; state.voiceSynthesisButton = button;
  button.disabled = false; button.textContent = "Cancel"; button.setAttribute("aria-pressed", "true");
  setSoulActivity("speaking", "Preparing one bounded local voice response.");
  try {
    const expressive = state.voiceOutputQuality === "expressive";
    const response = await fetch(expressive ? "/api/v1/voice/synthesize-stream" : "/api/v1/voice/synthesize", {
      method: "POST", credentials: "same-origin", cache: "no-store", signal: controller.signal,
      headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf },
      body: JSON.stringify({ text, voice: state.voiceOutputProfile, quality: state.voiceOutputQuality, speech_context: speechContext })
    });
    if (!response.ok) {
      const failure = await response.json().catch(() => ({}));
      throw new Error(failure.error?.reason || "Speech synthesis failed safely");
    }
    let blob;
    if (expressive) {
      if (!response.body) throw new Error("Expressive voice stream was unavailable");
      const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = ""; let terminal = null;
      while (true) {
        const { value, done } = await reader.read(); buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
        const lines = buffer.split("\n"); buffer = lines.pop() || "";
        lines.filter(Boolean).forEach((line) => {
          const event = JSON.parse(line);
          if (event.type === "progress") {
            setSoulActivity("speaking", event.event?.message || "Expressive voice rendering is active.");
            button.textContent = "Cancel";
          }
          if (event.type === "result") terminal = event.result;
        });
        if (done) break;
      }
      if (buffer.trim()) { const event = JSON.parse(buffer); if (event.type === "result") terminal = event.result; }
      if (!terminal?.ok) throw new Error(terminal?.message || "Expressive speech stopped safely");
      const binary = atob(terminal.audio_base64); const bytes = new Uint8Array(binary.length);
      for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
      blob = new Blob([bytes], { type: terminal.content_type || "audio/wav" });
    } else {
      blob = await response.blob();
    }
    if (state.voiceSynthesisController !== controller) return;
    const url = URL.createObjectURL(blob); const audio = new Audio(url);
    state.voicePlaybackUrl = url; state.voicePlayback = audio; state.voiceSynthesisController = null;
    button.disabled = false; button.textContent = "Stop"; button.setAttribute("aria-pressed", "true");
    const finish = () => { if (state.voicePlayback === audio) stopVoicePlayback(); };
    audio.addEventListener("ended", finish, { once: true }); audio.addEventListener("error", finish, { once: true });
    await audio.play();
  } catch (error) {
    if (error.name !== "AbortError") announce(error.message);
    if (state.voiceSynthesisController === controller || state.voiceSynthesisButton === button) stopVoicePlayback();
  }
}

function safeLocalArtifactUrl(value, kind) {
  const text = String(value || "");
  const patterns = {
    audio: /^\/api\/v1\/music\/audio\/music_[a-f0-9]{16}\/candidate_[a-f0-9]{16}\/(?:mp3|flac)$/,
    image: /^(?:\/api\/v1\/visual\/image\/visual_project_[a-f0-9]{16}\/visual_candidate_[a-f0-9]{16}|\/api\/v1\/perception\/image\/chat_[A-Za-z0-9_.-]+\/[a-f0-9]{64}\.(?:png|jpg))$/,
    video: /^\/api\/v1\/music\/visual\/music_[a-f0-9]{16}\/candidate_[a-f0-9]{16}\/visual_[a-f0-9]{16}\/(?:loop|preview)$/
  };
  return patterns[kind]?.test(text) ? text : null;
}

function renderMessageAttachments(article, attachments) {
  if (!attachments.length) return;
  const region = document.createElement("div"); region.className = "message-attachments";
  attachments.forEach((attachment) => {
    const item = document.createElement("section"); item.className = "message-attachment";
    const title = document.createElement("strong"); title.textContent = attachment.title || "Creative candidate"; item.append(title);
    if (attachment.kind === "audio") {
      const source = safeLocalArtifactUrl(attachment.player_url, "audio"); const lossless = safeLocalArtifactUrl(attachment.lossless_url, "audio");
      if (source) { const player = document.createElement("audio"); player.controls = true; player.preload = "none"; player.src = source; item.append(player); }
      if (lossless) { const link = document.createElement("a"); link.href = lossless; link.textContent = "Open lossless FLAC"; link.target = "_blank"; link.rel = "noopener"; item.append(link); }
    } else if (attachment.kind === "image") {
      const source = safeLocalArtifactUrl(attachment.image_url, "image");
      if (source) { const picture = document.createElement("img"); picture.src = source; picture.alt = attachment.title || "Soul visual candidate"; picture.loading = "lazy"; item.append(picture); }
    } else if (attachment.kind === "video") {
      const source = safeLocalArtifactUrl(attachment.video_url, "video");
      if (source) { const player = document.createElement("video"); player.controls = true; player.preload = "none"; player.src = source; item.append(player); }
    }
    if (attachment.note) { const note = document.createElement("p"); note.textContent = attachment.note; item.append(note); }
    if (item.childElementCount > 1) region.append(item);
  });
  if (region.childElementCount) article.append(region);
}

function renderMessageActions(article, actions) {
  const safe = actions.filter((action) => {
    if (!/^[a-f0-9]{64}$/.test(action.expected_digest || "")) return false;
    if (action.operation === "chats.creative.execute") return /^creative_[a-f0-9]{16}$/.test(action.flow_id || "") && /^chat_[A-Za-z0-9_.-]+$/.test(action.chat_id || "");
    if (action.operation === "core.activate.execute") return ["daily", "amd-free", "music"].includes(action.core_id) && /^[A-Za-z0-9_.-]+$/.test(action.target_profile_id || "");
    return false;
  });
  if (!safe.length) return;
  const region = document.createElement("div"); region.className = "message-actions";
  safe.forEach((action) => {
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button gate-button--gold"; button.textContent = action.label || "Continue exact creative workflow";
    const status = document.createElement("small"); status.className = "message-action-status";
    button.addEventListener("click", async () => {
      button.disabled = true; status.textContent = action.operation === "core.activate.execute" ? "Core transfer accepted…" : "Creative workflow accepted…";
      try {
        if (action.operation === "core.activate.execute") {
          status.textContent = "Revalidating active work and Core state…";
          const envelope = await callSoul(action.operation, { core_id: action.core_id, target_profile_id: action.target_profile_id, confirmation: action.confirmation_phrase, expected_digest: action.expected_digest });
          lifecycle(envelope); status.textContent = envelope.errors?.[0]?.message || dataOf(envelope).reason || "Core activation complete.";
          if (envelope.lifecycle_state !== "complete") { button.disabled = false; return; }
          await refreshCores({ automatic: true }); await refreshModelRuntime({ automatic: true }); await refreshStatus({ automatic: true });
          return;
        }
        const envelope = await callNdjson("/api/v1/music-job-stream", action.operation, { chat_id: action.chat_id, flow_id: action.flow_id, action_id: action.action_id, confirmation: action.confirmation_phrase, expected_digest: action.expected_digest }, { current_chat_id: action.chat_id }, (event) => { status.textContent = event.message || "Bounded creative work in progress…"; });
        lifecycle(envelope); status.textContent = envelope.errors?.[0]?.message || dataOf(envelope).reason || "Creative workflow reached a review gate.";
        if (state.activeChat?.id === action.chat_id) await selectChat(state.activeChat);
        await refreshCores({ automatic: true }); await refreshModelRuntime({ automatic: true });
      } catch (error) { status.textContent = error.message || "Creative workflow failed safely."; button.disabled = false; }
    });
    region.append(button, status);
  });
  article.append(region);
}

function renderMessages(records, noChat = false) {
  const area = byId("messages"); area.replaceChildren();
  if (!records.length) { const empty = document.createElement("div"); empty.className = "empty-state"; const copy = document.createElement("div"); const eyebrow = document.createElement("p"); eyebrow.className = "eyebrow"; eyebrow.textContent = noChat ? "Active list clear" : "Fresh context"; const heading = document.createElement("h2"); heading.textContent = noChat ? "Create a conversation when you’re ready." : "This conversation is ready."; const note = document.createElement("p"); note.textContent = noChat ? "Archived transcripts remain stored locally and are not deleted." : "Your first message will use Soul’s configured provider and shared context boundary."; copy.append(eyebrow, heading, note); empty.append(copy); area.append(empty); return; }
  records.forEach((record) => area.append(messageArticle(record)));
  area.scrollTop = area.scrollHeight;
}

function appendPendingExchange(message, requestIdValue) {
  const area = byId("messages"); area.querySelector(".empty-state")?.remove(); area.append(messageArticle({ role: "user", content: message }, { pending: true }));
  const pending = area.lastElementChild; if (pending) pending.dataset.requestId = requestIdValue;
  const working = messageArticle({ role: "assistant", content: "Reading the transmission…" }, { working: true }); working.id = "soul-working-message"; area.append(working); area.scrollTop = area.scrollHeight;
}

function markPendingMessageAccepted(requestIdValue) {
  const pending = [...document.querySelectorAll(".message--pending")].find((item) => item.dataset.requestId === requestIdValue);
  if (!pending) return;
  pending.classList.remove("message--pending");
  const label = pending.querySelector(".message-label"); if (label) label.textContent = "You";
}

function renderChatProgress(record) {
  const existing = byId("soul-working-message");
  if (!record || record.status !== "reserved") { existing?.remove(); return; }
  const summary = String(record.progress_summary || "Bounded foreground work remains active.").trim().slice(0, 240);
  if (existing) {
    const body = existing.querySelector(".message-body"); if (body) body.textContent = summary;
    existing.dataset.requestId = record.request_id || ""; return;
  }
  const working = messageArticle({ role: "assistant", content: summary }, { working: true });
  working.id = "soul-working-message"; working.dataset.requestId = record.request_id || "";
  const area = byId("messages"); area.querySelector(".empty-state")?.remove(); area.append(working); area.scrollTop = area.scrollHeight;
}

function updateWorkingMessage(summary) { const body = byId("soul-working-message")?.querySelector(".message-body"); if (body) body.textContent = summary; }

function renderWorkspace(records) {
  byId("workspace-count").textContent = String(records.length); const list = byId("workspace-list"); list.replaceChildren();
  if (!records.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No artifact metadata is attached yet."; list.append(empty); return; }
  records.forEach((record) => { const item = document.createElement("div"); item.className = "artifact"; const title = document.createElement("strong"); title.textContent = record.title || record.artifact_id || "Artifact"; const meta = document.createElement("small"); meta.textContent = [record.kind, record.privacy, record.lifecycle, record.delivery_state, "metadata only"].filter(Boolean).join(" · "); item.append(title, meta); list.append(item); });
}

function renderInbox(data) {
  const records = data.records || []; byId("inbox-count").textContent = String(records.length);
  byId("inbox-summary").textContent = records.length ? `${records.length} bounded deliver${records.length === 1 ? "y" : "ies"} available.` : "No deliveries for this conversation.";
}

async function createChat() {
  setBusy(true, "Creating conversation");
  try { const envelope = await callSoul("chats.create"); lifecycle(envelope); const chat = dataOf(envelope).record; await loadChats(false); await selectChat(chat); } catch (error) { showError(error); } finally { setBusy(false); }
}

function musicProjectInput() {
  const vocalMode = byId("music-vocal-mode").value;
  return { title: byId("music-title").value, intent: byId("music-intent").value, target_duration_seconds: Number(byId("music-duration").value), vocal_mode: vocalMode, rights_status: byId("music-rights").value, caption: byId("music-caption").value, lyrics: vocalMode === "instrumental" ? "" : byId("music-lyrics").value, bpm: Number(byId("music-bpm").value), keyscale: byId("music-key").value, timesignature: byId("music-time").value, language: "en", seed: Number(byId("music-seed").value) };
}

function supportedMusicDuration(duration) {
  return Number.isInteger(duration) && ((duration >= 30 && duration <= 300) || duration === 600);
}

function syncMusicCompositionMode() {
  const lyrics = byId("music-lyrics"); const instrumental = byId("music-vocal-mode").value === "instrumental"; const locked = Boolean(state.selectedMusicProject);
  byId("music-caption-guidance").textContent = instrumental
    ? "Describe one coherent instrumental identity under 512 characters. Broad or second-based movement timing belongs here; BPM, key, and meter remain in their dedicated fields. Soul sends the runtime’s exact trained no-vocal token."
    : "Describe one coherent vocal identity under 512 characters. Put exact section timing in Lyrics and section markers; BPM, key, and meter remain in their dedicated fields.";
  byId("music-lyrics-label").textContent = instrumental ? "Lyrics unavailable in Instrumental mode" : "Lyrics and section markers";
  lyrics.placeholder = instrumental
    ? "Instrumental projects use the runtime’s exact no-vocal token. Put arrangement and movement timing in Sound and structure."
    : "[Intro]\n\n[Verse 1 - rhythmic male vocal]\nOne lyric line at a time\n\n[Instrumental]\n\n[Outro]";
  lyrics.required = !instrumental;
  if (locked) return;
  if (instrumental) {
    if (!lyrics.disabled && lyrics.value) lyrics.dataset.vocalDraft = lyrics.value;
    lyrics.value = "";
    lyrics.disabled = true;
  } else {
    lyrics.disabled = false;
    if (!lyrics.value && lyrics.dataset.vocalDraft) lyrics.value = lyrics.dataset.vocalDraft;
  }
}

async function loadMusicStudio() {
  state.musicLoaded = true;
  try {
    const envelope = await callSoul("music.projects.list", { limit: 100 }); lifecycle(envelope);
    state.musicProjects = dataOf(envelope).projects || []; renderMusicProjects(); await loadMusicReferences(); await refreshMusicReferenceStatus(); await refreshMusicResources();
    const first = state.musicProjects.find((project) => (project.release_state || "active") === state.musicProjectView);
    if (first) await selectMusicProject(first);
  } catch (error) { state.musicLoaded = false; byId("music-form-status").textContent = error.message; }
}

async function loadMusicReferences() {
  const envelope = await callSoul("music.references.list", { limit: 200 }); lifecycle(envelope);
  if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Reference library needs attention");
  state.musicReferences = dataOf(envelope); renderMusicReferences();
}

async function refreshMusicReferenceStatus() {
  try { const envelope = await callSoul("music.references.status"); const data = dataOf(envelope); const ready = data.available === true; byId("music-reference-tool-status").textContent = ready ? "Local reference tools ready · no resident process" : (data.blockers || []).join(" · ") || "Reference tools unavailable"; byId("preview-music-reference").disabled = !ready; }
  catch (error) { byId("music-reference-tool-status").textContent = error.message; byId("preview-music-reference").disabled = true; }
}

async function previewMusicReference() {
  state.musicReferencePreview = null; byId("music-reference-confirm").hidden = true; byId("music-reference-status").textContent = "Reading metadata only; no media is downloaded at this gate."; byId("preview-music-reference").disabled = true;
  try { const params = { url: byId("music-reference-url").value, rights_assertion: byId("music-reference-rights").value }; const envelope = await callSoul("music.references.analysis.preview", params); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Reference preview is unavailable"); state.musicReferencePreview = { ...data, ...params }; byId("music-reference-scope").textContent = JSON.stringify(data.preview_scope, null, 2); prefillApprovalGate("music-reference-confirmation", "analyze-music-reference", data.confirmation_phrase); byId("music-reference-confirm").hidden = false; byId("music-reference-status").textContent = `${data.metadata.title} · ${data.metadata.artists.join(", ")} · ${data.metadata.duration_seconds}s. Review the scope; clicking Analyze authorizes this foreground pass.`; }
  catch (error) { byId("music-reference-status").textContent = error.message; }
  finally { byId("preview-music-reference").disabled = false; }
}

async function analyzeMusicReference() {
  if (!state.musicReferencePreview || state.musicReferenceAnalyzing) return; state.musicReferenceAnalyzing = true; byId("analyze-music-reference").disabled = true; byId("preview-music-reference").disabled = true;
  const params = { url: state.musicReferencePreview.url, rights_assertion: state.musicReferencePreview.rights_assertion, confirmation: byId("music-reference-confirmation").value, expected_digest: state.musicReferencePreview.expected_digest };
  try { const envelope = await callNdjson("/api/v1/music-stream", "music.references.analysis.execute", params, {}, (event) => { const message = String(event.message || "").trim(); if (message) byId("music-reference-status").textContent = `${String(event.stage || "working").replaceAll("_", " ")}: ${message.slice(0, 240)}`; }); lifecycle(envelope); if (!dataOf(envelope).reference) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); byId("music-reference-status").textContent = "Derived evidence recorded. Source audio and temporary analysis files were removed."; state.musicReferencePreview = null; byId("music-reference-confirm").hidden = true; await loadMusicReferences(); }
  catch (error) { byId("music-reference-status").textContent = error.message; }
  finally { state.musicReferenceAnalyzing = false; byId("preview-music-reference").disabled = false; byId("analyze-music-reference").disabled = !state.musicReferencePreview || byId("music-reference-confirmation").value !== state.musicReferencePreview.confirmation_phrase; }
}

function renderMusicReferences() {
  const library = state.musicReferences || { artists: [], tracks: [], fusions: [] };
  byId("music-reference-count").textContent = String((library.tracks || []).length);
  byId("music-fusion-count").textContent = String((library.fusions || []).length);
  const list = byId("music-reference-list"); list.replaceChildren();
  if (!(library.artists || []).length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No reviewed reference profiles yet."; list.append(empty); }
  (library.artists || []).forEach((artist) => {
    const group = document.createElement("details"); group.className = "music-reference-artist";
    const summary = document.createElement("summary"); const name = document.createElement("strong"); name.textContent = artist.name; const count = document.createElement("small"); count.textContent = `${artist.albums.reduce((sum, album) => sum + album.tracks.length, 0)} tracks`; summary.append(name, count); group.append(summary);
    artist.albums.forEach((album) => { const release = document.createElement("section"); release.className = "music-reference-album"; const title = document.createElement("h3"); title.textContent = album.title; release.append(title); album.tracks.forEach((track) => { const row = document.createElement("div"); row.className = "music-reference-track-row"; const eligible = track.synthesis?.status === "approved" && Boolean(track.synthesis?.selected_revision_id); const picker = document.createElement("input"); picker.type = "checkbox"; picker.className = "music-reference-picker"; picker.setAttribute("aria-label", `Select ${track.provenance.title} for fusion`); picker.disabled = !eligible; picker.checked = eligible && state.musicFusionSources.has(track.reference_id); if (!eligible) state.musicFusionSources.delete(track.reference_id); picker.addEventListener("change", () => toggleMusicFusionSource(track.reference_id, picker)); const button = document.createElement("button"); button.type = "button"; button.className = "music-reference-track"; const trackTitle = document.createElement("strong"); trackTitle.textContent = track.provenance.title; const meta = document.createElement("small"); const evidence = track.evidence || {}; meta.textContent = [evidence.bpm ? `${evidence.bpm} BPM` : null, evidence.key || null, eligible ? "fusion ready" : `synthesis ${track.synthesis?.status || "pending"}`].filter(Boolean).join(" · "); button.append(trackTitle, meta); button.addEventListener("click", () => inspectMusicReference(track.reference_id, button)); row.append(picker, button); release.append(row); }); group.append(release); });
    list.append(group);
  });
  const fusions = byId("music-fusion-list"); fusions.querySelectorAll(".music-reference-track").forEach((node) => node.remove());
  (library.fusions || []).forEach((fusion) => { const button = document.createElement("button"); button.type = "button"; button.className = "music-reference-track"; const title = document.createElement("strong"); title.textContent = fusion.title; const meta = document.createElement("small"); meta.textContent = `${fusion.source_reference_ids.length} sources · ${fusion.status}`; button.append(title, meta); button.addEventListener("click", () => inspectMusicReference(fusion.fusion_id, button)); fusions.append(button); });
  updateMusicFusionSelection();
}

function toggleMusicFusionSource(referenceId, picker) {
  if (picker.checked && state.musicFusionSources.size >= 5) { picker.checked = false; byId("music-reference-fusion-status").textContent = "A fusion may contain at most five approved targets."; return; }
  if (picker.checked) state.musicFusionSources.add(referenceId); else state.musicFusionSources.delete(referenceId); updateMusicFusionSelection();
}

function updateMusicFusionSelection() {
  const count = state.musicFusionSources.size; const button = byId("draft-music-reference-fusion"); button.textContent = `Draft fusion · ${count} selected`; button.disabled = state.musicSynthesisBusy || count < 2 || count > 5;
}

async function inspectMusicReference(referenceId, button) {
  button.disabled = true;
  try { const envelope = await callSoul("music.references.get", { reference_id: referenceId }); lifecycle(envelope); const reference = dataOf(envelope).reference; state.selectedMusicReference = reference; state.musicReferenceDelete = null; state.musicReferenceReanalysis = null; state.musicSynthesisApproval = null; state.musicSynthesisRejection = null; button.querySelector("small").textContent = reference.record_type === "track" ? `${reference.status} · synthesis ${reference.synthesis.status}` : `${reference.status} · ${reference.source_reference_ids.length} sources`; renderMusicReferenceDetail(); }
  catch (error) { button.querySelector("small").textContent = error.message; }
  finally { button.disabled = false; }
}

function renderMusicReferenceDetail() {
  const reference = state.selectedMusicReference; const detail = byId("music-reference-detail");
  detail.hidden = !reference; if (detail.hidden) return;
  const track = reference.record_type === "track"; const provenance = reference.provenance || {}; const evidence = reference.evidence || {}; const synthesis = reference.synthesis || { revisions: [] };
  const revisions = synthesis.revisions || []; const latest = revisions.at(-1); const selected = revisions.find((item) => item.revision_id === synthesis.selected_revision_id);
  const latestRejected = Boolean(latest && (synthesis.rejected_revision_ids || []).includes(latest.revision_id));
  const semanticEvidenceReady = !track || (evidence.extractor_receipt?.semantic_evidence_version === 1 && ["sections", "instrumentation", "production_traits", "energy_curve", "vocal_traits"].every((field) => Array.isArray(evidence[field]) && evidence[field].length > 0 && evidence[field].every((value) => typeof value === "string" && value.trim())));
  byId("music-reference-detail-title").textContent = track ? (provenance.title || "Reference profile") : reference.title;
  byId("music-reference-detail-meta").textContent = track ? [provenance.artists?.join(", "), provenance.album, `${provenance.duration_seconds}s`, provenance.rights_assertion?.replaceAll("_", " ")].filter(Boolean).join(" · ") : `${reference.source_reference_ids.length} approved sources · fusion candidate`;
  byId("music-reference-synthesis-state").textContent = synthesis.status || "pending";
  byId("music-reference-observed").previousElementSibling.textContent = track ? "Fallible measurements derived from the source" : "Approved targets and the role Soul assigned each source";
  byId("music-reference-observed").textContent = JSON.stringify(track ? { bpm: evidence.bpm, bpm_alternatives: evidence.bpm_alternatives, key: evidence.key, key_alternatives: evidence.key_alternatives, meter: evidence.meter, sections: evidence.sections, instrumentation: evidence.instrumentation, production_traits: evidence.production_traits, energy_curve: evidence.energy_curve, vocal_traits: evidence.vocal_traits, lyrical_traits: evidence.lyrical_traits, confidence_notes: evidence.confidence_notes } : { source_reference_ids: reference.source_reference_ids, roles: reference.roles }, null, 2);
  byId("music-reference-target").textContent = latest ? JSON.stringify({ revision_id: latest.revision_id, scope: latest.scope, intent: latest.intent, title: latest.title, sound_and_structure: latest.caption, lyrics: latest.lyrics, bpm: latest.bpm, key: latest.keyscale, time: latest.timesignature, exclusions: latest.exclusions, rationale: latest.rationale }, null, 2) : "";
  byId("music-reference-target-note").textContent = latest ? `Revision ${revisions.length} · ${latest.revision_id}${selected?.revision_id === latest.revision_id ? " · approved target" : latestRejected ? " · rejected" : " · awaiting Operator decision"}` : semanticEvidenceReady ? "No synthesis has been drafted." : "Source identity and basic measurements are recorded. Semantic enrichment is required before Soul may draft from this reference.";
  const scope = byId("music-reference-synthesis-scope"); if (!latest) scope.value = "all"; scope.disabled = !latest;
  byId("draft-music-reference-synthesis").hidden = !track && !latest; byId("draft-music-reference-synthesis").textContent = track ? (latest ? "Retry selected scope" : "Draft composition target") : "Retry fusion scope";
  byId("draft-music-reference-synthesis").disabled = state.musicSynthesisBusy || !semanticEvidenceReady;
  byId("preview-music-reference-synthesis-approval").hidden = !latest || latestRejected || selected?.revision_id === latest.revision_id;
  byId("preview-music-reference-synthesis-rejection").hidden = !latest || latestRejected || selected?.revision_id === latest.revision_id;
  byId("music-reference-synthesis-confirm").hidden = !state.musicSynthesisApproval;
  byId("music-reference-synthesis-reject-confirm").hidden = !state.musicSynthesisRejection;
  byId("preview-music-reference-delete").hidden = !track;
  byId("music-reference-delete-confirm").hidden = !state.musicReferenceDelete;
  byId("reanalyze-music-reference").hidden = !track || semanticEvidenceReady;
  byId("music-reference-reanalysis-confirm").hidden = !state.musicReferenceReanalysis;
}

async function previewMusicReferenceReanalysis() {
  const reference = state.selectedMusicReference; if (!reference || reference.record_type !== "track" || state.musicReferenceAnalyzing) return;
  state.musicReferenceReanalysis = null; byId("music-reference-reanalysis-confirm").hidden = true; byId("reanalyze-music-reference").disabled = true; byId("music-reference-synthesis-status").textContent = "Preparing a complete reanalysis preview; no source media has been downloaded yet.";
  try { const envelope = await callSoul("music.references.reanalysis.preview", { reference_id: reference.reference_id }); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.musicReferenceReanalysis = data; byId("music-reference-reanalysis-scope").textContent = JSON.stringify(data.preview_scope, null, 2); prefillApprovalGate("music-reference-reanalysis-confirmation", "execute-music-reference-reanalysis", data.confirmation_phrase); byId("music-reference-synthesis-status").textContent = "Review the scope; clicking Reanalyze authorizes this foreground pass."; renderMusicReferenceDetail(); }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
  finally { byId("reanalyze-music-reference").disabled = false; }
}

async function executeMusicReferenceReanalysis() {
  const reference = state.selectedMusicReference; const preview = state.musicReferenceReanalysis; if (!reference || !preview || state.musicReferenceAnalyzing) return;
  state.musicReferenceAnalyzing = true; byId("execute-music-reference-reanalysis").disabled = true;
  try { const params = { reference_id: reference.reference_id, confirmation: byId("music-reference-reanalysis-confirmation").value, expected_digest: preview.expected_digest }; const envelope = await callNdjson("/api/v1/music-stream", "music.references.reanalysis.execute", params, {}, (event) => { const message = String(event.message || "").trim(); if (message) byId("music-reference-synthesis-status").textContent = `${String(event.stage || "working").replaceAll("_", " ")}: ${message.slice(0, 240)}`; }); lifecycle(envelope); const updated = dataOf(envelope).reference; if (!updated) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.selectedMusicReference = updated; state.musicReferenceReanalysis = null; byId("music-reference-synthesis-status").textContent = "Complete evidence profile recorded. Temporary source audio and transcript were removed."; renderMusicReferenceDetail(); await loadMusicReferences(); }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
  finally { state.musicReferenceAnalyzing = false; }
}

async function previewMusicReferenceDelete() {
  const reference = state.selectedMusicReference; if (!reference || reference.record_type !== "track") return;
  state.musicReferenceDelete = null; byId("music-reference-delete-confirm").hidden = true; byId("preview-music-reference-delete").disabled = true; byId("music-reference-synthesis-status").textContent = "Inventorying this reference and checking saved fusion dependencies…";
  try { const envelope = await callSoul("music.references.delete.preview", { reference_id: reference.reference_id }); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.musicReferenceDelete = data; byId("music-reference-delete-scope").textContent = JSON.stringify(data.preview_scope, null, 2); byId("music-reference-delete-confirmation").value = ""; byId("delete-music-reference").disabled = true; byId("music-reference-synthesis-status").textContent = "Review the exact profile deletion, then type the confirmation phrase."; renderMusicReferenceDetail(); }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
  finally { byId("preview-music-reference-delete").disabled = false; }
}

async function deleteMusicReference() {
  const reference = state.selectedMusicReference; const preview = state.musicReferenceDelete; if (!reference || !preview) return;
  byId("delete-music-reference").disabled = true;
  try { const envelope = await callSoul("music.references.delete.execute", { reference_id: reference.reference_id, confirmation: byId("music-reference-delete-confirmation").value, expected_digest: preview.expected_digest }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.selectedMusicReference = null; state.musicReferenceDelete = null; state.musicReferenceReanalysis = null; byId("music-reference-detail").hidden = true; await loadMusicReferences(); byId("music-reference-status").textContent = "Reference profile deleted. Empty artist and album groupings were removed from the archive."; }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
}

async function draftMusicReferenceSynthesis() {
  const reference = state.selectedMusicReference; if (!reference || state.musicSynthesisBusy) return;
  state.musicSynthesisBusy = true; state.musicSynthesisApproval = null; state.musicSynthesisRejection = null; renderMusicReferenceDetail(); byId("music-reference-synthesis-status").textContent = "Soul is translating observed evidence into one original composition target…";
  try { const envelope = await callSoul("music.references.synthesis.draft", { reference_id: reference.reference_id || reference.fusion_id, scope: byId("music-reference-synthesis-scope").value }); lifecycle(envelope); const updated = dataOf(envelope).reference; if (!updated) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.selectedMusicReference = updated; byId("music-reference-synthesis-status").textContent = "Candidate revision recorded. Review the exact target before approval."; renderMusicReferenceDetail(); await loadMusicReferences(); }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
  finally { state.musicSynthesisBusy = false; renderMusicReferenceDetail(); }
}

async function draftMusicReferenceFusion() {
  if (state.musicSynthesisBusy || state.musicFusionSources.size < 2 || state.musicFusionSources.size > 5) return;
  state.musicSynthesisBusy = true; updateMusicFusionSelection(); byId("music-reference-fusion-status").textContent = "Soul is reconciling the selected targets into one original composition…";
  try { const envelope = await callSoul("music.references.fusion.draft", { reference_ids: [...state.musicFusionSources] }); lifecycle(envelope); const reference = dataOf(envelope).reference; if (!reference) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.selectedMusicReference = reference; state.musicSynthesisApproval = null; state.musicFusionSources.clear(); byId("music-reference-fusion-status").textContent = "Fusion candidate recorded. Review its roles and exact target before approval."; renderMusicReferenceDetail(); await loadMusicReferences(); }
  catch (error) { byId("music-reference-fusion-status").textContent = error.message; }
  finally { state.musicSynthesisBusy = false; updateMusicFusionSelection(); }
}

async function previewMusicReferenceSynthesisApproval() {
  const reference = state.selectedMusicReference; const revision = reference?.synthesis?.revisions?.at(-1); if (!reference || !revision) return;
  byId("preview-music-reference-synthesis-approval").disabled = true;
  try { const envelope = await callSoul("music.references.synthesis.approval.preview", { reference_id: reference.reference_id || reference.fusion_id, revision_id: revision.revision_id }); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.musicSynthesisApproval = data; byId("music-reference-synthesis-scope-preview").textContent = JSON.stringify(data.preview_scope, null, 2); prefillApprovalGate("music-reference-synthesis-confirmation", "approve-music-reference-synthesis", data.confirmation_phrase); byId("music-reference-synthesis-status").textContent = "Review the exact revision; clicking Approve records the Operator decision."; renderMusicReferenceDetail(); }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
  finally { byId("preview-music-reference-synthesis-approval").disabled = false; }
}

async function previewMusicReferenceSynthesisRejection() {
  const reference = state.selectedMusicReference; const revision = reference?.synthesis?.revisions?.at(-1); if (!reference || !revision) return;
  byId("preview-music-reference-synthesis-rejection").disabled = true;
  try { const envelope = await callSoul("music.references.synthesis.rejection.preview", { reference_id: reference.reference_id || reference.fusion_id, revision_id: revision.revision_id }); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.musicSynthesisRejection = data; state.musicSynthesisApproval = null; byId("music-reference-synthesis-reject-scope").textContent = JSON.stringify(data.preview_scope, null, 2); byId("music-reference-synthesis-reject-confirmation").value = ""; byId("reject-music-reference-synthesis").disabled = true; byId("music-reference-synthesis-status").textContent = "Exact revision rejection is ready for Operator confirmation."; renderMusicReferenceDetail(); }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
  finally { byId("preview-music-reference-synthesis-rejection").disabled = false; }
}

async function rejectMusicReferenceSynthesis() {
  const rejection = state.musicSynthesisRejection; const reference = state.selectedMusicReference; if (!rejection || !reference) return;
  byId("reject-music-reference-synthesis").disabled = true;
  try { const envelope = await callSoul("music.references.synthesis.rejection.execute", { reference_id: reference.reference_id || reference.fusion_id, revision_id: rejection.revision.revision_id, confirmation: byId("music-reference-synthesis-reject-confirmation").value, expected_digest: rejection.expected_digest }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.selectedMusicReference = dataOf(envelope).reference; state.musicSynthesisRejection = null; byId("music-reference-synthesis-status").textContent = "Revision rejected and preserved. You may now retry the entire target or one component."; renderMusicReferenceDetail(); await loadMusicReferences(); }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
}

async function approveMusicReferenceSynthesis() {
  const approval = state.musicSynthesisApproval; const reference = state.selectedMusicReference; if (!approval || !reference) return;
  byId("approve-music-reference-synthesis").disabled = true;
  try { const envelope = await callSoul("music.references.synthesis.approval.execute", { reference_id: reference.reference_id || reference.fusion_id, revision_id: approval.revision.revision_id, confirmation: byId("music-reference-synthesis-confirmation").value, expected_digest: approval.expected_digest }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.selectedMusicReference = dataOf(envelope).reference; state.musicSynthesisApproval = null; byId("music-reference-synthesis-status").textContent = "Original composition target approved. Observed evidence remains unchanged."; renderMusicReferenceDetail(); await loadMusicReferences(); }
  catch (error) { byId("music-reference-synthesis-status").textContent = error.message; }
}

function renderMusicProjects() {
  const active = state.musicProjects.filter((project) => (project.release_state || "active") === "active"); const released = state.musicProjects.filter((project) => project.release_state === "released"); const visible = state.musicProjectView === "released" ? released : active;
  byId("music-folder-active").textContent = `Active · ${active.length}`; byId("music-folder-released").textContent = `Released · ${released.length}`; byId("music-folder-active").classList.toggle("is-active", state.musicProjectView === "active"); byId("music-folder-released").classList.toggle("is-active", state.musicProjectView === "released");
  byId("music-project-count").textContent = String(visible.length); const list = byId("music-project-list"); list.replaceChildren();
  if (!visible.length) { const p = document.createElement("p"); p.className = "muted"; p.textContent = state.musicProjectView === "released" ? "No released compositions." : "No active compositions."; list.append(p); return; }
  visible.forEach((project) => { const button = document.createElement("button"); button.type = "button"; button.className = `studio-item${state.selectedMusicProject?.project_id === project.project_id ? " is-active" : ""}`; const title = document.createElement("strong"); title.textContent = project.title; const meta = document.createElement("small"); meta.textContent = `${project.target_duration_seconds}s · ${project.vocal_mode} · ${project.bpm} BPM`; button.append(title, meta); button.addEventListener("click", () => selectMusicProject(project)); list.append(button); });
}

function setMusicProjectView(view) { state.musicProjectView = view; state.selectedMusicProject = null; resetMusicForm(); }

function resetMusicForm() {
  state.selectedMusicProject = null; state.musicProjectDeletePreview = null; state.musicPreview = null; byId("music-project-form").reset(); byId("music-project-form").querySelectorAll("input,textarea,select").forEach((field) => { field.disabled = false; }); byId("music-bpm").value = "110"; byId("music-key").value = "C minor"; byId("music-time").value = "4"; byId("music-seed").value = String(Math.floor(Math.random() * 2147483647)); syncMusicCompositionMode(); byId("music-workbench-title").textContent = "New composition"; byId("save-music-project").hidden = false; byId("music-project-release").hidden = true; byId("music-project-delete-card").hidden = true; byId("music-project-delete-confirm").hidden = true; byId("music-generation-card").hidden = true; byId("music-candidates").hidden = true; byId("music-form-status").textContent = "A new project preserves its exact creative inputs."; renderMusicProjects();
}

async function createMusicProject(event) {
  event.preventDefault(); byId("save-music-project").disabled = true;
  try { const project = musicProjectInput(); if (!supportedMusicDuration(project.target_duration_seconds)) throw new Error("Duration must be an exact whole second from 30 through 300, or exactly 600 seconds."); const envelope = await callSoul("music.projects.create", { project }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Project needs attention"); state.musicLoaded = false; await loadMusicStudio(); byId("music-form-status").textContent = "Project created. Preview before generation."; } catch (error) { byId("music-form-status").textContent = error.message; } finally { byId("save-music-project").disabled = false; }
}

async function selectMusicProject(project) {
  try { const envelope = await callSoul("music.projects.get", { project_id: project.project_id }); lifecycle(envelope); const data = dataOf(envelope); state.selectedMusicProject = data.project; state.musicProjectDeletePreview = null; state.musicPreview = null; renderMusicProjects(); const p = data.project; byId("music-workbench-title").textContent = p.title; byId("music-title").value = p.title; byId("music-intent").value = p.intent; byId("music-duration").value = String(p.target_duration_seconds); byId("music-vocal-mode").value = p.vocal_mode; byId("music-rights").value = p.rights_status; byId("music-bpm").value = String(p.bpm); byId("music-key").value = p.keyscale; byId("music-time").value = p.timesignature; byId("music-seed").value = String(p.seed); byId("music-caption").value = p.caption; byId("music-lyrics").value = p.lyrics; byId("music-project-form").querySelectorAll("input,textarea,select").forEach((field) => { field.disabled = true; }); syncMusicCompositionMode(); byId("save-music-project").hidden = true; const release = byId("music-project-release"); release.hidden = false; release.textContent = p.release_state === "released" ? "Restore to Active" : "Move to Released"; byId("music-project-delete-card").hidden = false; byId("music-project-delete-confirm").hidden = true; byId("music-project-delete-status").textContent = "Preview inventories this project before permanent deletion."; byId("music-generation-card").hidden = false; byId("music-generation-confirm").hidden = true; renderMusicCandidates(data.generations || []); } catch (error) { byId("music-form-status").textContent = error.message; }
}

async function toggleMusicProjectRelease() {
  const project = state.selectedMusicProject; if (!project) return; const released = project.release_state === "released"; const button = byId("music-project-release"); button.disabled = true;
  try { const envelope = await callSoul(released ? "music.projects.restore" : "music.projects.release", { project_id: project.project_id }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.musicLoaded = false; resetMusicForm(); await loadMusicStudio(); byId("music-form-status").textContent = released ? "Composition restored to Active. IDs and bindings were preserved." : "Composition moved to Released. IDs and bindings were preserved."; }
  catch (error) { byId("music-form-status").textContent = error.message; } finally { button.disabled = false; }
}

async function previewMusicProjectDelete() {
  if (!state.selectedMusicProject || state.musicGenerating) return;
  state.musicProjectDeletePreview = null; byId("music-project-delete-confirm").hidden = true; byId("preview-music-project-delete").disabled = true; byId("music-project-delete-status").textContent = "Inventorying archive-owned project data…";
  try { const envelope = await callSoul("music.projects.delete.preview", { project_id: state.selectedMusicProject.project_id }); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.musicProjectDeletePreview = data; byId("music-project-delete-scope").textContent = JSON.stringify(data.preview_scope, null, 2); byId("music-project-delete-confirmation").value = ""; byId("execute-music-project-delete").disabled = true; byId("music-project-delete-confirm").hidden = false; byId("music-project-delete-status").textContent = "Review the exact inventory and retained finished exports, then type the confirmation phrase."; }
  catch (error) { byId("music-project-delete-status").textContent = error.message; }
  finally { byId("preview-music-project-delete").disabled = false; }
}

async function executeMusicProjectDelete() {
  const preview = state.musicProjectDeletePreview; const project = state.selectedMusicProject; if (!preview || !project || state.musicGenerating) return;
  byId("execute-music-project-delete").disabled = true;
  try { const envelope = await callSoul("music.projects.delete.execute", { project_id: project.project_id, confirmation: byId("music-project-delete-confirmation").value, expected_digest: preview.expected_digest }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); state.musicProjectDeletePreview = null; state.selectedMusicProject = null; state.musicLoaded = false; resetMusicForm(); await loadMusicStudio(); byId("music-form-status").textContent = "Composition permanently removed from the archive. Finished exports were left untouched."; }
  catch (error) { byId("music-project-delete-status").textContent = error.message; }
}

async function refreshMusicResources() {
  try { const envelope = await callSoul("music.resources.status"); const data = dataOf(envelope); const ready = data.can_acquire_music === true; byId("music-resource-state").textContent = ready ? "Lane ready" : "Lane held"; byId("music-resource-state").classList.toggle("is-ready", ready); const engine = data.engine || {}; byId("music-generation-summary").textContent = ready ? `${engine.model || "Music engine"} is ready for one bounded foreground run on ${engine.accelerator || "the active Core"}.` : (data.blockers || []).join(" · ") || "Music resources need attention."; } catch (error) { byId("music-resource-state").textContent = "Unavailable"; }
}

async function previewMusicGeneration() {
  if (!state.selectedMusicProject) return; byId("music-generation-status").textContent = "Inspecting exact generation scope…";
  try { const envelope = await callSoul("music.generation.preview", { project_id: state.selectedMusicProject.project_id }); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || data.reason || "Generation is blocked"); state.musicPreview = data; state.musicCandidateId = data.candidate_id; byId("music-generation-scope").textContent = JSON.stringify(data.preview_scope, null, 2); byId("music-generation-confirm").hidden = false; prefillApprovalGate("music-generation-confirmation", "start-music-generation", data.confirmation_phrase); byId("music-generation-status").textContent = `Candidate ${data.candidate_id} is bound to this preview. Clicking Start authorizes this exact foreground run.`; } catch (error) { byId("music-generation-status").textContent = error.message; }
}

async function startMusicGeneration() {
  if (!state.musicPreview || state.musicGenerating) return; state.musicGenerating = true; byId("start-music-generation").disabled = true; byId("cancel-music-generation").disabled = false; showGenerationProgress(byId("music-progress"), { stage: "preparing", message: "Engaging the bounded Music Core." });
  const params = { project_id: state.selectedMusicProject.project_id, candidate_id: state.musicPreview.candidate_id, confirmation: byId("music-generation-confirmation").value, expected_digest: state.musicPreview.expected_digest };
  try { const envelope = await callNdjson("/api/v1/music-stream", "music.generation.execute", params, {}, (event) => showGenerationProgress(byId("music-progress"), event)); lifecycle(envelope); byId("music-generation-status").textContent = envelope.lifecycle_state === "blocked_for_human_review" ? "Candidate complete. Listen and record adherence evidence below." : (envelope.errors?.[0]?.message || envelope.lifecycle_state); await selectMusicProject(state.selectedMusicProject); if (dataOf(envelope).candidate) emitSoulNotification("music_ready", `music:${dataOf(envelope).candidate.candidate_id}`); } catch (error) { byId("music-generation-status").textContent = error.message; emitSoulNotification("attention"); } finally { state.musicGenerating = false; byId("cancel-music-generation").disabled = true; hideGenerationProgress(byId("music-progress")); }
}

async function cancelMusicGeneration() {
  if (!state.musicCandidateId) return;
  try { const preview = await callSoul("music.generation.cancel.preview", { candidate_id: state.musicCandidateId }); const data = dataOf(preview); if (!data.expected_digest) throw new Error(preview.errors?.[0]?.message || "Cancellation is not ready yet"); const phrase = window.prompt(`Cancel only ${state.musicCandidateId}? Type ${data.confirmation_phrase}`); if (phrase !== data.confirmation_phrase) { byId("music-generation-status").textContent = "Cancellation confirmation did not match; generation continues."; return; } const result = await callSoul("music.generation.cancel.execute", { candidate_id: state.musicCandidateId, confirmation: phrase, expected_digest: data.expected_digest }); byId("music-generation-status").textContent = result.lifecycle_state === "canceled" ? "Cancellation signal completed." : (result.errors?.[0]?.message || result.lifecycle_state); } catch (error) { byId("music-generation-status").textContent = error.message; }
}

async function restoreMusicGeneration(projectId) {
  try {
    const job = (await activeMusicJobs(projectId))[0];
    if (!job || (state.musicGenerating && state.musicJobId === job.job_id)) return;
    state.musicGenerating = true; state.musicJobId = job.job_id; state.musicCandidateId = job.candidate_id;
    byId("cancel-music-generation").disabled = false;
    showMusicProgress(job.latest_progress || { stage: "working", message: "Reattached to the active bounded generation job." });
    const envelope = await followMusicJob(job.job_id, showMusicProgress); lifecycle(envelope);
    if (state.selectedMusicProject?.project_id === projectId) { byId("music-generation-status").textContent = envelope.lifecycle_state === "blocked_for_human_review" ? "Candidate complete. Listen and record adherence evidence below." : (envelope.errors?.[0]?.message || envelope.lifecycle_state); await selectMusicProject({ project_id: projectId }); }
    if (dataOf(envelope).candidate) emitSoulNotification("music_ready", `music:${dataOf(envelope).candidate.candidate_id}`);
  } catch (error) { if (state.selectedMusicProject?.project_id === projectId) byId("music-generation-status").textContent = error.message; emitSoulNotification("attention"); }
  finally { state.musicGenerating = false; state.musicJobId = null; byId("cancel-music-generation").disabled = true; hideGenerationProgress(byId("music-progress")); }
}

function showMusicProgress(event) { showGenerationProgress(byId("music-progress"), event); }

function renderMusicCandidates(candidates) {
  if (state.selectedMusicProject?.project_id) restoreMusicGeneration(state.selectedMusicProject.project_id);
  const section = byId("music-candidates"); section.hidden = candidates.length === 0; byId("music-candidate-count").textContent = String(candidates.length); const list = byId("music-candidate-list"); list.replaceChildren();
  const linkedSources = new Set(candidates.map((candidate) => candidate.source_candidate_id).filter(Boolean));
  const newestFirst = candidates.slice().sort((left, right) => String(right.created_at || "").localeCompare(String(left.created_at || "")) || String(right.candidate_id).localeCompare(String(left.candidate_id)));
  newestFirst.forEach((candidate) => {
    const older = candidate.review?.disposition === "revise" && linkedSources.has(candidate.candidate_id);
    const card = document.createElement("article"); card.className = "music-candidate"; card.classList.toggle("is-older-version", older);
    const heading = document.createElement("div"); heading.className = "card-heading";
    const title = document.createElement("strong"); title.textContent = candidate.candidate_id;
    const audioSeconds = candidate.artifacts?.flac?.duration_seconds?.toFixed?.(1) || "—"; const generationSeconds = candidate.timings?.total_seconds?.toFixed?.(1); const timingLabel = generationSeconds ? ` · generated in ${generationSeconds}s` : "";
    const meta = document.createElement("small"); meta.textContent = `${audioSeconds}s audio${timingLabel} · ${older ? "older version" : (candidate.generation_kind === "revision" ? "revision" : "original")} · ${candidate.review ? candidate.review.disposition : "awaiting review"}`;
    heading.append(title, meta);
    const audio = document.createElement("audio"); audio.controls = true; audio.preload = "none"; audio.src = `/api/v1/music/audio/${candidate.project_id}/${candidate.candidate_id}/mp3`;
    const details = document.createElement("div"); details.className = "music-candidate-details"; details.hidden = older;
    const download = document.createElement("a"); download.href = `/api/v1/music/audio/${candidate.project_id}/${candidate.candidate_id}/flac`; download.textContent = "Open lossless FLAC"; download.target = "_blank";
    const analysis = musicAnalysisPanel(candidate);
    const revision = !older && (candidate.review?.disposition === "revise" || candidate.analysis?.machine_route === "revision_recommended") ? musicRevisionPanel(candidate) : null;
    if (candidate.timings) { const timing = document.createElement("p"); timing.className = "music-candidate-timing"; timing.textContent = `Generation timing · model ${Number(candidate.timings.model_seconds || 0).toFixed(1)}s · FLAC ${Number(candidate.timings.flac_derivation_seconds || 0).toFixed(1)}s · MP3 ${Number(candidate.timings.mp3_derivation_seconds || 0).toFixed(1)}s · total ${Number(candidate.timings.total_seconds || 0).toFixed(1)}s`; details.append(timing); }
    details.append(download, analysis); if (revision) details.append(revision); const visual = musicVisualCompanionPanel(candidate); if (visual) details.append(visual); if (candidate.review) details.append(musicDispositionPanel(candidate)); if (candidate.review?.disposition === "keep") details.append(musicTrimPanel(candidate, audio)); details.append(musicReviewForm(candidate));
    card.append(heading, audio);
    if (older) { const toggle = document.createElement("button"); toggle.type = "button"; toggle.className = "text-button music-version-toggle"; toggle.textContent = "Inspect older version"; toggle.addEventListener("click", () => { details.hidden = !details.hidden; toggle.textContent = details.hidden ? "Inspect older version" : "Collapse older version"; }); card.append(toggle); }
    card.append(details); list.append(card);
  });
}

function musicVisualCompanionPanel(candidate) {
  const visuals = candidate.visuals || []; const source = candidate.visual_sources?.[0]; if (!visuals.length && !source) return null;
  const panel = document.createElement("section"); panel.className = "music-visual-companion";
  const heading = document.createElement("div"); heading.className = "card-heading"; const title = document.createElement("strong"); title.textContent = "Visual Companion"; const badge = document.createElement("small"); badge.textContent = visuals.length ? `${visuals.length} visual version${visuals.length === 1 ? "" : "s"}` : "approved source available"; heading.append(title, badge); panel.append(heading);
  if (!visuals.length) {
    const status = document.createElement("p"); status.className = "dialog-status";
    const note = document.createElement("p"); note.textContent = `${source.label}. Bind this reviewed source to the exact candidate audio before any rendering.`;
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button"; button.textContent = "Preview visual binding";
    button.addEventListener("click", () => previewMusicVisualAction(candidate, panel, button, status, "import", { asset_id: source.asset_id })); panel.append(note, button, status); return panel;
  }
  visuals.forEach((visual) => panel.append(musicVisualLineage(candidate, visual, source)));
  return panel;
}

function musicVisualLineage(candidate, visual, source) {
  const staticProfile = visual.render_profile?.profile_id === "static-hold-v2";
  const generatedMotion = visual.source_kind === "generated_motion";
  const lineage = document.createElement("section"); lineage.className = "music-visual-lineage";
  const heading = document.createElement("div"); heading.className = "card-heading"; const title = document.createElement("strong"); title.textContent = staticProfile ? "Static visual presentation" : (generatedMotion ? "Generated motion companion" : "Historical visual effect"); const badge = document.createElement("small"); badge.textContent = visual.stage.replaceAll("_", " "); heading.append(title, badge); lineage.append(heading);
  const status = document.createElement("p"); status.className = "dialog-status";
  const media = document.createElement("div"); media.className = "music-visual-media";
  if (!generatedMotion) { const base = document.createElement("img"); base.src = musicVisualUrl(candidate, visual, "base"); base.alt = "Approved visual companion base scene"; media.append(base); }
  if (visual.artifacts?.loop) { const loop = document.createElement("video"); loop.controls = true; loop.loop = true; loop.muted = true; loop.preload = "none"; loop.src = musicVisualUrl(candidate, visual, "loop"); loop.setAttribute("aria-label", staticProfile ? "Static visual presentation preview" : "Retired visual effect preview"); media.append(loop); }
  if (visual.artifacts?.preview) { const preview = document.createElement("video"); preview.controls = true; preview.preload = "none"; preview.src = musicVisualUrl(candidate, visual, "preview"); preview.setAttribute("aria-label", "Full-duration visual companion with candidate audio"); media.append(preview); }
  lineage.append(media);
  const metrics = document.createElement("p"); metrics.className = "music-candidate-timing"; metrics.textContent = visual.artifacts?.loop ? `${staticProfile ? "Static hold · no synthesized motion" : (generatedMotion ? "Reviewed generated motion" : "Historical effect")} · ${visual.artifacts.loop.duration_seconds}s · ${visual.artifacts.loop.width}×${visual.artifacts.loop.height} · ${visual.artifacts.loop.fps} fps` : "Approved still is immutable; presentation encoding has not started."; lineage.append(metrics);
  if (staticProfile && !visual.artifacts?.loop) {
    const settings = musicVisualPresentationSettings(visual); lineage.append(settings.element);
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button"; button.textContent = "Preview static presentation"; button.addEventListener("click", () => previewMusicVisualAction(candidate, lineage, button, status, "loop", { visual_id: visual.visual_id, visual_presentation: settings.value() })); lineage.append(button);
  } else if (staticProfile && !visual.artifacts?.preview) {
    const note = document.createElement("p"); note.textContent = "The frame is held exactly as approved. FFmpeg only handles framing, encoding, fades, and audio muxing.";
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button gate-button--gold"; button.textContent = "Preview full-duration render"; button.addEventListener("click", () => previewMusicVisualAction(candidate, lineage, button, status, "final", { visual_id: visual.visual_id })); lineage.append(note, button);
  } else if (generatedMotion && !visual.artifacts?.preview) {
    const note = document.createElement("p"); note.textContent = "The exact reviewed motion study will repeat to the candidate duration and be muxed with the exact lossless audio. No new inference occurs.";
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button gate-button--gold"; button.textContent = "Preview full-duration motion render"; button.addEventListener("click", () => previewMusicVisualAction(candidate, lineage, button, status, "final", { visual_id: visual.visual_id })); lineage.append(note, button);
  } else if (!staticProfile && !generatedMotion) {
    const note = document.createElement("p"); note.textContent = "Historical effect evidence remains playable, but retired procedural-motion profiles cannot advance."; lineage.append(note);
    if (source) { const replacement = document.createElement("button"); replacement.type = "button"; replacement.className = "gate-button"; replacement.textContent = "Prepare static replacement"; replacement.addEventListener("click", () => previewMusicVisualAction(candidate, lineage, replacement, status, "import", { asset_id: source.asset_id })); lineage.append(replacement); }
  } else {
    const note = document.createElement("p"); note.textContent = "Static local companion ready. It remains unpublished and bound to this exact audio digest."; lineage.append(note);
    const packageButton = document.createElement("button"); packageButton.type = "button"; packageButton.className = "gate-button gate-button--gold"; packageButton.textContent = "Prepare YouTube upload package";
    packageButton.addEventListener("click", () => draftMusicPublicationPackage(candidate, visual, lineage, packageButton, status)); lineage.append(packageButton);
  }
  const motion = document.createElement("div"); motion.className = "music-visual-motion-boundary"; const motionTitle = document.createElement("strong"); motionTitle.textContent = "Generated motion"; const motionState = document.createElement("span"); motionState.textContent = generatedMotion ? "Bound and reviewed" : "Available in Visual Studio"; const motionNote = document.createElement("small"); motionNote.textContent = generatedMotion ? "This exact Wan motion study remains tied to the reviewed source still and candidate audio digest." : "Keep a still in Visual Studio to create and review a bounded Wan motion study."; motion.append(motionTitle, motionState, motionNote); lineage.append(motion);
  lineage.append(status); return lineage;
}

async function draftMusicPublicationPackage(candidate, visual, panel, button, status) {
  button.disabled = true; status.textContent = "Drafting editable upload metadata from the finished composition…";
  const identity = { project_id: candidate.project_id, candidate_id: candidate.candidate_id, visual_id: visual.visual_id };
  try {
    const envelope = await callSoul("music.publication.draft", identity); lifecycle(envelope); const data = dataOf(envelope);
    if (!data.description) throw new Error(envelope.errors?.[0]?.message || "Export the kept song before preparing its upload package");
    const editor = document.createElement("div"); editor.className = "music-publication-editor";
    const heading = document.createElement("div"); heading.className = "card-heading"; const title = document.createElement("strong"); title.textContent = "YouTube description"; const boundary = document.createElement("small"); boundary.textContent = "editable · local package only"; heading.append(title, boundary);
    const textarea = document.createElement("textarea"); textarea.rows = 18; textarea.maxLength = 5000; textarea.value = data.description; textarea.setAttribute("aria-label", "Editable YouTube description");
    const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button"; preview.textContent = "Preview exact upload package";
    preview.addEventListener("click", () => previewMusicPublicationPackage(identity, textarea, editor, preview, status));
    const note = document.createElement("p"); note.className = "card-note"; note.textContent = "The package contains the upload-ready MP4, thumbnail, youtube-description.txt sidecar, and private-upload metadata. It does not contact YouTube.";
    editor.append(heading, textarea, preview, note); button.replaceWith(editor); status.textContent = "Review the wording, links, credits, and lyrics before binding the exact package.";
  } catch (error) { status.textContent = error.message; button.disabled = false; }
}

async function previewMusicPublicationPackage(identity, textarea, editor, button, status) {
  button.disabled = true; status.textContent = "Binding the exact video, thumbnail, and edited description…";
  try {
    const description = textarea.value; const envelope = await callSoul("music.publication.preview", { ...identity, description }); lifecycle(envelope); const data = dataOf(envelope);
    if (envelope.lifecycle_state === "complete" && data.package) { status.textContent = `Upload package already exists at ${data.package.destination}`; return; }
    if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || "YouTube package preview is unavailable");
    const scope = document.createElement("pre"); scope.className = "diagnostic-output"; scope.textContent = JSON.stringify(data.preview_scope, null, 2);
    const approval = document.createElement("input"); const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = "Export exact upload package"; prefillApprovalGate(approval, execute, data.confirmation_phrase);
    execute.addEventListener("click", async () => { execute.disabled = true; status.textContent = "Copying the exact reviewed package into the finished-song library…"; try { const result = await callSoul("music.publication.execute", { ...identity, description, confirmation: approval.value, expected_digest: data.expected_digest }); lifecycle(result); const published = dataOf(result).package; if (result.lifecycle_state !== "complete" || !published) throw new Error(result.errors?.[0]?.message || result.lifecycle_state); status.textContent = `YouTube upload package ready at ${published.destination}. Nothing was uploaded or published.`; } catch (error) { status.textContent = error.message; execute.disabled = false; } });
    const label = document.createElement("label"); label.textContent = `Approval phrase · ${data.confirmation_phrase}`; label.append(approval); editor.append(scope, label, execute); textarea.disabled = true; button.remove(); status.textContent = "One click exports local upload materials only; YouTube upload and publication remain separate.";
  } catch (error) { status.textContent = error.message; button.disabled = false; }
}

function musicVisualPresentationSettings(visual) {
  const current = visual.presentation || { mode: "static", fit: "contain", matte: "#060B11", intro_fade_seconds: 2, outro_fade_seconds: 4 };
  const element = document.createElement("div"); element.className = "music-visual-presentation-settings";
  const mode = document.createElement("label"); mode.textContent = "Presentation"; const modeSelect = document.createElement("select"); const staticOption = document.createElement("option"); staticOption.value = "static"; staticOption.textContent = "Static composition"; modeSelect.append(staticOption); mode.append(modeSelect);
  const fit = document.createElement("label"); fit.textContent = "Framing"; const fitSelect = document.createElement("select"); [["contain","Contain · preserve full image"],["cover","Cover · crop to frame"]].forEach(([value,text]) => { const option = document.createElement("option"); option.value = value; option.textContent = text; fitSelect.append(option); }); fitSelect.value = current.fit; fit.append(fitSelect);
  const matte = document.createElement("label"); matte.textContent = "Matte"; const matteInput = document.createElement("input"); matteInput.type = "color"; matteInput.value = current.matte; matte.append(matteInput);
  const intro = document.createElement("label"); intro.textContent = "Fade in · seconds"; const introInput = document.createElement("input"); introInput.type = "number"; introInput.min = "0"; introInput.max = "10"; introInput.step = ".5"; introInput.value = String(current.intro_fade_seconds); intro.append(introInput);
  const outro = document.createElement("label"); outro.textContent = "Fade out · seconds"; const outroInput = document.createElement("input"); outroInput.type = "number"; outroInput.min = "0"; outroInput.max = "10"; outroInput.step = ".5"; outroInput.value = String(current.outro_fade_seconds); outro.append(outroInput);
  element.append(mode, fit, matte, intro, outro);
  return { element, value: () => ({ mode: "static", fit: fitSelect.value, matte: matteInput.value, intro_fade_seconds: Number(introInput.value), outro_fade_seconds: Number(outroInput.value) }) };
}

function musicVisualUrl(candidate, visual, artifact) { return `/api/v1/music/visual/${candidate.project_id}/${candidate.candidate_id}/${visual.visual_id}/${artifact}`; }

async function previewMusicVisualAction(candidate, panel, button, status, kind, extra) {
  button.disabled = true; status.textContent = "Binding exact visual and audio scope…";
  const base = { project_id: candidate.project_id, candidate_id: candidate.candidate_id, ...extra };
  try {
    const envelope = await callSoul(`music.visuals.${kind}.preview`, base); const data = dataOf(envelope);
    if (envelope.lifecycle_state === "complete") { await selectMusicProject({ project_id: candidate.project_id }); return; }
    if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Visual render preview is unavailable");
    const gate = document.createElement("div"); gate.className = "music-disposition-gate"; const scope = document.createElement("pre"); scope.className = "diagnostic-output"; scope.textContent = JSON.stringify(data.preview_scope, null, 2); const label = document.createElement("label"); label.textContent = `Approval phrase · ${data.confirmation_phrase}`; const input = document.createElement("input"); const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = kind === "import" ? "Bind exact source" : (kind === "loop" ? "Encode exact static preview" : "Render full-duration companion"); prefillApprovalGate(input, execute, data.confirmation_phrase); execute.addEventListener("click", () => executeMusicVisualAction(candidate, kind, base, data, input.value, execute, status)); label.append(input); gate.append(scope, label, execute); button.replaceWith(gate); status.textContent = kind === "final" ? "This creates one local MP4; it does not publish or upload anything." : "One bounded foreground encode; no image or motion model is loaded.";
  } catch (error) { status.textContent = error.message; button.disabled = false; }
}

async function executeMusicVisualAction(candidate, kind, base, preview, confirmation, button, status) {
  button.disabled = true; status.textContent = kind === "import" ? "Copying the approved source into exact candidate lineage…" : "Rendering in the foreground…";
  const params = { ...base, confirmation, expected_digest: preview.expected_digest };
  try {
    const envelope = kind === "import" ? await callSoul("music.visuals.import.execute", params) : await callNdjson("/api/v1/music-stream", `music.visuals.${kind}.execute`, params, {}, (event) => { const line = String(event.message || "").trim(); if (line) status.textContent = `${String(event.stage || "working").replaceAll("_", " ")}: ${line.slice(0, 240)}`; });
    lifecycle(envelope); if (!dataOf(envelope).visual) throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); await selectMusicProject({ project_id: candidate.project_id });
  } catch (error) { status.textContent = error.message; button.disabled = false; }
}

function musicDispositionPanel(candidate) {
  const panel = document.createElement("section"); panel.className = `music-disposition music-disposition--${candidate.review.disposition}`;
  const status = document.createElement("p"); status.className = "dialog-status";
  if (candidate.review.disposition === "reject") {
    const button = document.createElement("button"); button.type = "button"; button.className = "danger-button"; button.textContent = "Preview permanent candidate deletion";
    button.addEventListener("click", () => previewMusicDisposition(candidate, "reject", panel, button, status)); panel.append(button, status);
  } else if (candidate.review.disposition === "keep") {
    const actions = document.createElement("div"); actions.className = "music-actions";
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button gate-button--gold"; button.textContent = "Preview finished-song export";
    button.addEventListener("click", () => previewMusicDisposition(candidate, "export", panel, button, status));
    const revise = document.createElement("button"); revise.type = "button"; revise.className = "gate-button"; revise.textContent = "Re-mark as revise";
    revise.addEventListener("click", async () => {
      revise.disabled = true; status.textContent = "Recording a corrected disposition while preserving the prior keep review…";
      try {
        const review = { ...candidate.review, disposition: "revise" };
        ["schema_version", "project_id", "candidate_id", "reviewed_at"].forEach((key) => delete review[key]);
        const envelope = await callSoul("music.candidates.review", { project_id: candidate.project_id, candidate_id: candidate.candidate_id, review });
        lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state);
        await selectMusicProject({ project_id: candidate.project_id });
      } catch (error) { status.textContent = error.message; revise.disabled = false; }
    });
    actions.append(button, revise); panel.append(actions, status);
  } else {
    status.textContent = "Revision evidence is retained here until a linked candidate is generated."; panel.append(status);
  }
  return panel;
}

async function previewMusicDisposition(candidate, kind, panel, button, status) {
  button.disabled = true; status.textContent = kind === "reject" ? "Binding exact destructive scope…" : "Checking transcription and finished-library scope…";
  try {
    const envelope = await callSoul(`music.candidates.${kind}.preview`, { project_id: candidate.project_id, candidate_id: candidate.candidate_id }); const data = dataOf(envelope);
    if (envelope.lifecycle_state === "complete" && data.export) { status.textContent = `Already exported to ${data.export.destination}`; return; }
    if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || `${kind} preview is unavailable`);
    const gate = document.createElement("div"); gate.className = "music-disposition-gate";
    const scope = document.createElement("pre"); scope.className = "diagnostic-output"; scope.textContent = JSON.stringify(data.preview_scope, null, 2);
    const label = document.createElement("label"); label.textContent = kind === "reject" ? `Type ${data.confirmation_phrase}` : `Approval phrase · ${data.confirmation_phrase}`;
    const input = document.createElement("input"); input.autocomplete = "off"; input.spellcheck = false;
    const execute = document.createElement("button"); execute.type = "button"; execute.className = kind === "reject" ? "danger-button" : "gate-button gate-button--gold"; execute.textContent = kind === "reject" ? "Delete rejected candidate" : "Export finished song"; execute.disabled = true;
    input.addEventListener("input", () => { execute.disabled = input.value !== data.confirmation_phrase; });
    if (kind === "export") prefillApprovalGate(input, execute, data.confirmation_phrase);
    execute.addEventListener("click", () => executeMusicDisposition(candidate, kind, data, input.value, execute, status));
    label.append(input); gate.append(scope, label, execute); button.replaceWith(gate); status.textContent = kind === "reject" ? "Deletion removes FLAC, MP3, inputs, and transcription; a small lineage receipt remains." : "Export is atomic, owner-private, and will not overwrite an existing song folder.";
  } catch (error) { status.textContent = error.message; button.disabled = false; }
}

async function executeMusicDisposition(candidate, kind, preview, confirmation, button, status) {
  button.disabled = true; status.textContent = kind === "reject" ? "Deleting only the confirmed rejected candidate…" : "Copying the confirmed candidate into the finished-song library…";
  try {
    const envelope = await callSoul(`music.candidates.${kind}.execute`, { project_id: candidate.project_id, candidate_id: candidate.candidate_id, confirmation, expected_digest: preview.expected_digest }); lifecycle(envelope);
    if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state);
    if (kind === "reject") { await selectMusicProject({ project_id: candidate.project_id }); return; }
    status.textContent = `Finished song exported to ${dataOf(envelope).export?.destination || "the Soul music library"}.`;
  } catch (error) { status.textContent = error.message; button.disabled = false; }
}

function musicTrimPanel(candidate, sourceAudio) {
  const panel = document.createElement("section"); panel.className = "music-trim";
  const heading = document.createElement("div"); heading.className = "card-heading"; const title = document.createElement("strong"); title.textContent = "Lite Edit"; const boundary = document.createElement("small"); boundary.textContent = "source edges only"; heading.append(title, boundary);
  const explanation = document.createElement("p"); explanation.textContent = "Create a new FLAC and MP3 from the immutable original. Internal cuts, fades, and arrangement repair remain revision work.";
  const open = document.createElement("button"); open.type = "button"; open.className = "gate-button"; open.textContent = "Open trim controls";
  const status = document.createElement("p"); status.className = "dialog-status"; status.textContent = "Export the accepted original first; edited copies never overwrite it.";
  panel.append(heading, explanation, open, status);
  open.addEventListener("click", async () => { open.disabled = true; status.textContent = "Reading the source waveform locally…"; try { await buildMusicTrimControls(candidate, sourceAudio, panel, status); open.remove(); status.textContent = "Set source boundaries, audition the selection, then preview the exact derivative."; } catch (error) { status.textContent = error.message; open.disabled = false; } });
  return panel;
}

async function buildMusicTrimControls(candidate, sourceAudio, panel, status) {
  const sourceUrl = `/api/v1/music/audio/${candidate.project_id}/${candidate.candidate_id}/mp3`;
  const response = await fetch(sourceUrl, { credentials: "same-origin", cache: "no-store" }); if (!response.ok) throw new Error("Source listening copy is unavailable");
  const bytes = await response.arrayBuffer(); const Context = window.AudioContext || window.webkitAudioContext; if (!Context) throw new Error("This browser cannot render the waveform");
  const context = new Context(); let buffer; try { buffer = await context.decodeAudioData(bytes.slice(0)); } finally { await context.close(); }
  const recordedDuration = Number(candidate.artifacts?.flac?.duration_seconds); const duration = Number((Number.isFinite(recordedDuration) && recordedDuration > 0 ? recordedDuration : buffer.duration).toFixed(3)); const controls = document.createElement("div"); controls.className = "music-trim-controls";
  const canvas = document.createElement("canvas"); canvas.width = 1200; canvas.height = 150; canvas.setAttribute("aria-label", "Source audio waveform"); drawMusicWaveform(canvas, buffer);
  const grid = document.createElement("div"); grid.className = "music-trim-grid";
  const makeBoundary = (name, value) => { const label = document.createElement("label"); label.textContent = name; const input = document.createElement("input"); input.type = "number"; input.min = "0"; input.max = String(duration); input.step = "0.001"; input.value = value.toFixed(3); label.append(input); return [label, input]; };
  const [startLabel, start] = makeBoundary("Start seconds", 0); const [endLabel, end] = makeBoundary("End seconds", duration); const result = document.createElement("output"); result.textContent = `${duration.toFixed(3)} seconds selected`; grid.append(startLabel, endLabel, result);
  const actions = document.createElement("div"); actions.className = "music-actions"; const audition = document.createElement("button"); audition.type = "button"; audition.className = "quiet-button"; audition.textContent = "Audition selection"; const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button"; preview.textContent = "Preview trimmed copy"; actions.append(audition, preview);
  const update = () => { const startAt = Number(start.value); const endAt = Number(end.value); const valid = Number.isFinite(startAt) && Number.isFinite(endAt) && startAt >= 0 && endAt <= duration + 0.01 && endAt - startAt >= 1 && (startAt >= 0.01 || duration - endAt >= 0.01); preview.disabled = !valid; audition.disabled = !valid; result.textContent = valid ? `${(endAt - startAt).toFixed(3)} seconds selected` : "Choose at least one second and change an edge"; };
  start.addEventListener("input", update); end.addEventListener("input", update); update();
  audition.addEventListener("click", () => auditionMusicSelection(sourceAudio, Number(start.value), Number(end.value), audition));
  preview.addEventListener("click", () => previewMusicTrim(candidate, Number(start.value), Number(end.value), controls, preview, status));
  controls.append(canvas, grid, actions); panel.insertBefore(controls, status);
}

function drawMusicWaveform(canvas, buffer) {
  const context = canvas.getContext("2d"); const samples = buffer.getChannelData(0); const width = canvas.width; const height = canvas.height; const step = Math.max(1, Math.floor(samples.length / width)); context.clearRect(0, 0, width, height); context.fillStyle = "#161B25"; context.fillRect(0, 0, width, height); context.strokeStyle = "#3AAEDF"; context.lineWidth = 1; context.beginPath();
  for (let x = 0; x < width; x += 1) { let low = 1; let high = -1; const offset = x * step; for (let index = 0; index < step && offset + index < samples.length; index += 1) { const value = samples[offset + index]; low = Math.min(low, value); high = Math.max(high, value); } context.moveTo(x, (1 + low) * height / 2); context.lineTo(x, (1 + high) * height / 2); }
  context.stroke();
}

function auditionMusicSelection(audio, startAt, endAt, button) {
  audio.pause(); audio.currentTime = startAt; audio.play(); button.disabled = true; button.textContent = "Playing selection";
  const stop = () => { if (audio.currentTime >= endAt || audio.paused || audio.ended) { if (audio.currentTime >= endAt) audio.pause(); audio.removeEventListener("timeupdate", stop); audio.removeEventListener("pause", stop); button.disabled = false; button.textContent = "Audition selection"; } };
  audio.addEventListener("timeupdate", stop); audio.addEventListener("pause", stop);
}

async function previewMusicTrim(candidate, startSeconds, endSeconds, controls, button, status) {
  button.disabled = true; status.textContent = "Binding immutable source and exact edge boundaries…";
  try { const envelope = await callSoul("music.candidates.trim.preview", { project_id: candidate.project_id, candidate_id: candidate.candidate_id, start_seconds: startSeconds, end_seconds: endSeconds }); const data = dataOf(envelope); if (envelope.lifecycle_state === "complete" && data.trim) { status.textContent = `This exact trim already exists at ${data.trim.destination}`; return; } if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Trim preview is unavailable");
    controls.querySelectorAll("input,button").forEach((control) => { control.disabled = true; }); const gate = document.createElement("div"); gate.className = "music-disposition-gate"; const scope = document.createElement("pre"); scope.className = "diagnostic-output"; scope.textContent = JSON.stringify(data.preview_scope, null, 2); const label = document.createElement("label"); label.textContent = `Approval phrase · ${data.confirmation_phrase}`; const input = document.createElement("input"); const apply = document.createElement("button"); apply.type = "button"; apply.className = "gate-button gate-button--gold"; apply.textContent = "Create trimmed copy"; prefillApprovalGate(input, apply, data.confirmation_phrase); apply.addEventListener("click", () => executeMusicTrim(candidate, startSeconds, endSeconds, data, input.value, apply, status)); label.append(input); gate.append(scope, label, apply); controls.append(gate); status.textContent = "Clicking Create authorizes this one source-derived FLAC and MP3. The original remains untouched.";
  } catch (error) { status.textContent = error.message; button.disabled = false; }
}

async function executeMusicTrim(candidate, startSeconds, endSeconds, preview, confirmation, button, status) {
  button.disabled = true; status.textContent = "Creating the bounded source-derived copies…";
  try { const envelope = await callSoul("music.candidates.trim.execute", { project_id: candidate.project_id, candidate_id: candidate.candidate_id, start_seconds: startSeconds, end_seconds: endSeconds, confirmation, expected_digest: preview.expected_digest }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); status.textContent = `Trimmed FLAC and MP3 created at ${dataOf(envelope).trim?.destination || "the finished song edit folder"}.`; }
  catch (error) { status.textContent = error.message; button.disabled = false; }
}

function musicAnalysisPanel(candidate) {
  const panel = document.createElement("section"); panel.className = "music-analysis"; const heading = document.createElement("div"); heading.className = "card-heading"; const title = document.createElement("strong"); title.textContent = "Vocal evidence"; const badge = document.createElement("small"); heading.append(title, badge); panel.append(heading);
  if (candidate.analysis) { renderMusicAnalysisEvidence(panel, candidate.analysis, badge, candidate); return panel; }
  badge.textContent = "not analyzed"; const explanation = document.createElement("p"); explanation.className = "muted"; explanation.textContent = "Run one CPU-only foreground transcription. The model exits after the bounded pass; machine evidence routes to human testing or revision but never approves the candidate."; const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button"; preview.textContent = "Preview vocal analysis"; const status = document.createElement("p"); status.className = "dialog-status"; panel.append(explanation, preview, status);
  preview.addEventListener("click", async () => { preview.disabled = true; status.textContent = "Inspecting exact CPU analysis scope…"; try { const envelope = await callSoul("music.candidates.analysis.preview", { project_id: candidate.project_id, candidate_id: candidate.candidate_id }); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Analysis is unavailable"); const scope = document.createElement("pre"); scope.className = "diagnostic-output"; scope.textContent = JSON.stringify(data.preview_scope, null, 2); const label = document.createElement("label"); label.textContent = `Approval phrase · ${data.confirmation_phrase}`; const input = document.createElement("input"); input.autocomplete = "off"; input.spellcheck = false; const run = document.createElement("button"); run.type = "button"; run.className = "gate-button gate-button--gold"; run.textContent = "Analyze vocals in foreground"; run.disabled = true; input.addEventListener("input", () => { run.disabled = input.value !== data.confirmation_phrase; }); prefillApprovalGate(input, run, data.confirmation_phrase); run.addEventListener("click", () => runMusicAnalysis(candidate, data, input.value, status, run)); preview.replaceWith(scope, label, input, run); status.textContent = "Review the scope; clicking Analyze authorizes the bounded CPU pass. No resident model will remain."; } catch (error) { status.textContent = error.message; preview.disabled = false; } }); return panel;
}

async function runMusicAnalysis(candidate, preview, confirmation, status, button) {
  button.disabled = true; status.textContent = "Starting bounded CPU transcription…"; const params = { project_id: candidate.project_id, candidate_id: candidate.candidate_id, confirmation, expected_digest: preview.expected_digest };
  try { const envelope = await callNdjson("/api/v1/music-stream", "music.candidates.analysis.execute", params, {}, (event) => { const line = String(event.message || "").trim().split("\n").filter(Boolean).pop(); if (line) status.textContent = `${String(event.stage || "working").replaceAll("_", " ")}: ${line.slice(0, 240)}`; }); lifecycle(envelope); if (!dataOf(envelope).analysis) throw new Error(envelope.errors?.[0]?.message || "Analysis did not complete"); await selectMusicProject(state.selectedMusicProject); emitSoulNotification("lyrics_ready", `lyrics:${candidate.candidate_id}`); } catch (error) { status.textContent = error.message; button.disabled = false; emitSoulNotification("attention"); }
}

function renderMusicAnalysisEvidence(panel, analysis, badge, candidate) {
  const route = analysis.machine_route === "human_listening_test" ? "Machine heard OK → human test" : "Machine heard BAD → revision attempt"; badge.textContent = route; badge.className = analysis.machine_route === "human_listening_test" ? "is-ready" : "is-warning"; const summary = document.createElement("p"); summary.textContent = `${Math.round((analysis.alignment?.sequence_recall || 0) * 100)}% sequence recall · ${analysis.alignment?.problem_line_count || 0} likely problem lines. ${analysis.disclaimer}`; const columns = document.createElement("div"); columns.className = "music-lyric-compare"; [["Intended lyrics", analysis.intended_lyrics], ["Machine-heard lyrics", analysis.machine_heard_formatted || formatMachineHeardLyrics(analysis.segments) || analysis.machine_heard_lyrics]].forEach(([name, value]) => { const section = document.createElement("section"); const h = document.createElement("h4"); h.textContent = name; const text = document.createElement("pre"); text.textContent = value || "—"; section.append(h, text); columns.append(section); }); const lines = document.createElement("ol"); lines.className = "music-line-evidence"; (analysis.alignment?.lines || []).forEach((item) => { const line = document.createElement("li"); line.dataset.status = item.status; line.textContent = `${item.status.replaceAll("_", " ")} · ${Math.round(item.sequence_recall * 100)}% — ${item.intended}`; lines.append(line); }); panel.append(summary, columns, lines);
}

function formatMachineHeardLyrics(segments) {
  let previousEnd = null; const lines = []; (segments || []).forEach((segment) => { if (previousEnd !== null && Number(segment.start_ms) - Number(previousEnd) >= 5000) lines.push(""); lines.push(String(segment.text || "").trim()); previousEnd = segment.end_ms; }); return lines.join("\n").trim();
}

function musicRevisionPanel(candidate) {
  const panel = document.createElement("section"); panel.className = "music-revision-panel"; const launch = document.createElement("button"); launch.type = "button"; launch.className = "gate-button"; launch.textContent = "Ask Soul to draft revision"; const status = document.createElement("p"); status.className = "dialog-status"; status.textContent = "Soul will translate recorded feedback into an editable brief. It cannot start generation."; launch.addEventListener("click", () => draftMusicRevision(candidate, panel, launch, status)); panel.append(launch, status); return panel;
}

async function draftMusicRevision(candidate, panel, launch, status) {
  if (state.musicGenerating) return;
  launch.disabled = true; panel.querySelectorAll(".music-revision-rationale,.music-revision,.music-revision-gate").forEach((element) => element.remove()); status.textContent = "Soul is translating review evidence into a new material revision…";
  try { const envelope = await callSoul("music.candidates.revision.draft", { project_id: candidate.project_id, source_candidate_id: candidate.candidate_id }); const data = dataOf(envelope); if (!data.revision) throw new Error(envelope.errors?.[0]?.message || "Soul did not return a valid revision brief"); const summary = document.createElement("section"); summary.className = "music-revision-rationale"; const heading = document.createElement("strong"); heading.textContent = "Soul's proposed changes"; const rationale = document.createElement("p"); rationale.textContent = data.rationale; const changes = document.createElement("ul"); (data.changes || []).forEach((value) => { const item = document.createElement("li"); item.textContent = value; changes.append(item); }); const provider = document.createElement("small"); provider.textContent = `${data.provider?.model || "local model"} · review-only draft`; summary.append(heading, rationale, changes, provider); panel.insertBefore(summary, status); prepareMusicRevision(candidate, panel, launch, status, data.revision); status.textContent = "Review or edit this draft, retry Soul, or preview the exact revision. No generation has started."; }
  catch (error) { status.textContent = `${error.message}. No revision or generation was started.`; }
  finally { launch.disabled = false; launch.textContent = "Retry Soul draft"; }
}

function prepareMusicRevision(candidate, panel, launch, status, draft) {
  const source = candidate.generation_input; if (!source) { status.textContent = "The exact source input is unavailable; revision stopped safely."; return; } const form = document.createElement("form"); form.className = "music-revision"; const heading = document.createElement("div"); heading.className = "card-heading"; const title = document.createElement("strong"); title.textContent = "Revision input"; const sourceLabel = document.createElement("small"); sourceLabel.textContent = `from ${candidate.candidate_id}`; heading.append(title, sourceLabel);
  const field = (labelText, control) => { const label = document.createElement("label"); label.textContent = labelText; label.append(control); return label; }; const caption = document.createElement("textarea"); caption.name = "caption"; caption.rows = 6; caption.maxLength = 512; caption.required = true; caption.placeholder = "One coherent sonic identity under 512 characters; keep BPM, key, time, and lyric structure in their dedicated fields."; caption.value = draft.caption; const lyrics = document.createElement("textarea"); lyrics.name = "lyrics"; lyrics.rows = 9; lyrics.maxLength = 20000; lyrics.required = true; lyrics.placeholder = "[Verse 1 - rhythmic male vocal]\nOne lyric line at a time"; lyrics.value = draft.lyrics; const grid = document.createElement("div"); grid.className = "music-revision-grid"; const bpm = document.createElement("input"); bpm.name = "bpm"; bpm.type = "number"; bpm.min = "30"; bpm.max = "300"; bpm.required = true; bpm.value = String(draft.bpm); const key = document.createElement("input"); key.name = "keyscale"; key.maxLength = 40; key.required = true; key.value = draft.keyscale; const time = document.createElement("input"); time.name = "timesignature"; time.pattern = "2|3|4|5|6|7|9|12"; time.required = true; time.value = draft.timesignature; const seed = document.createElement("input"); seed.name = "seed"; seed.type = "number"; seed.min = "0"; seed.max = "2147483647"; seed.required = true; seed.value = String(Math.floor(Math.random() * 2147483647)); grid.append(field("BPM", bpm), field("Key", key), field("Time", time), field("Seed", seed)); const preview = document.createElement("button"); preview.type = "submit"; preview.className = "gate-button"; preview.textContent = "Preview exact revision"; form.append(heading, field("Sound and structure", caption), field("Lyrics and section markers", lyrics), grid, preview); panel.insertBefore(form, status);
  form.addEventListener("submit", async (event) => { event.preventDefault(); const revision = { caption: caption.value, lyrics: lyrics.value, bpm: Number(bpm.value), keyscale: key.value, timesignature: time.value, seed: Number(seed.value) }; preview.disabled = true; status.textContent = "Binding the revised input to one new candidate…"; try { const envelope = await callSoul("music.candidates.revision.preview", { project_id: candidate.project_id, source_candidate_id: candidate.candidate_id, revision }); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Revision preview is unavailable"); form.querySelectorAll("input,textarea,button").forEach((control) => { control.disabled = true; }); const gate = musicRevisionGate(candidate, revision, data, status); panel.insertBefore(gate, status); status.textContent = `New candidate ${data.candidate_id} is bound to this exact revision. No generation has started.`; } catch (error) { status.textContent = error.message; preview.disabled = false; } });
}

function musicRevisionGate(sourceCandidate, revision, preview, status) {
  const gate = document.createElement("div"); gate.className = "music-revision-gate"; const scope = document.createElement("pre"); scope.className = "diagnostic-output"; scope.textContent = JSON.stringify(preview.preview_scope, null, 2); const label = document.createElement("label"); label.textContent = `Approval phrase · ${preview.confirmation_phrase}`; const input = document.createElement("input"); input.autocomplete = "off"; input.spellcheck = false; const actions = document.createElement("div"); actions.className = "music-actions"; const start = document.createElement("button"); start.type = "button"; start.className = "gate-button gate-button--gold"; start.textContent = "Generate revised candidate"; start.disabled = true; const cancel = document.createElement("button"); cancel.type = "button"; cancel.className = "danger-button"; cancel.textContent = "Cancel active revision"; cancel.disabled = true; const progress = createGenerationProgress(); input.addEventListener("input", () => { start.disabled = input.value !== preview.confirmation_phrase; }); prefillApprovalGate(input, start, preview.confirmation_phrase); start.addEventListener("click", async () => { start.disabled = true; cancel.disabled = false; input.disabled = true; state.musicGenerating = true; state.musicCandidateId = preview.candidate_id; status.textContent = "Starting the bounded Music Core revision pass…"; showGenerationProgress(progress, { stage: "preparing", message: "Binding review evidence to the revised candidate." }); const params = { project_id: sourceCandidate.project_id, source_candidate_id: sourceCandidate.candidate_id, candidate_id: preview.candidate_id, revision, confirmation: input.value, expected_digest: preview.expected_digest }; try { const envelope = await callNdjson("/api/v1/music-stream", "music.candidates.revision.execute", params, {}, (event) => showGenerationProgress(progress, event)); lifecycle(envelope); const candidate = dataOf(envelope).candidate; if (!candidate) throw new Error(envelope.errors?.[0]?.message || "Revision did not complete"); await selectMusicProject(state.selectedMusicProject); emitSoulNotification("music_ready", `music:${candidate.candidate_id}`); } catch (error) { status.textContent = error.message; start.disabled = false; input.disabled = false; emitSoulNotification("attention"); } finally { state.musicGenerating = false; cancel.disabled = true; hideGenerationProgress(progress); } }); cancel.addEventListener("click", () => cancelRevisionGeneration(preview.candidate_id, status)); actions.append(start, cancel); gate.append(scope, label, input, actions, progress); return gate;
}

async function cancelRevisionGeneration(candidateId, status) {
  try { const envelope = await callSoul("music.generation.cancel.preview", { candidate_id: candidateId }); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Cancellation is unavailable"); const phrase = window.prompt(`Cancel only ${candidateId}? Type ${data.confirmation_phrase}`); if (phrase !== data.confirmation_phrase) { status.textContent = "Cancellation confirmation did not match; revision continues."; return; } const result = await callSoul("music.generation.cancel.execute", { candidate_id: candidateId, confirmation: phrase, expected_digest: data.expected_digest }); status.textContent = result.lifecycle_state === "canceled" ? "Revision cancellation signal completed." : (result.errors?.[0]?.message || result.lifecycle_state); } catch (error) { status.textContent = error.message; }
}

function musicReviewForm(candidate) {
  const form = document.createElement("form"); form.className = "music-review"; const fields = [["musical_quality", "Musical quality"], ["prompt_adherence", "Prompt"], ["vocal_adherence", "Vocals"], ["lyric_adherence", "Lyrics"]]; fields.forEach(([name, label]) => { const wrapper = document.createElement("label"); wrapper.textContent = label; const select = document.createElement("select"); select.name = name; ["passed", "partial", "failed", "not_applicable"].forEach((value) => { const option = document.createElement("option"); option.value = value; option.textContent = value.replaceAll("_", " "); select.append(option); }); wrapper.append(select); form.append(wrapper); }); const rating = document.createElement("label"); rating.textContent = "Overall rating"; const ratingInput = document.createElement("select"); ratingInput.name = "rating"; [[1,"1 · unusable"],[2,"2 · poor"],[3,"3 · workable"],[4,"4 · strong"],[5,"5 · excellent"]].forEach(([value,text]) => { const option = document.createElement("option"); option.value = String(value); option.textContent = text; option.selected = value === 3; ratingInput.append(option); }); rating.append(ratingInput); form.append(rating); const disposition = document.createElement("label"); disposition.textContent = "Disposition"; const dispositionSelect = document.createElement("select"); dispositionSelect.name = "disposition"; ["keep", "revise", "reject"].forEach((value) => { const option = document.createElement("option"); option.value = value; option.textContent = value; dispositionSelect.append(option); }); disposition.append(dispositionSelect); form.append(disposition); const notes = document.createElement("textarea"); notes.name = "notes"; notes.maxLength = 8000; notes.placeholder = "What matched, what drifted, and what should change?"; const submit = document.createElement("button"); submit.type = "submit"; submit.className = "gate-button"; submit.textContent = candidate.review ? "Record revised review" : "Record review"; const status = document.createElement("p"); status.className = "dialog-status"; form.append(notes, submit, status); if (candidate.review) { fields.forEach(([name]) => { form.elements[name].value = candidate.review[name]; }); ratingInput.value = String(candidate.review.rating); dispositionSelect.value = candidate.review.disposition; notes.value = candidate.review.notes || ""; } form.addEventListener("submit", async (event) => { event.preventDefault(); const values = Object.fromEntries(new FormData(form)); values.rating = Number(values.rating); submit.disabled = true; try { const envelope = await callSoul("music.candidates.review", { project_id: candidate.project_id, candidate_id: candidate.candidate_id, review: values }); if (envelope.lifecycle_state === "complete") { status.textContent = "Listening evidence recorded; any prior revision remains preserved."; await selectMusicProject({ project_id: candidate.project_id }); } else { status.textContent = envelope.errors?.[0]?.message || envelope.lifecycle_state; } } catch (error) { status.textContent = error.message; } finally { submit.disabled = false; } }); return form;
}

function openClearDialog() {
  state.clearPreview = null;
  state.forgetPreview = null;
  byId("clear-mode").value = "selected";
  byId("clear-title").value = state.activeChat?.title || "";
  renderClearSelection();
  setClearModeFields();
  byId("clear-preview").hidden = true;
  byId("clear-confirmation").value = "";
  byId("forget-preview").hidden = true;
  byId("forget-confirmation").value = "";
  byId("forget-confirmation-phrase").textContent = "preview required";
  byId("execute-forget").disabled = true;
  byId("preview-forget").disabled = state.chats.length === 0;
  byId("forget-dialog-status").textContent = "Permanent deletion requires a separate inventory preview and exact dynamic confirmation.";
  byId("clear-dialog-status").textContent = "Preview is required before archival.";
  byId("clear-dialog").showModal();
}

function selectedClearChatIds() {
  return Array.from(byId("clear-selection-list").querySelectorAll('input[type="checkbox"]:checked'), (input) => input.value);
}

function updateClearSelectionCount() {
  const count = selectedClearChatIds().length;
  byId("clear-selection-count").textContent = `${count} selected`;
}

function renderClearSelection() {
  const list = byId("clear-selection-list"); list.replaceChildren();
  state.chats.forEach((chat) => {
    const item = document.createElement("label"); item.className = "clear-selection-item";
    const input = document.createElement("input"); input.type = "checkbox"; input.value = chat.id; input.checked = chat.id === state.activeChat?.id;
    const copy = document.createElement("span");
    const title = document.createElement("strong"); title.textContent = chat.title || "Untitled conversation";
    const id = document.createElement("small"); id.textContent = chat.id;
    copy.append(title, id); item.append(input, copy); list.append(item);
    input.addEventListener("change", () => { updateClearSelectionCount(); resetConversationPreviews(); });
  });
  if (!state.chats.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No active conversations are available."; list.append(empty); }
  updateClearSelectionCount();
}

function setClearModeFields() {
  const mode = byId("clear-mode").value;
  byId("clear-title-field").hidden = mode !== "title";
  byId("clear-selection-field").hidden = mode !== "selected";
}

async function previewForget() {
  const status = byId("forget-dialog-status");
  state.forgetPreview = null; byId("forget-preview").hidden = true; status.textContent = "Inventorying conversation-owned data…";
  try {
    const parameters = clearParameters();
    const envelope = await callSoul("chats.forget_many.preview", parameters); lifecycle(envelope);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Delete-and-forget preview blocked."; return; }
    const data = dataOf(envelope); state.forgetPreview = { parameters, digest: data.inventory_digest, confirmation: data.confirmation_phrase, chatIds: (data.records || []).map((record) => record.id) };
    byId("forget-preview-summary").textContent = `${data.conversation_count} conversation${data.conversation_count === 1 ? "" : "s"}, ${data.message_count} message${data.message_count === 1 ? "" : "s"}, ${data.memory_count} unique linked memor${data.memory_count === 1 ? "y" : "ies"}, and ${data.artifact_attachment_count} artifact attachment${data.artifact_attachment_count === 1 ? "" : "s"} identified.`;
    const list = byId("forget-preview-list"); list.replaceChildren();
    (data.records || []).forEach((record) => { const item = document.createElement("div"); item.className = "clear-preview-item"; const title = document.createElement("strong"); title.textContent = record.title || "Untitled conversation"; const detail = document.createElement("small"); detail.textContent = `${record.id} · ${record.message_count} message${record.message_count === 1 ? "" : "s"}`; item.append(title, detail); list.append(item); });
    [
      `Delete permanently: ${data.owned_file_count} conversation-owned file(s), ${data.owned_file_bytes} byte(s) total`,
      `Forget logically: ${data.memory_count} unique shared memory record(s)`,
      `Detach only: ${data.artifact_attachment_count} artifact attachment(s); artifact files remain`,
      `Retain: ${(data.retained || []).join("; ")}`
    ].forEach((copy) => { const item = document.createElement("div"); item.className = "clear-preview-item"; const text = document.createElement("strong"); text.textContent = copy; item.append(text); list.append(item); });
    byId("forget-confirmation-phrase").textContent = data.confirmation_phrase;
    byId("forget-confirmation").value = ""; byId("execute-forget").disabled = true; byId("forget-preview").hidden = false; status.textContent = "Review every conversation and aggregate count, then type the exact confirmation.";
  } catch (error) { status.textContent = error.message || "Delete-and-forget preview failed safely."; }
}

async function executeForget() {
  if (!state.forgetPreview || byId("forget-confirmation").value !== state.forgetPreview.confirmation) return;
  const status = byId("forget-dialog-status"); byId("execute-forget").disabled = true; status.textContent = "Deleting the verified conversations and forgetting linked memory…";
  try {
    const parameters = { ...state.forgetPreview.parameters, confirmation: state.forgetPreview.confirmation, expected_digest: state.forgetPreview.digest };
    const envelope = await callSoul("chats.forget_many.execute", parameters); lifecycle(envelope);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Delete-and-forget blocked for human review."; state.forgetPreview = null; return; }
    const data = dataOf(envelope); const count = data.conversation_count || 0; const expectedIds = state.forgetPreview.chatIds;
    if (data.postcondition_verified !== true || data.deleted_chat_ids?.length !== expectedIds.length || expectedIds.some((id) => !data.deleted_chat_ids.includes(id))) throw new Error("Server did not verify the exact deletion postcondition.");
    state.activeChat = null; await loadChats(true);
    const remainingIds = new Set(state.chats.map((chat) => chat.id));
    if (expectedIds.some((id) => remainingIds.has(id))) throw new Error("Deleted conversations remain in the active list; success was not accepted.");
    state.forgetPreview = null; byId("clear-dialog").close(); announce(`${count} conversation${count === 1 ? "" : "s"} permanently deleted and verified absent`);
  } catch (error) { status.textContent = error.message || "Delete-and-forget failed safely."; }
}

function clearParameters() {
  const mode = byId("clear-mode").value;
  if (mode === "all") return { mode };
  if (mode === "selected") return { mode, chat_ids: selectedClearChatIds() };
  return { mode, title: byId("clear-title").value.trim() };
}

function resetClearPreview() {
  state.clearPreview = null;
  byId("clear-preview").hidden = true;
  byId("clear-confirmation").value = "";
  byId("execute-clear").disabled = true;
  byId("clear-dialog-status").textContent = "Scope changed; preview again.";
}

function resetForgetPreview() {
  state.forgetPreview = null;
  byId("forget-preview").hidden = true;
  byId("forget-confirmation").value = "";
  byId("forget-confirmation-phrase").textContent = "preview required";
  byId("execute-forget").disabled = true;
  byId("forget-dialog-status").textContent = "Scope changed; preview permanent deletion again.";
}

function resetConversationPreviews() {
  resetClearPreview();
  resetForgetPreview();
}

async function previewClear() {
  const status = byId("clear-dialog-status"); status.textContent = "Checking active conversations…";
  try {
    const parameters = clearParameters();
    const envelope = await callSoul("chats.clear.preview", parameters); lifecycle(envelope);
    if (envelope.lifecycle_state !== "complete") { state.clearPreview = null; byId("clear-preview").hidden = true; status.textContent = envelope.errors?.[0]?.message || "No active conversations matched."; return; }
    const data = dataOf(envelope); state.clearPreview = { parameters, digest: data.match_digest };
    byId("clear-preview-summary").textContent = `${data.count} active conversation${data.count === 1 ? "" : "s"} will leave the list. Transcript files remain stored.`;
    const list = byId("clear-preview-list"); list.replaceChildren();
    (data.records || []).forEach((record) => { const item = document.createElement("div"); item.className = "clear-preview-item"; const title = document.createElement("strong"); title.textContent = record.title || "Untitled conversation"; const id = document.createElement("small"); id.textContent = record.id; item.append(title, id); list.append(item); });
    byId("clear-confirmation").value = ""; byId("execute-clear").disabled = true; byId("clear-preview").hidden = false; status.textContent = "Review every match, then type the exact confirmation.";
  } catch (error) { status.textContent = error.message || "Preview failed safely."; }
}

async function executeClear() {
  if (!state.clearPreview || byId("clear-confirmation").value !== "CLEAR_CONVERSATIONS") return;
  const status = byId("clear-dialog-status"); byId("execute-clear").disabled = true; status.textContent = "Archiving verified conversations…";
  try {
    const parameters = { ...state.clearPreview.parameters, confirmation: "CLEAR_CONVERSATIONS", expected_digest: state.clearPreview.digest };
    const envelope = await callSoul("chats.clear.execute", parameters); lifecycle(envelope);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Archive blocked; preview again."; resetClearPreview(); return; }
    const count = dataOf(envelope).count || 0; state.activeChat = null; state.clearPreview = null; byId("clear-dialog").close(); await loadChats(true); announce(`${count} conversation${count === 1 ? "" : "s"} archived; transcripts retained`);
  } catch (error) { status.textContent = error.message || "Archive failed safely."; }
}

function preferredVoiceMimeType() {
  if (typeof MediaRecorder === "undefined") return "";
  return ["audio/webm;codecs=opus", "audio/mp4", "audio/webm", "audio/ogg;codecs=opus"].find((type) => MediaRecorder.isTypeSupported(type)) || "";
}

async function toggleVoiceRecording() {
  if (state.voiceRecorder) { stopVoiceRecording(); return; }
  if (!state.activeChat || state.busy || state.voiceTranscribing) return;
  if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
    byId("composer-hint").textContent = "This browser does not expose microphone recording.";
    return;
  }

  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
      video: false
    });
    const mimeType = preferredVoiceMimeType();
    const recorder = mimeType ? new MediaRecorder(stream, { mimeType }) : new MediaRecorder(stream);
    state.voiceStream = stream; state.voiceRecorder = recorder; state.voiceChunks = []; state.voiceStartedAt = performance.now(); state.voiceDiscard = false;
    recorder.addEventListener("dataavailable", (event) => {
      if (event.data?.size) state.voiceChunks.push(event.data);
      const elapsed = Math.floor((performance.now() - state.voiceStartedAt) / 1000);
      byId("composer-hint").textContent = `Listening · ${Math.min(elapsed, 60)}s of 60s · press Stop when finished`;
      if (elapsed >= 60 && recorder.state === "recording") stopVoiceRecording();
    });
    recorder.addEventListener("stop", finishVoiceRecording, { once: true });
    recorder.addEventListener("error", () => cancelVoiceRecording("Microphone capture failed safely."));
    recorder.start(1000);
    setSoulActivity("listening", "The microphone is open only for this visible push-to-talk recording.");
    byId("composer-hint").textContent = "Listening · 0s of 60s · press Stop when finished";
    updateVoiceControl();
  } catch (error) {
    state.voiceStream?.getTracks().forEach((track) => track.stop()); state.voiceStream = null; state.voiceRecorder = null;
    byId("composer-hint").textContent = error?.name === "NotAllowedError" ? "Microphone permission was not granted." : "Microphone capture could not start.";
    setSoulActivity("failed", "The microphone remained closed.");
    updateVoiceControl();
  }
}

function stopVoiceRecording() {
  const recorder = state.voiceRecorder;
  if (recorder?.state === "recording") recorder.stop();
}

function cancelVoiceRecording(message) {
  state.voiceDiscard = true;
  const recorder = state.voiceRecorder;
  if (recorder?.state === "recording") recorder.stop();
  else {
    state.voiceStream?.getTracks().forEach((track) => track.stop());
    state.voiceStream = null; state.voiceRecorder = null; state.voiceChunks = [];
    byId("composer-hint").textContent = message;
    updateVoiceControl();
  }
}

async function finishVoiceRecording() {
  const chunks = state.voiceChunks.slice();
  const mimeType = state.voiceRecorder?.mimeType || chunks[0]?.type || "audio/webm";
  const discard = state.voiceDiscard;
  state.voiceStream?.getTracks().forEach((track) => track.stop());
  state.voiceStream = null; state.voiceRecorder = null; state.voiceChunks = []; state.voiceStartedAt = 0; state.voiceDiscard = false;
  updateVoiceControl();
  if (discard) {
    byId("composer-hint").textContent = "Voice recording canceled; no audio was retained.";
    setSoulActivity("idle", "The local thread is quiet.");
    return;
  }
  if (!chunks.length) {
    byId("composer-hint").textContent = "No microphone audio was captured.";
    setSoulActivity("failed", "The recording ended without audio.");
    return;
  }

  state.voiceTranscribing = true; updateVoiceControl();
  byId("composer-hint").textContent = "Transcribing locally · the recording will be discarded afterward";
  setSoulActivity("transcribing", "CPU Whisper is turning the bounded recording into an editable draft.");
  try {
    const blob = new Blob(chunks, { type: mimeType });
    const response = await fetch("/api/v1/voice/transcribe", {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": mimeType, "X-Soul-CSRF": csrf },
      body: blob, cache: "no-store"
    });
    const envelope = await response.json();
    if (response.status === 401 || envelope.error?.code === "password_change_required") { window.location.reload(); throw new Error("Dashboard session expired"); }
    if (response.status === 403 && envelope.error?.code === "csrf") { window.location.reload(); throw new Error("Dashboard security token refreshed"); }
    if (!response.ok) throw new Error(envelope.error?.reason || "Microphone upload failed safely");
    if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || dataOf(envelope).message || "No transcript was produced");
    insertVoiceTranscript(dataOf(envelope).transcript || "");
    byId("composer-hint").textContent = `${Number(dataOf(envelope).duration_seconds || 0).toFixed(1)}s transcribed locally · sending through the ordinary Chat path`;
    setSoulActivity("received", "The recording was discarded. Its transcript is entering the bounded conversation path.");
    state.voiceRoundTripPending = true;
    state.voiceTranscribing = false;
    updateVoiceControl();
    byId("composer").requestSubmit();
  } catch (error) {
    byId("composer-hint").textContent = error.message || "Local transcription failed safely.";
    setSoulActivity("failed", "No message was sent and temporary audio was discarded.");
  } finally {
    state.voiceTranscribing = false; updateVoiceControl(); byId("message-input").focus();
  }
}

function insertVoiceTranscript(transcript) {
  const input = byId("message-input"); const text = String(transcript).trim(); if (!text) return;
  const start = Number.isInteger(input.selectionStart) ? input.selectionStart : input.value.length;
  const end = Number.isInteger(input.selectionEnd) ? input.selectionEnd : start;
  const prefix = start > 0 && !/\s$/.test(input.value.slice(0, start)) ? " " : "";
  const suffix = end < input.value.length && !/^\s/.test(input.value.slice(end)) ? " " : "";
  input.value = `${input.value.slice(0, start)}${prefix}${text}${suffix}${input.value.slice(end)}`;
  const cursor = start + prefix.length + text.length + suffix.length; input.setSelectionRange(cursor, cursor);
}

function clearPictureAttachment() {
  if (state.pictureAttachment?.previewUrl) URL.revokeObjectURL(state.pictureAttachment.previewUrl);
  state.pictureAttachment = null;
  const input = byId("picture-input"); if (input) input.value = "";
  const panel = byId("picture-attachment"); if (panel) panel.hidden = true;
  const preview = byId("picture-attachment-preview"); if (preview) preview.removeAttribute("src");
  const retain = byId("picture-attachment-retain"); if (retain) retain.checked = false;
  if (!state.busy && byId("composer-hint")) byId("composer-hint").textContent = state.activeChat ? "Ready · local continuity enabled" : "No conversation selected";
}

async function selectPictureAttachment(event) {
  const file = event.target.files?.[0]; if (!file) return;
  if (!["image/png", "image/jpeg"].includes(file.type)) { clearPictureAttachment(); showError(new Error("Picture attachments must be PNG or JPEG.")); return; }
  if (file.size <= 0 || file.size > 10 * 1024 * 1024) { clearPictureAttachment(); showError(new Error("Picture attachments must be between 1 byte and 10 MiB.")); return; }
  try {
    const dataUrl = await new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(String(reader.result || "")); reader.onerror = () => reject(new Error("The browser could not read that picture.")); reader.readAsDataURL(file); });
    const comma = dataUrl.indexOf(","); if (comma < 0) throw new Error("The browser produced an invalid picture payload.");
    const previewUrl = URL.createObjectURL(file);
    if (state.pictureAttachment?.previewUrl) URL.revokeObjectURL(state.pictureAttachment.previewUrl);
    state.pictureAttachment = { filename: file.name, mediaType: file.type, bytes: file.size, imageBase64: dataUrl.slice(comma + 1), previewUrl };
    byId("picture-attachment-preview").src = previewUrl;
    byId("picture-attachment-name").textContent = file.name;
    byId("picture-attachment-meta").textContent = `${formatBytes(file.size)} · ${file.type === "image/png" ? "PNG" : "JPEG"} · local only`;
    byId("picture-attachment").hidden = false;
    byId("composer-hint").textContent = "Picture ready · ask one explicit question · Daily Core required";
    byId("message-input").focus();
  } catch (error) { clearPictureAttachment(); showError(error); }
}

function openScreenCaptureDialog() {
  if (!state.activeChat || state.busy || state.screenCapturing) return;
  byId("screen-capture-status").textContent = "No pixels have been captured.";
  byId("screen-capture-dialog").showModal();
}

async function captureScreenPreview() {
  if (!state.activeChat || state.busy || state.screenCapturing) return;
  const selected = document.querySelector('input[name="screen-capture-mode"]:checked');
  const mode = selected?.value || "monitor";
  const button = byId("execute-screen-capture");
  state.screenCapturing = true; button.disabled = true;
  byId("screen-capture-status").textContent = mode === "region" ? "Waiting for one desktop region selection…" : "Capturing one local preview…";
  byId("capture-screen").disabled = true;
  try {
    const result = await callScreenCapture(mode);
    const capture = result.capture;
    clearPictureAttachment();
    const dataUrl = `data:${capture.media_type};base64,${capture.image_base64}`;
    state.pictureAttachment = {
      filename: capture.filename, mediaType: capture.media_type, bytes: capture.bytes,
      imageBase64: capture.image_base64, previewUrl: null, source: "screen_capture",
      scope: capture.scope, sourceLabel: capture.source_label
    };
    byId("picture-attachment-preview").src = dataUrl;
    byId("picture-attachment-name").textContent = capture.filename;
    byId("picture-attachment-meta").textContent = `${formatBytes(capture.bytes)} · PNG · ${capture.source_label} · local preview`;
    byId("picture-attachment").hidden = false;
    byId("composer-hint").textContent = "Screen preview ready · ask one explicit question · Daily Core required";
    byId("screen-capture-dialog").close();
    byId("message-input").focus();
    announce("One screen preview captured locally; no model has inspected it");
  } catch (error) {
    byId("screen-capture-status").textContent = error.message;
    showError(error);
  } finally {
    state.screenCapturing = false; button.disabled = false;
    byId("capture-screen").disabled = state.busy || !state.activeChat;
  }
}

async function sendMessage(event) {
  event.preventDefault(); const input = byId("message-input"); const message = input.value.trim(); if (!message || !state.activeChat || state.busy || state.voiceTranscribing || state.voiceRecorder) return;
  const voiceRoundTrip = state.voiceRoundTripPending; state.voiceRoundTripPending = false;
  const picture = state.pictureAttachment;
  const chatId = state.activeChat.id; const chatRequestId = requestId(); input.value = ""; appendPendingExchange(message, chatRequestId);
  if (!picture) state.localChatRequests.add(chatRequestId);
  emitSoulNotification("submit"); setSoulActivity("received", picture ? "The local picture and question have entered a bounded perception path." : "Submitting this transmission to local continuity.");
  setBusy(true, "Soul is responding"); byId("lifecycle-state").textContent = "pending"; document.querySelector(".state-ribbon").dataset.lifecycle = "pending"; document.querySelector(".conversation").dataset.lifecycle = "pending";
  try {
    let envelope;
    if (picture) {
      envelope = await callPictureStream({
        request_id: chatRequestId, chat_id: chatId, question: message,
        image_base64: picture.imageBase64, media_type: picture.mediaType,
        filename: picture.filename, retain: byId("picture-attachment-retain").checked
      }, (progress) => {
        const summary = progress.message || "Bounded local picture understanding is active.";
        setSoulActivity(progress.state === "observing" ? "inspecting" : progress.state, summary); updateWorkingMessage(summary);
      });
      if (envelope.lifecycle_state !== "complete") throw new Error(envelope.reason || envelope.lifecycle_state || "Picture understanding failed safely");
      clearPictureAttachment();
      byId("lifecycle-state").textContent = "complete"; document.querySelector(".state-ribbon").dataset.lifecycle = "complete"; document.querySelector(".conversation").dataset.lifecycle = "complete";
    } else {
      envelope = await callSoulStream(
        "chats.send",
        { chat_id: chatId, message },
        { current_chat_id: chatId },
        (progress) => recordChatProgress(chatId, chatRequestId, progress),
        { requestId: chatRequestId }
      );
      lifecycle(envelope);
    }
    state.localChatRequests.delete(chatRequestId); state.chatProgress.delete(chatId);
    const messages = await callSoul("chats.messages", { chat_id: chatId, limit: 200 }, { current_chat_id: chatId }); const records = dataOf(messages).records || [];
    if (state.activeChat?.id === chatId) {
      renderMessages(records);
      const workspace = await callSoul("workspace.chat", { chat_id: chatId, limit: 50 }, { current_chat_id: chatId }); renderWorkspace(dataOf(workspace).records || []);
    }
    await loadChats(false); announce(`Request ${envelope.lifecycle_state || "finished"}`);
    if (!voiceRoundTrip) emitSoulNotification("chat_ready", `chat:${chatId}:${records.at(-1)?.id || requestId()}`);
    if (voiceRoundTrip && state.activeChat?.id === chatId) {
      const reply = [...records].reverse().find((record) => record.role === "assistant" && String(record.content || record.text || "").trim());
      const buttons = [...document.querySelectorAll(".message--assistant .message-speak-button")];
      const button = buttons.at(-1);
      if (reply && button) await synthesizeMessageSpeech(String(reply.content || reply.text).trim(), button, speechContextForMessage(reply));
      else announce("Soul completed the exchange without an eligible spoken reply");
    }
  } catch (error) {
    let active = null; let accepted = false;
    try {
      const [messages, progress] = await Promise.all([
        callSoul("chats.messages", { chat_id: chatId, limit: 200 }, { current_chat_id: chatId }),
        picture ? Promise.resolve(null) : callSoul("chats.progress", { chat_id: chatId, limit: 1 }, { current_chat_id: chatId })
      ]);
      const records = dataOf(messages).records || [];
      accepted = records.some((record) => record.metadata?.application_request_id === chatRequestId) ||
        records.some((record) => record.role === "user" && record.content === message);
      if (progress) {
        replaceChatProgress(dataOf(progress).records || [], chatId);
        active = state.chatProgress.get(chatId) || null;
      }
      if (state.activeChat?.id === chatId) { renderMessages(records); renderChatProgress(active); }
      if (!accepted) input.value = message;
    } catch (_reconcileError) { input.value = message; }
    if (active) {
      setSoulActivity(active.progress_state, active.progress_summary);
      announce("The browser detached after acceptance; bounded work remains active. Reopen this conversation to refresh its state.");
    } else {
      setSoulActivity("failed", picture ? "Picture understanding stopped safely; the selected picture and draft remain available." : (accepted ? "The accepted exchange reached no active progress state; refresh this conversation for its terminal result." : "The exchange failed safely; an unsent draft has been restored."));
      emitSoulNotification("attention"); showError(error);
    }
  } finally {
    state.localChatRequests.delete(chatRequestId);
    setBusy(false);
    if (state.activeChat?.id === chatId) input.focus();
  }
}

async function togglePin() {
  if (!state.activeChat) return; const operation = state.activeChat.pinned ? "chats.unpin" : "chats.pin";
  try { const envelope = await callSoul(operation, { chat_id: state.activeChat.id }); lifecycle(envelope); state.activeChat = dataOf(envelope).record; await loadChats(false); renderChatList(); byId("pin-chat").textContent = state.activeChat.pinned ? "Unpin" : "Pin"; } catch (error) { showError(error); }
}

function detailRow(term, description) { const row = document.createElement("div"); const dt = document.createElement("dt"); dt.textContent = term; const dd = document.createElement("dd"); dd.textContent = description; row.append(dt, dd); return row; }
function setCoreMenu(open) { const menu = byId("core-menu"); menu.hidden = !open; byId("core-navigation").classList.toggle("is-open", open); byId("core-selector").setAttribute("aria-expanded", String(open)); }
function renderCores(coreStatus) {
  state.coreStatus = coreStatus; const activeLabel = coreStatus.active_core_label || (coreStatus.core_mode === "unloaded" && coreStatus.selected_core_label ? `${coreStatus.selected_core_label} · unloaded` : (coreStatus.core_mode === "unloaded" ? "Core unloaded" : "Core unavailable")); byId("core-label").textContent = activeLabel;
  const menu = byId("core-menu"); menu.replaceChildren();
  (coreStatus.cores || []).forEach((core) => {
    const button = document.createElement("button"); button.type = "button"; button.className = "core-menu-item"; button.setAttribute("role", "menuitem"); button.disabled = core.active || !core.can_activate;
    const heading = document.createElement("span"); const title = document.createElement("strong"); title.textContent = core.label; const stateLabel = document.createElement("em"); stateLabel.textContent = core.active ? "Active" : (core.can_activate ? "Available" : "Held"); heading.append(title, stateLabel);
    const purpose = document.createElement("small"); purpose.textContent = core.purpose; const target = document.createElement("small"); target.textContent = `Chat engine: ${core.target_profile?.model_name || core.target_profile?.label || "not configured"}`;
    button.append(heading, purpose, target); button.addEventListener("click", () => previewCore(core.id)); menu.append(button);
  });
  const boundary = document.createElement("p"); boundary.className = "core-menu-boundary"; boundary.textContent = coreStatus.music_lane?.conflict || "Music Studio uses a bounded foreground engine assigned by the active Core."; menu.append(boundary);
}
async function refreshCores({ automatic = false } = {}) {
  try { const envelope = await callSoul("core.status"); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Core status is unavailable"); renderCores(dataOf(envelope)); if (!automatic) announce("Core status refreshed"); }
  catch (error) { byId("core-label").textContent = "Core unavailable"; byId("core-menu").replaceChildren(Object.assign(document.createElement("p"), { textContent: error.message || "Core status failed safely." })); }
}
async function previewCore(coreId) {
  setCoreMenu(false); byId("core-label").textContent = "Checking Core…";
  try {
    const envelope = await callSoul("core.activate.preview", { core_id: coreId }); const runtime = dataOf(envelope); if (envelope.lifecycle_state !== "complete") { await refreshCores({ automatic: true }); throw new Error(envelope.errors?.[0]?.message || "Core activation is blocked."); }
    renderModelRuntime(runtime); state.modelRuntimePreview = { kind: "core", action: runtime.action, coreId, targetProfileId: runtime.target_profile?.id, digest: runtime.expected_digest, confirmation: runtime.confirmation_phrase };
    byId("model-runtime-dialog-title").textContent = `Activate ${runtime.target_core?.label || "Core"}`; byId("model-runtime-preview-title").textContent = "Transfer the verified chat engine";
    byId("model-runtime-preview-details").replaceChildren(detailRow("Current Core", runtime.source_core?.label || "Unloaded"), detailRow("Target Core", runtime.target_core?.label || coreId), detailRow("Target model", runtime.target_profile?.model_name || runtime.target_profile?.label || "unavailable"), detailRow("Accelerator", runtime.target_profile?.accelerator || "unavailable"), detailRow("Active work", String(runtime.active_work_count ?? 0)), detailRow("Music lane", runtime.target_core?.id === "amd-free" ? "held while NVIDIA chat is active" : "NVIDIA available on demand"));
    byId("model-runtime-confirmation-phrase").textContent = runtime.confirmation_phrase; prefillApprovalGate("model-runtime-confirmation", "execute-model-runtime", runtime.confirmation_phrase); byId("execute-model-runtime").textContent = `Activate ${runtime.target_core?.label || "verified Core"}`; byId("model-runtime-dialog-status").textContent = "The Core and all active work will be checked again before either service changes."; byId("model-runtime-dialog").showModal();
  } catch (error) { announce(error.message || "Core activation preview failed safely."); }
}
async function refreshStatus({ automatic = false } = {}) {
  const button = byId("refresh-status"); button.disabled = true; announce("Collecting bounded host status");
  try { const envelope = await callSoul("system_status.refresh"); lifecycle(envelope); const data = dataOf(envelope); const host = data.collected?.host?.hostname || data.hostname || data.host || "Unavailable"; const core = data.core || {}; const chat = core.chat_engine || {}; const music = core.music_engine || {}; const chatEngine = [chat.model, chat.runtime?.replaceAll("_", " "), chat.accelerator].filter(Boolean).join(" · ") || "Unavailable"; const musicEngine = [music.model, music.accelerator, music.residency?.replaceAll("_", " ")].filter(Boolean).join(" · ") || "Unavailable"; const musicLane = core.music_lane?.conflict || (core.music_lane?.available_in_active_core === true ? "Available on demand" : "Unavailable"); const details = byId("system-details"); details.replaceChildren(detailRow("Core", core.label || core.mode || "Unavailable"), detailRow("Chat engine", chatEngine), detailRow("Music engine", musicEngine), detailRow("Music lane", musicLane), detailRow("Host", host), detailRow("Collected", data.collected_at ? formatTime(data.collected_at) : "Completed"), detailRow("State", core.runtime_status || envelope.lifecycle_state || "unknown")); announce(automatic ? "Initial system status collected" : "System status refreshed manually"); } catch (error) { const details = byId("system-details"); details.replaceChildren(detailRow("Core", "Unavailable"), detailRow("Chat engine", "Unavailable"), detailRow("Music engine", "Unavailable"), detailRow("Music lane", "Unavailable"), detailRow("Host", "Unavailable"), detailRow("State", "failed")); if (!automatic) showError(error); } finally { button.disabled = false; }
}

function renderModelRuntime(runtime, message = "") {
  state.modelRuntime = runtime; const card = document.querySelector(".runtime-card"); const runtimeState = runtime.state || "unavailable"; card.dataset.state = runtimeState;
  byId("runtime-state-label").textContent = runtimeState.replaceAll("_", " ");
  byId("runtime-details").replaceChildren(
    detailRow("Core role", runtime.core_role?.replaceAll("-", " ") || "not configured"), detailRow("Profile", runtime.profile_label || runtime.profile || "not configured"), detailRow("Model", runtime.model || "not configured"),
    detailRow("Runtime", runtime.runtime?.replaceAll("_", " ") || "not configured"), detailRow("Accelerator", runtime.accelerator || "not configured"), detailRow("API alias", runtime.api_alias || "not configured"),
    detailRow("Service", runtime.service || "control disabled"), detailRow("Active work", String(runtime.active_work_count ?? 0)),
    detailRow("Server", runtime.server?.health || "unavailable"), detailRow("Resident", runtime.runtime === "ollama_openai" ? (runtime.server?.model_resident ? "model loaded" : "server ready · model on demand") : (runtime.loaded ? "model loaded" : "unloaded")),
    detailRow("At login", runtime.startup ? `${runtime.startup.state || "unknown"} · ${runtime.startup.selected_profile_id || "no selection"}` : "not configured")
  );
  const profiles = byId("runtime-profile-list"); profiles.replaceChildren();
  (runtime.profiles || []).forEach((profile) => {
    const row = document.createElement("div"); row.className = "runtime-profile"; row.classList.toggle("is-active", profile.active === true);
    const copy = document.createElement("div"); const title = document.createElement("strong"); title.textContent = profile.label || profile.id;
    const meta = document.createElement("small"); meta.textContent = [profile.model_name, profile.runtime?.replaceAll("_", " "), profile.accelerator, profile.core_role?.replaceAll("-", " "), profile.service_state, profile.selected ? "selected at login" : null].filter(Boolean).join(" · "); copy.append(title, meta); row.append(copy);
    let action = null; if (!profile.active && profile.service_state === "inactive" && runtime.can_load_profile) action = "load"; else if (!profile.active && profile.service_state === "inactive" && runtime.can_switch) action = "switch";
    if (action) { const button = document.createElement("button"); button.type = "button"; button.className = "runtime-profile-action"; button.textContent = action; button.addEventListener("click", () => previewModelRuntime(action, profile.id)); row.append(button); }
    else { const stateLabel = document.createElement("span"); stateLabel.className = "runtime-profile-state"; stateLabel.textContent = profile.active ? "active" : profile.service_state; row.append(stateLabel); }
    profiles.append(row);
  });
  byId("load-model-runtime").disabled = !runtime.can_load; byId("unload-model-runtime").disabled = !runtime.can_unload;
  byId("runtime-card-status").textContent = message || (runtime.configured ? "Manual only · no automatic load or idle unload" : "Configure runtime control in the private environment file to enable actions.");
}

async function refreshModelRuntime({ automatic = false } = {}) {
  const button = byId("refresh-model-runtime"); button.disabled = true;
  try {
    const envelope = await callSoul("model_runtime.status"); const runtime = dataOf(envelope);
    renderModelRuntime(runtime, envelope.lifecycle_state === "complete" ? "Manual only · no automatic load or idle unload" : (envelope.errors?.[0]?.message || "Runtime status is unavailable."));
    if (!automatic) announce("Model runtime status refreshed");
  } catch (error) { renderModelRuntime({}, error.message || "Model runtime status failed safely."); }
  finally { button.disabled = false; }
}

async function previewModelRuntime(action, profileId = null) {
  state.modelRuntimePreview = null; const status = byId("runtime-card-status"); status.textContent = `Checking whether ${action} is safe…`;
  try {
    const parameters = profileId ? { profile_id: profileId } : {};
    const envelope = await callSoul(`model_runtime.${action}.preview`, parameters); const runtime = dataOf(envelope); renderModelRuntime(runtime);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || `Model ${action} is blocked.`; return; }
    state.modelRuntimePreview = { kind: "runtime", action, profileId, digest: runtime.expected_digest, confirmation: runtime.confirmation_phrase };
    const actionTitle = action === "switch" ? "Switch model runtime" : `${action === "load" ? "Load" : "Unload"} model runtime`;
    byId("model-runtime-dialog-title").textContent = actionTitle;
    byId("model-runtime-preview-title").textContent = action === "switch" ? "Transfer the verified inference profile" : (action === "load" ? "Start the selected user service" : "Release model GPU memory");
    byId("model-runtime-preview-details").replaceChildren(
      detailRow("Current", runtime.profile_label || runtime.profile || "not configured"), detailRow("Target", runtime.target_profile?.label || runtime.target_profile?.id || runtime.profile || "not configured"),
      detailRow("Runtime", runtime.target_profile?.runtime?.replaceAll("_", " ") || runtime.runtime?.replaceAll("_", " ") || "unavailable"), detailRow("Service", runtime.target_profile?.service || runtime.service || "unavailable"), detailRow("Active work", String(runtime.active_work_count ?? 0)),
      detailRow("Activity probe", runtime.server?.idle_observable ? (runtime.server.slots_reachable ? `${runtime.server.active_slots} active / ${runtime.server.total_slots} slots` : "Ollama residency reachable") : "unavailable")
    );
    byId("model-runtime-confirmation-phrase").textContent = runtime.confirmation_phrase; prefillApprovalGate("model-runtime-confirmation", "execute-model-runtime", runtime.confirmation_phrase);
    byId("execute-model-runtime").textContent = action === "switch" ? "Switch verified model runtime" : `${action === "load" ? "Load" : "Unload"} verified model runtime`;
    byId("model-runtime-dialog-status").textContent = "The runtime state will be checked again before the service changes."; byId("model-runtime-dialog").showModal();
  } catch (error) { status.textContent = error.message || `Model ${action} preview failed safely.`; }
}

async function executeModelRuntime() {
  const preview = state.modelRuntimePreview; if (!preview || byId("model-runtime-confirmation").value !== preview.confirmation) return;
  const button = byId("execute-model-runtime"); const status = byId("model-runtime-dialog-status"); button.disabled = true; status.textContent = "Revalidating active work and service state…";
  try {
    const parameters = { confirmation: preview.confirmation, expected_digest: preview.digest }; let operation = `model_runtime.${preview.action}.execute`; if (preview.kind === "core") { operation = "core.activate.execute"; parameters.core_id = preview.coreId; parameters.target_profile_id = preview.targetProfileId; } else if (preview.profileId) parameters.profile_id = preview.profileId;
    const envelope = await callSoul(operation, parameters); const runtime = dataOf(envelope); renderModelRuntime(runtime);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Runtime change was blocked safely."; state.modelRuntimePreview = null; return; }
    state.modelRuntimePreview = null; byId("model-runtime-dialog").close(); announce(preview.kind === "core" ? "Core activation complete" : `Model runtime ${preview.action} complete`); await refreshModelRuntime(); await refreshCores({ automatic: true }); await refreshStatus({ automatic: true });
  } catch (error) { status.textContent = error.message || "Runtime change failed safely."; }
}

function showError(error) { byId("lifecycle-state").textContent = "failed"; document.querySelector(".state-ribbon").dataset.lifecycle = "failed"; document.querySelector(".conversation").dataset.lifecycle = "failed"; announce(error.message || "Request failed safely"); }

function studioItem(titleText, metaText, active, onClick) {
  const button = document.createElement("button"); button.type = "button"; button.className = "studio-item"; button.classList.toggle("is-active", active);
  const title = document.createElement("strong"); title.textContent = titleText;
  const meta = document.createElement("small"); meta.textContent = metaText;
  button.append(title, meta); button.addEventListener("click", onClick); return button;
}

function renderStudioLists(production = null) {
  if (production) state.productionSkills = production.records || [];
  const proposals = byId("proposal-list"); proposals.replaceChildren(); byId("proposal-count").textContent = String(state.proposals.length);
  if (!state.proposals.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No proposal packets found."; proposals.append(empty); }
  state.proposals.forEach((record) => { const source = record.intake ? `gap intake · ${record.occurrence_count || 1} occurrence${record.occurrence_count === 1 ? "" : "s"}` : (record.provider || "local"); proposals.append(studioItem(record.title || record.proposal_id, `${record.stage?.replaceAll("_", " ") || "awaiting proposal review"} · ${source}`, state.selectedProposal?.proposal_id === record.proposal_id, () => selectProposal(record.proposal_id))); });

  const betas = byId("beta-list"); betas.replaceChildren(); byId("beta-count").textContent = String(state.betas.length);
  if (!state.betas.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No implemented Beta packages yet."; betas.append(empty); }
  state.betas.forEach((record) => betas.append(studioItem(record.beta_id, `${record.maturity?.replaceAll("_", " ")} · ${record.runnable ? "runnable" : "not runnable"}`, state.selectedBeta?.beta_id === record.beta_id, () => selectBeta(record.beta_id))));

  const skills = byId("production-skill-list"); skills.replaceChildren(); byId("production-skill-count").textContent = String(state.productionSkills.length);
  state.productionSkills.forEach((record) => { const button = studioItem(record.skill_id, `${record.risk || "unknown"} · ${record.available ? "available" : "unavailable"}`, false, () => focusProductionSkill(record.skill_id)); button.dataset.skillId = record.skill_id; button.classList.toggle("is-linked", state.linkedProductionSkill === record.skill_id); skills.append(button); });
  if (!state.productionSkills.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No registered production skills."; skills.append(empty); }
}

function focusProductionSkill(skillId) {
  state.linkedProductionSkill = skillId; renderStudioLists(); const target = Array.from(byId("production-skill-list").querySelectorAll("button")).find((button) => button.dataset.skillId === skillId); if (target) target.focus();
}

async function loadSkillStudio() {
  try {
    const [proposalEnvelope, betaEnvelope, skillsEnvelope] = await Promise.all([
      callSoul("skill_studio.proposals.list", { limit: 100 }),
      callSoul("skill_studio.betas.list", { limit: 100 }),
      callSoul("skills.list", { limit: 100 })
    ]);
    state.proposals = dataOf(proposalEnvelope).records || []; state.betas = dataOf(betaEnvelope).records || []; state.studioLoaded = true;
    renderStudioLists(dataOf(skillsEnvelope)); announce("Skill Studio inventories loaded");
  } catch (error) { byId("studio-empty").querySelector("p:last-child").textContent = error.message || "Skill Studio failed safely."; }
}

function showStudioDetail(kind) {
  byId("studio-detail-pane").classList.toggle("is-empty", kind === "empty");
  byId("studio-empty").hidden = true;
  byId("proposal-detail").hidden = kind !== "proposal";
  byId("beta-detail").hidden = kind !== "beta";
}

function renderDefinitionList(target, entries) {
  target.replaceChildren(); entries.forEach(([term, value]) => target.append(detailRow(term, value == null || value === "" ? "—" : String(value))));
}

function renderChecklist(target, items, emptyText) {
  target.replaceChildren();
  if (!items.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = emptyText; target.append(empty); return; }
  items.forEach((item) => { const row = document.createElement("div"); row.className = `test-item ${item.complete || item.passed ? "is-passed" : ""}`; const mark = document.createElement("span"); mark.textContent = item.complete || item.passed ? "✓" : "○"; const copy = document.createElement("span"); const title = document.createElement("strong"); title.textContent = item.description || item.text || item.id || "Test requirement"; copy.append(title); if (item.id) { const id = document.createElement("small"); id.textContent = item.id; copy.append(id); } row.append(mark, copy); target.append(row); });
}

async function selectProposal(proposalId) {
  try {
    const envelope = await callSoul("skill_studio.proposals.get", { proposal_id: proposalId }); const record = dataOf(envelope).record; if (!record) return;
    state.selectedProposal = record; state.selectedBeta = null; state.proposalApproval = null; state.betaBuildPreview = null; state.proposalClosePreview = null; state.linkedProductionSkill = record.production_registered ? record.linked_skill_id : null; showStudioDetail("proposal"); renderStudioLists();
    byId("proposal-title").textContent = record.title || proposalId; byId("proposal-description").textContent = record.description || "No proposal description.";
    byId("proposal-gate-state").textContent = record.stage?.replaceAll("_", " ") || "awaiting proposal review";
    const proposalMeta = [["Proposal ID", record.proposal_id], ["Stage", record.stage?.replaceAll("_", " ")], ["Created", record.created_at], ["Linked skill", record.linked_skill_id || "not built"], ["Skill maturity", record.linked_skill_maturity?.replaceAll("_", " ")], ["Beta gate", record.beta_gate?.replaceAll("_", " ")]];
    if (record.intake) proposalMeta.push(["Origin chat", record.origin_chat_id], ["Gap class", record.gap_classification?.replaceAll("_", " ")], ["Occurrences", record.occurrence_count], ["Intake state", record.intake_status?.replaceAll("_", " ")]);
    renderDefinitionList(byId("proposal-meta"), proposalMeta);
    const linkedButton = byId("view-linked-skill"); linkedButton.hidden = !record.production_registered; linkedButton.textContent = record.production_registered ? `Locate production skill · ${record.linked_skill_id}` : "Locate linked production skill";
    byId("proposal-cloud").textContent = record.intake ? "Created locally from an unsatisfied chat request. No cloud provider was invoked. Optional Mistral development remains a separate disclosed human action." : (record.cloud_assisted ? `${record.provider} / ${record.model || "configured model"}; data class ${record.cloud_data_class || "unspecified"}. This output is advisory and cannot approve itself.` : "No cloud provider is recorded for this proposal.");
    byId("proposal-markdown").textContent = record.proposal_markdown || "No proposal text available."; renderChecklist(byId("proposal-checklist"), record.review_checklist || [], "No checklist file was supplied.");
    const approved = record.proposal_gate === "approved"; byId("preview-proposal-approval").disabled = approved; byId("proposal-approval-confirm").hidden = true; byId("proposal-confirmation").value = ""; byId("proposal-approval-status").textContent = approved ? "This exact proposal revision is approved for Beta implementation." : "Review the brief and checklist before opening Gate 1.";
    const canPrepareBeta = approved && !record.beta_present; byId("beta-build-card").hidden = !canPrepareBeta; byId("beta-build-confirm").hidden = true; byId("beta-build-confirmation").value = ""; byId("execute-beta-build").disabled = true; byId("beta-build-status").textContent = canPrepareBeta ? "Preparation creates candidate files only; implementation remains a separate reviewed Codex or human task." : ""; if (canPrepareBeta) byId("beta-build-skill-id").value = `generated.${record.proposal_id.toLowerCase().replace(/[^a-z0-9_]+/g, "_").replace(/^_+|_+$/g, "") || "skill"}`;
    byId("proposal-close-card").hidden = !record.closable; byId("proposal-close-confirm").hidden = true; byId("proposal-close-confirmation").value = ""; byId("execute-proposal-close").disabled = true; byId("proposal-close-status").textContent = record.closable ? "Production linkage verified. Preview the exact deletion boundary before closing." : "";
  } catch (error) { announce(error.message || "Proposal could not be loaded."); }
}

async function previewProposalApproval() {
  if (!state.selectedProposal) return;
  const status = byId("proposal-approval-status"); status.textContent = "Checking proposal revision…";
  const envelope = await callSoul("skill_studio.proposals.approval.preview", { proposal_id: state.selectedProposal.proposal_id }); const data = dataOf(envelope);
  if (!data.expected_digest) { status.textContent = envelope.errors?.[0]?.message || data.reason || "Approval preview blocked."; return; }
  state.proposalApproval = data; byId("proposal-approval-confirm").hidden = false; prefillApprovalGate("proposal-confirmation", "execute-proposal-approval", data.confirmation_phrase || "APPROVE_PROPOSAL_FOR_BETA_BUILD"); status.textContent = "Review the exact proposal; clicking Approve records Gate 1 authority only.";
}

async function executeProposalApproval() {
  if (!state.selectedProposal || !state.proposalApproval) return;
  const envelope = await callSoul("skill_studio.proposals.approval.execute", { proposal_id: state.selectedProposal.proposal_id, expected_digest: state.proposalApproval.expected_digest, confirmation: byId("proposal-confirmation").value });
  if (envelope.lifecycle_state !== "complete") { byId("proposal-approval-status").textContent = envelope.errors?.[0]?.message || "Approval blocked; preview again."; return; }
  state.studioLoaded = false; await loadSkillStudio(); await selectProposal(state.selectedProposal.proposal_id); announce("Proposal approved for bounded Beta implementation");
}

async function previewBetaBuild() {
  if (!state.selectedProposal) return; const status = byId("beta-build-status"); const skillId = byId("beta-build-skill-id").value.trim(); status.textContent = "Validating Gate 1 and proposal revision…";
  const envelope = await callSoul("skill_studio.proposals.beta_build.preview", { proposal_id: state.selectedProposal.proposal_id, skill_id: skillId }); const data = dataOf(envelope);
  if (!data.expected_digest) { status.textContent = envelope.errors?.[0]?.message || data.reason || "Beta preparation preview blocked."; return; }
  state.betaBuildPreview = data; byId("beta-build-confirm").hidden = false; byId("beta-build-phrase").textContent = data.confirmation_phrase; prefillApprovalGate("beta-build-confirmation", "execute-beta-build", data.confirmation_phrase); status.textContent = "Review the exact skill ID and candidate-only boundary; clicking Prepare authorizes this workspace.";
}

async function executeBetaBuild() {
  if (!state.selectedProposal || !state.betaBuildPreview) return; const status = byId("beta-build-status"); status.textContent = "Preparing bounded proposal-local Beta workspace…";
  const envelope = await callSoul("skill_studio.proposals.beta_build.execute", { proposal_id: state.selectedProposal.proposal_id, skill_id: state.betaBuildPreview.skill_id, expected_digest: state.betaBuildPreview.expected_digest, confirmation: byId("beta-build-confirmation").value }); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || data.reason || "Beta preparation blocked; preview again."; return; }
  state.studioLoaded = false; await loadSkillStudio(); await selectBeta(data.beta_id); announce(`Prepared incomplete Beta workspace ${data.beta_id}`);
}

async function previewProposalClose() {
  if (!state.selectedProposal) return; const status = byId("proposal-close-status"); status.textContent = "Revalidating production linkage and closeout boundary…";
  const envelope = await callSoul("skill_studio.proposals.close.preview", { proposal_id: state.selectedProposal.proposal_id }); const data = dataOf(envelope);
  if (!data.expected_digest) { status.textContent = envelope.errors?.[0]?.message || data.reason || "Closeout preview blocked."; return; }
  state.proposalClosePreview = data; byId("proposal-close-confirm").hidden = false; byId("proposal-close-confirmation").value = ""; byId("execute-proposal-close").disabled = true; status.textContent = `Will delete proposal and superseded Beta for ${data.linked_skill_id}; the production skill and shared diagnostics remain.`;
}

async function executeProposalClose() {
  if (!state.selectedProposal || !state.proposalClosePreview) return; const proposalId = state.selectedProposal.proposal_id; const status = byId("proposal-close-status"); status.textContent = "Checking unchanged closeout digest…";
  const envelope = await callSoul("skill_studio.proposals.close.execute", { proposal_id: proposalId, expected_digest: state.proposalClosePreview.expected_digest, confirmation: byId("proposal-close-confirmation").value });
  if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Proposal closeout blocked; preview again."; return; }
  state.selectedProposal = null; state.proposalClosePreview = null; state.linkedProductionSkill = null; state.studioLoaded = false; showStudioDetail("empty"); byId("studio-empty").hidden = false; await loadSkillStudio(); announce(`Closed production proposal ${proposalId}`);
}

async function selectBeta(betaId) {
  try {
    const envelope = await callSoul("skill_studio.betas.get", { beta_id: betaId }); const record = dataOf(envelope).record; if (!record) return;
    state.selectedBeta = record; state.selectedProposal = null; state.betaRunPreview = null; state.betaPromotionPreview = null; state.productionPromotionPreview = null; showStudioDetail("beta"); renderStudioLists();
    byId("beta-title").textContent = record.beta_id; byId("beta-description").textContent = record.description || "No Beta description."; byId("beta-maturity").textContent = record.maturity?.replaceAll("_", " ") || "beta";
    renderDefinitionList(byId("beta-meta"), [["Proposal", record.proposal_id], ["Risk", record.risk], ["Runnable", record.runnable ? "human-confirmed only" : "no"], ["Tests", `${record.test_summary?.passed || 0}/${record.test_summary?.declared || 0} passing`], ["Current revision", record.test_summary?.tested_current_revision ? "tested" : "not tested"], ["Promotion", record.promotion_state?.replaceAll("_", " ")]]);
    renderChecklist(byId("beta-tests"), record.required_tests || [], "No required tests are declared; promotion is blocked."); renderChecklist(byId("beta-weaknesses"), (record.known_weaknesses || []).map((text) => ({ text })), "No known weaknesses were declared.");
    byId("preview-beta-run").disabled = !record.runnable; byId("beta-run-confirm").hidden = true; byId("beta-run-output").hidden = true; byId("beta-run-status").textContent = record.maturity === "legacy_alpha_scaffold" ? "Legacy alpha scaffold: visible for migration, never runnable." : (record.runnable ? "A preview and exact human confirmation are required." : "Beta package is incomplete or has an invalid entrypoint.");
    byId("beta-promotion-confirm").hidden = true; byId("beta-promotion-status").textContent = "Gate 2 checks Gate 1, implementation, test evidence, and revision integrity.";
    const gate2Approved = record.promotion_state === "approved_for_promotion" && !record.production_registered; byId("production-promotion-card").hidden = !gate2Approved; byId("production-promotion-confirm").hidden = true; byId("production-promotion-confirmation").value = ""; byId("execute-production-promotion").disabled = true; byId("production-promotion-status").textContent = gate2Approved ? "Gate 2 is approved. Preview the exact production and registry mutation before continuing." : "";
  } catch (error) { announce(error.message || "Beta could not be loaded."); }
}

function betaArguments() { return byId("beta-args").value.split("\n").map((value) => value.trim()).filter(Boolean); }

async function previewBetaRun() {
  if (!state.selectedBeta) return; const status = byId("beta-run-status"); status.textContent = "Preparing bounded Beta run preview…";
  const envelope = await callSoul("skill_studio.betas.run.preview", { beta_id: state.selectedBeta.beta_id, args: betaArguments() }); const data = dataOf(envelope);
  if (!data.expected_digest) { status.textContent = envelope.errors?.[0]?.message || data.reason || "Beta run preview blocked."; return; }
  state.betaRunPreview = data; byId("beta-run-confirm").hidden = false; byId("beta-run-phrase").textContent = data.confirmation_phrase; prefillApprovalGate("beta-run-confirmation", "execute-beta-run", data.confirmation_phrase); status.textContent = `Foreground timeout: ${data.timeout_seconds}s. Clicking Run authorizes this bounded invocation.`;
}

async function executeBetaRun() {
  if (!state.selectedBeta || !state.betaRunPreview) return; const status = byId("beta-run-status"); status.textContent = "Running Beta in the foreground…";
  const envelope = await callSoul("skill_studio.betas.run.execute", { beta_id: state.selectedBeta.beta_id, args: betaArguments(), expected_digest: state.betaRunPreview.expected_digest, confirmation: byId("beta-run-confirmation").value }); const data = dataOf(envelope);
  const output = byId("beta-run-output"); output.hidden = false; output.textContent = [data.stdout, data.stderr].filter(Boolean).join("\n") || envelope.errors?.[0]?.message || "Beta returned no output."; status.textContent = data.diagnostic_log ? `Finished ${envelope.lifecycle_state}; diagnostic record: ${data.diagnostic_log}` : `Beta run ${envelope.lifecycle_state}.`;
}

async function previewBetaPromotion() {
  if (!state.selectedBeta) return; const status = byId("beta-promotion-status"); status.textContent = "Checking test evidence and revision integrity…";
  const envelope = await callSoul("skill_studio.betas.promotion.preview", { beta_id: state.selectedBeta.beta_id }); const data = dataOf(envelope); if (!data.expected_digest) { status.textContent = envelope.errors?.[0]?.message || data.reason || "Promotion preview blocked."; return; }
  state.betaPromotionPreview = data; byId("beta-promotion-confirm").hidden = false; const blockers = (data.blockers || []).map((text) => ({ text, passed: false })); renderChecklist(byId("beta-promotion-blockers"), blockers, "All deterministic prerequisites are satisfied."); prefillApprovalGate("beta-promotion-confirmation", "execute-beta-promotion", data.confirmation_phrase || "APPROVE_BETA_FOR_PROMOTION", data.ready === true); status.textContent = data.ready ? "Ready for Gate 2. Clicking Approve records the decision but does not perform promotion." : "Promotion approval is blocked until every listed requirement is satisfied.";
}

async function executeBetaPromotion() {
  if (!state.selectedBeta || !state.betaPromotionPreview?.ready) return;
  const envelope = await callSoul("skill_studio.betas.promotion.approve", { beta_id: state.selectedBeta.beta_id, expected_digest: state.betaPromotionPreview.expected_digest, confirmation: byId("beta-promotion-confirmation").value });
  if (envelope.lifecycle_state !== "complete") { byId("beta-promotion-status").textContent = envelope.errors?.[0]?.message || "Gate 2 approval blocked."; return; }
  state.studioLoaded = false; await loadSkillStudio(); await selectBeta(state.selectedBeta.beta_id); announce("Beta approved for a later explicit promotion workflow");
}

async function previewProductionPromotion() {
  if (!state.selectedBeta) return; const status = byId("production-promotion-status"); status.textContent = "Revalidating Gate 2, tests, source bytes, and production target…";
  const envelope = await callSoul("skill_studio.betas.production.preview", { beta_id: state.selectedBeta.beta_id }); const data = dataOf(envelope);
  if (!data.expected_digest) { status.textContent = envelope.errors?.[0]?.message || data.reason || "Production promotion preview blocked."; return; }
  state.productionPromotionPreview = data; byId("production-promotion-confirm").hidden = false; byId("production-promotion-phrase").textContent = data.confirmation_phrase; prefillApprovalGate("production-promotion-confirmation", "execute-production-promotion", data.confirmation_phrase);
  renderChecklist(byId("production-promotion-scope"), [{ text: `Copy ${data.source_entrypoint} → ${data.production_entrypoint}`, complete: true }, { text: `Register ${data.beta_id} in ${data.registry_path}`, complete: true }, { text: `Source SHA-256 ${data.source_sha256}`, complete: true }, ...((data.rollback || []).map((text) => ({ text: `Rollback: ${text}`, complete: true })))], "No production scope returned."); status.textContent = "Exact source, target, hash, registry definition, and rollback are bound into this preview.";
}

async function executeProductionPromotion() {
  if (!state.selectedBeta || !state.productionPromotionPreview) return; const betaId = state.selectedBeta.beta_id; const status = byId("production-promotion-status"); status.textContent = "Publishing exact reviewed bytes and registry entry…";
  const envelope = await callSoul("skill_studio.betas.production.execute", { beta_id: betaId, expected_digest: state.productionPromotionPreview.expected_digest, confirmation: byId("production-promotion-confirmation").value }); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || data.reason || "Production promotion failed safely."; return; }
  state.studioLoaded = false; await loadSkillStudio(); await selectProposal(data.proposal_id); announce(`Promoted ${betaId} to production`);
}

function labeledRecord(titleText, metaText, tone = "") {
  const item = document.createElement("div"); item.className = `assessment-record ${tone}`.trim();
  const title = document.createElement("strong"); title.textContent = titleText;
  const meta = document.createElement("small"); meta.textContent = metaText;
  item.append(title, meta); return item;
}

function renderImprovementEnvironment(report) {
  if (!report) return;
  const system = report.system || {};
  const managers = Object.entries(report.package_managers?.managers || {}).filter(([, value]) => value.detected);
  const updateCandidates = managers.reduce((count, [, value]) => count + (value.updates?.count || 0), 0);
  const cleanupCandidates = managers.reduce((count, [, value]) => count + (value.orphans?.count || 0) + (value.unused?.count || 0), 0);
  renderDefinitionList(byId("improvement-environment"), [
    ["Operating system", system.os_pretty_name || "Unavailable"],
    ["Kernel", system.kernel || "Unavailable"],
    ["Architecture", system.architecture || "Unavailable"],
    ["Host", system.hostname || "Unavailable"],
    ["Repository", report.soul_project?.git?.dirty ? "working tree has changes" : "working tree clean"],
    ["Package managers", managers.length ? managers.map(([name]) => name).join(", ") : "none detected"],
    ["Update candidates", report.update_checks_requested ? String(updateCandidates) : "not checked"],
    ["Cleanup candidates", report.update_checks_requested ? String(cleanupCandidates) : "not checked"]
  ]);
  const runtimes = Object.entries(report.runtimes?.runtimes || {}).filter(([, value]) => value.detected);
  byId("runtime-count").textContent = String(runtimes.length); const list = byId("runtime-list"); list.replaceChildren();
  runtimes.forEach(([name, value]) => list.append(labeledRecord(name, value.version || value.path || "detected", value.check_status === "timeout" ? "is-warning" : "")));
  if (!runtimes.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No configured runtimes were detected."; list.append(empty); }
}

function renderCapabilitySummary(summary, note = "Current bounded capability assessment.") {
  if (!summary) return;
  const metrics = byId("capability-summary").children;
  metrics[0].querySelector("strong").textContent = String(summary.available ?? "—");
  metrics[1].querySelector("strong").textContent = String(summary.partial ?? "—");
  metrics[2].querySelector("strong").textContent = String(summary.missing ?? "—");
  byId("capability-state").textContent = summary.blocked ? `${summary.blocked} blocked` : "assessed";
  byId("capability-note").textContent = note;
}

function renderModelSummary(report) {
  const endpoints = Object.entries(report?.endpoints || {}); const list = byId("model-summary"); list.replaceChildren();
  let reachable = 0;
  endpoints.forEach(([name, value]) => { if (value.reachable) reachable += 1; list.append(labeledRecord(name.replaceAll("_", " "), `${value.reachable ? "reachable" : "not reachable"} · ${(value.models || []).length} model${(value.models || []).length === 1 ? "" : "s"}`, value.reachable ? "is-available" : "")); });
  if (!endpoints.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No model assessment evidence."; list.append(empty); }
  byId("model-state").textContent = `${reachable}/${endpoints.length || 0} reachable`;
}

function renderStorageRetention(report) {
  const card = byId("storage-retention-card"); card.hidden = false;
  const summary = report?.summary || {}; const memory = report?.dashboard_memory || {};
  byId("storage-retention-state").textContent = `${summary.cleanup_candidate_count || 0} reviewable`;
  renderDefinitionList(byId("storage-retention-summary"), [
    ["Observed", formatBytes(summary.observed_bytes)],
    ["Protected", formatBytes(summary.protected_bytes)],
    ["Candidates", String(summary.cleanup_candidate_count || 0)],
    ["Dashboard now", formatBytes(memory.current_bytes)],
    ["Dashboard peak", formatBytes(memory.peak_bytes)],
    ["Sampling", memory.point_in_time ? "point-in-time only" : "unavailable"]
  ]);
  const list = byId("storage-retention-categories"); list.replaceChildren();
  (report?.categories || []).forEach((category) => {
    const retention = String(category.retention || "unclassified").replaceAll("_", " ");
    const note = `${formatBytes(category.bytes)} · ${category.entry_count || 0} top-level entries · ${retention}${category.blocked ? ` · ${category.blocked}` : ""}`;
    list.append(labeledRecord(category.id.replaceAll("_", " "), note, category.retention === "protected" ? "is-available" : "is-warning"));
  });
  if (!report?.categories?.length) list.append(labeledRecord("Storage unavailable", "No bounded category evidence was returned.", "is-warning"));
  byId("storage-cleanup-scope").hidden = true;
  byId("storage-cleanup-status").textContent = "Execution is deliberately unavailable in this slice.";
}

async function previewStorageCleanup() {
  const button = byId("preview-storage-cleanup"); const status = byId("storage-cleanup-status"); button.disabled = true; status.textContent = "Binding current metadata into one exact read-only scope…";
  try {
    const envelope = await callSoul("storage_retention.cleanup.preview", { category: byId("storage-cleanup-category").value }); lifecycle(envelope);
    if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || dataOf(envelope).reason || "Cleanup preview blocked safely.");
    const data = dataOf(envelope); const output = byId("storage-cleanup-scope"); output.hidden = false; output.textContent = JSON.stringify(data, null, 2);
    status.textContent = `${data.entry_count || 0} candidate${data.entry_count === 1 ? "" : "s"} · ${formatBytes(data.total_bytes)}. No cleanup execution exists in A1.`;
  } catch (error) { status.textContent = error.message; }
  finally { button.disabled = false; }
}

function renderRecommendations(records) {
  const list = byId("recommendation-list"); list.replaceChildren(); byId("recommendation-count").textContent = String(records.length);
  records.forEach((record) => list.append(labeledRecord(record.title || "Recommendation", `${record.severity || "info"} · ${record.detail || "Review the assessed evidence."}`, record.severity === "warn" || record.severity === "blocker" ? "is-warning" : "")));
  if (!records.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No recommendations were produced for this assessment."; list.append(empty); }
}

function renderImprovementProposals(inventory) {
  const records = inventory?.records || []; const list = byId("improvement-proposal-list"); list.replaceChildren(); byId("improvement-proposal-count").textContent = String(records.length);
  records.forEach((record) => list.append(labeledRecord(record.title || record.proposal_id || "Improvement proposal", `${record.priority || "unranked"} · ${record.status || "draft"} · human review required`)));
  if (!records.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No generated improvement proposal packets."; list.append(empty); }
}

function renderSelfImprovement(data) {
  const scope = data.assessment_scope || "environment"; const report = data.assessment || {};
  byId("improvement-scope").textContent = `${scope}${data.automatic ? " · automatic" : ""}`;
  byId("storage-retention-card").hidden = scope !== "storage";
  if (scope === "environment" || scope === "updates") renderImprovementEnvironment(report);
  if (scope === "models") renderModelSummary(report);
  if (scope === "capabilities") { renderCapabilitySummary(report.summary); renderModelSummary(report.sources?.model_runtime); }
  if (scope === "storage") renderStorageRetention(report);
  if (data.cached_capabilities?.available) renderCapabilitySummary(data.cached_capabilities.summary, `Cached assessment from ${formatTime(data.cached_capabilities.generated_at)}; run Capabilities to refresh.`);
  renderRecommendations(report.recommendations || []); renderImprovementProposals(data.proposals);
}

function setAssessmentButtonsDisabled(disabled) { document.querySelectorAll("[data-assessment-scope]").forEach((button) => { button.disabled = disabled; }); }

async function loadSelfImprovement() {
  setAssessmentButtonsDisabled(true); byId("improvement-scope").textContent = "assessing"; announce("Collecting lightweight read-only environment assessment");
  try { const envelope = await callSoul("self_improvement.snapshot"); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Assessment failed safely"); renderSelfImprovement(dataOf(envelope)); await loadHostPlans(); state.improvementLoaded = true; announce("Self Assessment snapshot ready"); }
  catch (error) { byId("improvement-scope").textContent = "failed"; showError(error); }
  finally { setAssessmentButtonsDisabled(false); }
}

async function refreshSelfImprovement(scope) {
  setAssessmentButtonsDisabled(true); byId("improvement-scope").textContent = `${scope} · running`; announce(`Running bounded ${scope} assessment`);
  try {
    const signal = typeof globalThis.AbortSignal?.timeout === "function" ? globalThis.AbortSignal.timeout(35_000) : undefined;
    const envelope = await callSoul("self_improvement.refresh", { scope }, {}, { signal }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Assessment failed safely"); renderSelfImprovement(dataOf(envelope)); announce(`${scope} assessment complete`);
  }
  catch (error) { byId("improvement-scope").textContent = `${scope} · failed`; showError(new Error(error.name === "TimeoutError" ? `${scope} assessment exceeded the foreground time limit` : error.message)); }
  finally { setAssessmentButtonsDisabled(false); }
}

async function previewImprovementProposals() {
  const status = byId("improvement-proposal-status"); status.textContent = "Assessing current capability-derived candidates…";
  const envelope = await callSoul("self_improvement.proposals.preview"); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete" || !data.expected_digest) { status.textContent = envelope.errors?.[0]?.message || "Proposal preview failed safely."; return; }
  state.improvementProposalPreview = data; const list = byId("improvement-proposal-preview-list"); list.replaceChildren();
  (data.proposals || []).forEach((record) => list.append(labeledRecord(record.title || record.id, `${record.priority || "unranked"} · ${record.summary || "advisory candidate"}`)));
  if (!data.proposals?.length) list.append(labeledRecord("No new capability candidates", "Generating now will not create implementation work."));
  byId("improvement-proposal-confirm").hidden = false; prefillApprovalGate("improvement-proposal-confirmation", "execute-improvement-proposals", data.confirmation_phrase || "GENERATE_SELF_IMPROVEMENT_PROPOSALS");
  status.textContent = "Review this exact candidate set; clicking Generate writes proposal packets only.";
}

async function executeImprovementProposals() {
  if (!state.improvementProposalPreview) return; const status = byId("improvement-proposal-status"); status.textContent = "Revalidating exact assessment revision…";
  const envelope = await callSoul("self_improvement.proposals.execute", { expected_digest: state.improvementProposalPreview.expected_digest, confirmation: byId("improvement-proposal-confirmation").value }); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Generation blocked; preview again."; return; }
  renderImprovementProposals(data.proposals); status.textContent = `${data.written_count || 0} new advisory packet${data.written_count === 1 ? "" : "s"} written. Human review is still required.`;
  state.improvementProposalPreview = null; byId("improvement-proposal-confirm").hidden = true; announce("Improvement proposal generation complete");
}

function maintenanceStateLabel(status, rebootRequired = false) {
  if (rebootRequired) return "Reboot required";
  return {
    healthy: "Healthy",
    reachable: "Online",
    updates_available: "Updates available",
    attention: "Attention",
    offline: "Offline",
    external: "External"
  }[status] || "Unknown";
}

function renderMaintenanceDevice(device) {
  const rebootRequired = device.reboot?.required === true;
  const card = document.createElement("article"); card.className = "maintenance-device-card"; card.dataset.state = rebootRequired ? "reboot_required" : (device.status || "unknown");
  const inventoryOnly = device.control !== "maintenance";
  const statusOnly = device.control === "status_only" || device.facts?.management_channel === "icmp_status";
  const observedAt = device.observed_at ? new Date(device.observed_at) : null;
  const observedLabel = observedAt && !Number.isNaN(observedAt.getTime()) ? observedAt.toLocaleString() : "not recorded";
  const heading = document.createElement("header");
  const identity = document.createElement("div"); const eyebrow = document.createElement("p"); eyebrow.className = "eyebrow"; eyebrow.textContent = device.address || "address unavailable";
  const title = document.createElement("h3"); title.textContent = device.label || device.id || "Device";
  const role = document.createElement("p"); role.className = "maintenance-device-role"; role.textContent = device.role || "Managed device";
  identity.append(eyebrow, title, role);
  const stateBadge = document.createElement("span"); stateBadge.className = "maintenance-state-badge"; stateBadge.textContent = maintenanceStateLabel(device.status, rebootRequired);
  heading.append(identity, stateBadge);

  if (statusOnly) {
    card.classList.add("maintenance-device-card--status-only");
    role.remove();
    const refresh = document.createElement("button"); refresh.type = "button"; refresh.className = "quiet-button maintenance-device-refresh";
    refresh.textContent = "Refresh";
    refresh.addEventListener("click", () => refreshMaintenanceDevice(device.id, refresh));
    const controls = document.createElement("div"); controls.className = "maintenance-status-only-controls"; controls.append(stateBadge, refresh);
    heading.append(controls);

    const evidence = document.createElement("div"); evidence.className = "maintenance-status-only-evidence";
    const evidenceItems = [
      ["Checked", observedLabel, "observed"],
      ["Status probe", device.reachable ? "active" : "unavailable", device.reachable ? "active" : "failed"],
      ["Network reachability", device.reachable ? "active" : "unavailable", device.reachable ? "active" : "failed"]
    ];
    evidenceItems.forEach(([label, value, stateName]) => {
      const item = document.createElement("span"); item.dataset.state = stateName;
      const strong = document.createElement("strong"); strong.textContent = label;
      item.append(strong, document.createTextNode(` · ${value}`)); evidence.append(item);
    });
    card.append(heading, evidence);
    return card;
  }

  const metrics = document.createElement("dl"); metrics.className = "maintenance-device-metrics";
  const packageManagers = Array.isArray(device.facts?.package_managers) ? device.facts.package_managers : [];
  const readOnlyStatus = inventoryOnly && device.facts?.status_adapter === "dnf5_read_only";
  const facts = [
    ["Platform", device.os || "unavailable"],
    ["Version", device.version || "unavailable"],
    ["Updates", inventoryOnly && !readOnlyStatus ? `${statusOnly ? "provider-managed" : "not queried"} · inventory only` : `${device.updates?.total ?? 0} total · ${device.updates?.native ?? 0} native · ${device.updates?.aur ?? 0} AUR · ${device.updates?.flatpak ?? 0} Flatpak`],
    ["Kernel", inventoryOnly && !readOnlyStatus ? `${device.kernel?.running || "not queried"} · inventory only` : `${device.kernel?.running || "unavailable"}${device.kernel?.update_required ? ` → ${device.kernel?.available || "newer available"}` : " · current"}`],
    ["Reboot", inventoryOnly ? (device.reboot?.reason || "not assessed · inventory only") : (device.reboot?.required ? (device.reboot?.reason || "required") : "not indicated")],
    ["Checked", observedLabel]
  ];
  facts.forEach(([label, value]) => {
    const row = document.createElement("div"); const dt = document.createElement("dt"); const dd = document.createElement("dd");
    dt.textContent = label; dd.textContent = String(value); row.append(dt, dd); metrics.append(row);
  });

  const services = document.createElement("div"); services.className = "maintenance-service-list";
  const channel = document.createElement("span"); channel.dataset.state = device.reachable ? "active" : "failed";
  channel.textContent = `${statusOnly ? "Status probe" : (inventoryOnly ? "Inventory probe" : "Maintenance channel")} · ${device.reachable ? "active" : "unavailable"}`; services.append(channel);
  packageManagers.forEach((manager) => {
    const chip = document.createElement("span"); chip.dataset.state = "active"; chip.textContent = `${manager} detected`; services.append(chip);
  });
  (device.services || []).forEach((service) => {
    const chip = document.createElement("span"); chip.dataset.state = service.state || "unknown"; chip.textContent = `${service.label} · ${service.state || "unknown"}`; services.append(chip);
  });
  const piholeContainer = device.facts?.pihole_container;
  if (piholeContainer) {
    const chip = document.createElement("span"); chip.dataset.state = piholeContainer.status === "running" ? "active" : "failed";
    chip.textContent = `LXC ${piholeContainer.id} · ${piholeContainer.status || "unknown"}`; services.append(chip);
  }
  const actions = document.createElement("div"); actions.className = "maintenance-device-actions";
  const refresh = document.createElement("button"); refresh.type = "button"; refresh.className = "gate-button maintenance-device-refresh";
  refresh.textContent = "Refresh";
  refresh.addEventListener("click", () => refreshMaintenanceDevice(device.id, refresh));
  actions.append(refresh);
  if (inventoryOnly) {
    const notice = document.createElement("p"); notice.className = "maintenance-status-only";
    notice.textContent = statusOnly
      ? "Status only · lifecycle and mutation remain provider-managed"
      : (readOnlyStatus
        ? "DNF5 evidence only · maintenance and reboot authority remain disabled"
        : "Inventory only · discovered capabilities grant no mutation authority");
    actions.append(notice);
  } else {
    ["maintenance", "reboot"].forEach((action) => {
      const button = document.createElement("button"); button.type = "button"; button.className = action === "reboot" ? "gate-button maintenance-reboot-button" : "gate-button gate-button--gold";
      button.textContent = action === "reboot" ? "Reboot" : "Maintenance";
      button.disabled = !device.reachable;
      button.addEventListener("click", () => openMaintenanceDeviceAction(device.id, action));
      actions.append(button);
    });
  }
  card.append(heading, metrics, services, actions);
  return card;
}

async function refreshMaintenanceDevice(deviceId, button) {
  const status = byId("maintenance-fleet-status");
  const originalLabel = button.textContent;
  button.disabled = true; button.textContent = "Refreshing…";
  status.textContent = `Refreshing bounded evidence for ${deviceId}…`;
  try {
    const signal = typeof globalThis.AbortSignal?.timeout === "function" ? globalThis.AbortSignal.timeout(45_000) : undefined;
    const envelope = await callSoul("maintenance.fleet.device.refresh", { device_id: deviceId }, {}, { signal }); lifecycle(envelope);
    const data = dataOf(envelope);
    if (envelope.lifecycle_state !== "complete" || !Array.isArray(data.devices)) throw new Error(envelope.errors?.[0]?.message || data.reason || "Device status refresh failed safely.");
    renderMaintenanceFleet(data);
    const refreshed = data.devices.find((device) => device.id === data.refreshed_device_id);
    status.textContent = `${refreshed?.label || deviceId} checked ${new Date(refreshed?.observed_at || data.collected_at).toLocaleString()} · only this device was probed.`;
    announce(`${refreshed?.label || "Device"} status refreshed`);
  } catch (error) {
    button.disabled = false; button.textContent = originalLabel;
    status.textContent = error.name === "TimeoutError" ? "Device refresh exceeded its foreground time limit; no background process remains." : error.message;
  }
}

function renderMaintenanceTopology(topology) {
  const canvas = byId("maintenance-topology"); canvas.replaceChildren();
  const nodes = new Map((topology?.nodes || []).map((node) => [node.id, node]));
  const network = topology?.network || {};
  const makeNode = (node, markerText) => {
    const block = document.createElement("div"); block.className = "maintenance-topology-node"; block.dataset.state = node.status || "unknown";
    const marker = document.createElement("span"); marker.textContent = markerText;
    const copy = document.createElement("div"); const strong = document.createElement("strong"); strong.textContent = node.label; const role = document.createElement("small"); role.textContent = node.role;
    const address = document.createElement("code"); address.textContent = node.address;
    copy.append(strong, role, address); block.append(marker, copy);
    return block;
  };

  const map = document.createElement("div"); map.className = "maintenance-network-map";
  const cloudTier = document.createElement("section"); cloudTier.className = "maintenance-network-tier maintenance-network-cloud";
  const cloudHeading = document.createElement("div"); cloudHeading.className = "maintenance-network-tier-heading";
  const cloudEyebrow = document.createElement("p"); cloudEyebrow.className = "eyebrow"; cloudEyebrow.textContent = "External network";
  const cloudTitle = document.createElement("strong"); cloudTitle.textContent = "WAN & provider cloud";
  cloudHeading.append(cloudEyebrow, cloudTitle);
  const cloudNodes = document.createElement("div"); cloudNodes.className = "maintenance-network-cloud-nodes";
  (network.cloud_node_ids || ["internet"]).forEach((id) => {
    const node = nodes.get(id); if (node) cloudNodes.append(makeNode(node, "WAN"));
  });
  cloudTier.append(cloudHeading, cloudNodes);

  const uplink = document.createElement("div"); uplink.className = "maintenance-network-uplink";
  const uplinkLine = document.createElement("i"); uplinkLine.setAttribute("aria-hidden", "true");
  const uplinkLabel = document.createElement("span"); uplinkLabel.textContent = "Default route · WAN uplink";
  uplink.append(uplinkLine, uplinkLabel);

  const gatewayTier = document.createElement("section"); gatewayTier.className = "maintenance-network-tier maintenance-network-gateway";
  const gatewayHeading = document.createElement("div"); gatewayHeading.className = "maintenance-network-tier-heading";
  const gatewayEyebrow = document.createElement("p"); gatewayEyebrow.className = "eyebrow"; gatewayEyebrow.textContent = "Network edge";
  const gatewayTitle = document.createElement("strong"); gatewayTitle.textContent = "Default gateway";
  gatewayHeading.append(gatewayEyebrow, gatewayTitle);
  const gatewayNode = nodes.get(network.gateway_node_id);
  if (gatewayNode) gatewayTier.append(gatewayHeading, makeNode(gatewayNode, "GW"));
  else gatewayTier.append(gatewayHeading);

  const lanUplink = document.createElement("div"); lanUplink.className = "maintenance-network-uplink maintenance-network-uplink--lan";
  const lanLine = document.createElement("i"); lanLine.setAttribute("aria-hidden", "true");
  const lanLabel = document.createElement("span"); lanLabel.textContent = "Local switching & routing";
  lanUplink.append(lanLine, lanLabel);

  const lan = document.createElement("section"); lan.className = "maintenance-network-lan";
  const lanHeading = document.createElement("header");
  const lanIdentity = document.createElement("div"); const lanEyebrow = document.createElement("p"); lanEyebrow.className = "eyebrow"; lanEyebrow.textContent = "Local network";
  const lanTitle = document.createElement("strong"); lanTitle.textContent = network.subnet || "Subnet unavailable";
  lanIdentity.append(lanEyebrow, lanTitle);
  const lanInterface = document.createElement("code"); lanInterface.textContent = network.interface && network.interface !== "unavailable" ? `interface ${network.interface}` : "route evidence unavailable";
  lanHeading.append(lanIdentity, lanInterface);
  const lanNodes = document.createElement("div"); lanNodes.className = "maintenance-network-lan-nodes";
  (network.lan_node_ids || []).forEach((id) => {
    const node = nodes.get(id); if (node) lanNodes.append(makeNode(node, "LAN"));
  });
  if (!lanNodes.childElementCount) {
    const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No local device nodes are available.";
    lanNodes.append(empty);
  }
  lan.append(lanHeading, lanNodes);
  map.append(cloudTier, uplink, gatewayTier, lanUplink, lan);

  const relationships = (topology?.edges || []).filter((edge) => !["route", "wan"].includes(edge.kind));
  const relationshipSection = document.createElement("section"); relationshipSection.className = "maintenance-topology-relationships";
  const relationshipHeading = document.createElement("div"); relationshipHeading.className = "maintenance-network-tier-heading";
  const relationshipEyebrow = document.createElement("p"); relationshipEyebrow.className = "eyebrow"; relationshipEyebrow.textContent = "Operational relationships";
  const relationshipTitle = document.createElement("strong"); relationshipTitle.textContent = "Management, services & planned paths";
  relationshipHeading.append(relationshipEyebrow, relationshipTitle);
  const links = document.createElement("div"); links.className = "maintenance-topology-links";
  relationships.forEach((edge) => {
    const link = document.createElement("div"); link.dataset.kind = edge.kind || "link";
    const route = document.createElement("span"); route.textContent = `${nodes.get(edge.from)?.label || edge.from} → ${nodes.get(edge.to)?.label || edge.to}`;
    const label = document.createElement("strong"); label.textContent = edge.label || "connected";
    link.append(route, label); links.append(link);
  });
  relationshipSection.append(relationshipHeading, links);
  canvas.append(map, relationshipSection);
}

function renderMaintenanceFleet(data) {
  state.maintenanceFleet = data;
  const summary = data.summary || {};
  byId("maintenance-fleet-reachable").textContent = `${summary.reachable_count ?? 0} / ${summary.device_count ?? 0}`;
  byId("maintenance-fleet-updates").textContent = String(summary.updates_available ?? 0);
  byId("maintenance-fleet-kernels").textContent = String(summary.kernel_attention_count ?? 0);
  byId("maintenance-fleet-reboots").textContent = String(summary.reboot_required_count ?? 0);
  const grid = byId("maintenance-device-grid"); grid.replaceChildren();
  (data.devices || []).forEach((device) => grid.append(renderMaintenanceDevice(device)));
  if (!data.devices?.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No device evidence returned."; grid.append(empty); }
  renderMaintenanceTopology(data.topology);
  state.maintenanceFleetLoaded = true;
}

async function loadMaintenanceFleetSnapshot() {
  const status = byId("maintenance-fleet-status");
  try {
    const envelope = await callSoul("maintenance.fleet.snapshot"); lifecycle(envelope);
    const data = dataOf(envelope);
    if (data.available === false || !Array.isArray(data.devices)) {
      status.textContent = data.reason || "No persisted fleet status exists yet. Collect one now.";
      return;
    }
    renderMaintenanceFleet(data);
    status.textContent = `Persisted snapshot from ${new Date(data.collected_at).toLocaleString()} · collect now to replace it.`;
  } catch (error) {
    status.textContent = error.message;
  }
}

async function loadMaintenanceFleet() {
  const button = byId("refresh-maintenance-fleet"); const status = byId("maintenance-fleet-status");
  button.disabled = true; status.textContent = "Collecting bounded workstation, infrastructure, appliance, package, kernel, and service evidence…";
  try {
    const signal = typeof globalThis.AbortSignal?.timeout === "function" ? globalThis.AbortSignal.timeout(120_000) : undefined;
    const envelope = await callSoul("maintenance.fleet.status", {}, {}, { signal }); lifecycle(envelope);
    const data = dataOf(envelope);
    if (envelope.lifecycle_state !== "complete" || !Array.isArray(data.devices)) throw new Error(envelope.errors?.[0]?.message || data.reason || "Fleet status failed safely.");
    renderMaintenanceFleet(data);
    status.textContent = `Collected and persisted ${new Date(data.collected_at).toLocaleString()} · workstation pacman and remote APT counts use current cached metadata.`;
    announce("Maintenance fleet status ready");
  } catch (error) {
    status.textContent = error.name === "TimeoutError" ? "Fleet collection exceeded its foreground time limit; no background process remains." : error.message;
  } finally {
    button.disabled = false;
  }
}

function maintenanceDiscoveryError(envelope, fallback) {
  return envelope.errors?.[0]?.message || envelope.reason || dataOf(envelope).reason || fallback;
}

function resetMaintenanceEnrollmentPreview() {
  state.maintenanceEnrollmentPreview = null;
  byId("maintenance-enrollment-confirm").hidden = true;
  byId("maintenance-enrollment-scope").textContent = "";
}

function selectMaintenanceCandidate(candidate) {
  resetMaintenanceEnrollmentPreview();
  resetMaintenanceIgnorePanel();
  state.maintenanceEnrollmentCandidate = candidate;
  state.maintenanceRemovalPreview = null;
  byId("maintenance-removal-panel").hidden = true;
  byId("maintenance-enrollment-address").value = candidate.address;
  byId("maintenance-enrollment-label").value = candidate.known_device || "";
  byId("maintenance-enrollment-mode").value = "status_only";
  byId("maintenance-enrollment-policy").value = "fixed";
  byId("maintenance-enrollment-mac").value = candidate.identity_hints?.mac_address || "";
  byId("maintenance-enrollment-policy").querySelector('option[value="dhcp_tracked"]').disabled = !candidate.identity_hints?.mac_address;
  byId("maintenance-enrollment-policy").disabled = false;
  byId("maintenance-enrollment-ssh-alias").value = "";
  byId("maintenance-enrollment-ssh-row").hidden = true;
  byId("maintenance-enrollment-heading").textContent = `Review ${candidate.address}`;
  byId("maintenance-enrollment-panel").hidden = false;
  byId("maintenance-enrollment-status").textContent = candidate.state === "already_configured"
    ? "This address is already represented. Enrollment will be blocked unless the existing record is removed or configuration changes."
    : "Choose a label and inventory boundary, then preview the exact private record.";
  byId("maintenance-enrollment-label").focus();
}

function resetMaintenanceIgnorePanel() {
  state.maintenanceIgnoreCandidate = null;
  state.maintenanceIgnorePreview = null;
  state.maintenanceIgnoreMode = null;
  byId("maintenance-ignore-panel").hidden = true;
  byId("maintenance-ignore-scope").hidden = true;
  byId("maintenance-ignore-scope").textContent = "";
  byId("execute-maintenance-ignore").disabled = true;
}

function selectMaintenanceIgnoreCandidate(candidate) {
  resetMaintenanceEnrollmentPreview(); byId("maintenance-enrollment-panel").hidden = true;
  state.maintenanceIgnoreCandidate = candidate;
  state.maintenanceIgnorePreview = null;
  state.maintenanceIgnoreMode = "ignore";
  byId("maintenance-ignore-heading").textContent = `Ignore ${candidate.address}`;
  byId("maintenance-ignore-description").textContent = "Exclude this reviewed identity from future candidate lists. It remains visible and reversible.";
  byId("maintenance-ignore-label-row").hidden = false;
  const vendor = candidate.identity_hints?.vendor;
  byId("maintenance-ignore-label").value = vendor && vendor !== "Locally administered address" ? vendor : `Device at ${candidate.address}`;
  byId("preview-maintenance-ignore").hidden = false;
  byId("execute-maintenance-ignore").textContent = "Ignore reviewed candidate";
  byId("execute-maintenance-ignore").disabled = true;
  byId("maintenance-ignore-status").textContent = "Name this private exclusion, then preview its exact MAC-first or IP-fallback identity.";
  byId("maintenance-ignore-panel").hidden = false;
  byId("maintenance-ignore-label").focus();
}

function renderMaintenanceDiscoveryCandidates(candidates) {
  state.maintenanceDiscoveryCandidates = candidates;
  byId("maintenance-candidate-count").textContent = String(candidates.length);
  const list = byId("maintenance-discovery-candidates"); list.replaceChildren();
  if (!candidates.length) {
    const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No reachable candidates were reported inside this scan."; list.append(empty); return;
  }
  candidates.forEach((candidate) => {
    const row = document.createElement("article"); row.className = "maintenance-discovery-item";
    const copy = document.createElement("div"); const title = document.createElement("strong"); title.textContent = candidate.address;
    const hints = candidate.identity_hints || {};
    const identity = [hints.vendor, hints.mac_address, hints.interface, ...(hints.neighbor_state || [])].filter(Boolean);
    const detail = document.createElement("small"); detail.textContent = identity.length
      ? `Untrusted candidate · ${identity.join(" · ")}`
      : "Untrusted candidate · no local identity hints available";
    copy.append(title, detail);
    const actions = document.createElement("div"); actions.className = "maintenance-discovery-item-actions";
    const review = document.createElement("button"); review.type = "button"; review.className = "quiet-button"; review.textContent = "Review";
    review.addEventListener("click", () => selectMaintenanceCandidate(candidate));
    const ignore = document.createElement("button"); ignore.type = "button"; ignore.className = "quiet-button"; ignore.textContent = "Ignore";
    ignore.addEventListener("click", () => selectMaintenanceIgnoreCandidate(candidate));
    actions.append(review, ignore); row.append(copy, actions); list.append(row);
  });
}

function removeMaintenanceDiscoveryCandidate(candidate) {
  const address = String(candidate?.address || "");
  const remaining = (state.maintenanceDiscoveryCandidates || []).filter((entry) => String(entry.address || "") !== address);
  renderMaintenanceDiscoveryCandidates(remaining);
  return remaining.length;
}

function maintenanceIgnoreParameters() {
  const candidate = state.maintenanceIgnoreCandidate || {};
  return {
    address: candidate.address,
    label: byId("maintenance-ignore-label").value.trim(),
    subnet: candidate.subnet,
    mac_address: candidate.identity_hints?.mac_address || "",
    vendor: candidate.identity_hints?.vendor || ""
  };
}

async function previewMaintenanceIgnore() {
  if (!state.maintenanceIgnoreCandidate) return;
  const status = byId("maintenance-ignore-status"); byId("preview-maintenance-ignore").disabled = true;
  try {
    const envelope = await callSoul("maintenance.discovery.ignore.preview", maintenanceIgnoreParameters());
    if (envelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(envelope, "Ignore preview failed safely."));
    const data = dataOf(envelope); state.maintenanceIgnorePreview = data;
    byId("maintenance-ignore-scope").textContent = JSON.stringify(data.device, null, 2);
    byId("maintenance-ignore-scope").hidden = false;
    byId("execute-maintenance-ignore").disabled = false;
    status.textContent = "Review this private exclusion. The device is not contacted and receives no authority.";
  } catch (error) { status.textContent = error.message; }
  finally { byId("preview-maintenance-ignore").disabled = false; }
}

async function previewMaintenanceRestore(record) {
  resetMaintenanceIgnorePanel();
  state.maintenanceIgnoreMode = "restore";
  byId("maintenance-ignore-heading").textContent = `Restore ${record.label}`;
  byId("maintenance-ignore-description").textContent = "Remove this private exclusion so the identity may appear in a future explicit scan.";
  byId("maintenance-ignore-label-row").hidden = true;
  byId("preview-maintenance-ignore").hidden = true;
  byId("execute-maintenance-ignore").textContent = "Restore reviewed candidate";
  byId("maintenance-ignore-panel").hidden = false;
  const status = byId("maintenance-ignore-status"); status.textContent = "Binding the current ignored-device record…";
  try {
    const envelope = await callSoul("maintenance.discovery.restore.preview", { identity_key: record.identity_key });
    if (envelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(envelope, "Restore preview failed safely."));
    const data = dataOf(envelope); state.maintenanceIgnorePreview = data;
    byId("maintenance-ignore-scope").textContent = JSON.stringify(data.device, null, 2);
    byId("maintenance-ignore-scope").hidden = false;
    byId("execute-maintenance-ignore").disabled = false;
    status.textContent = "Review this exact exclusion removal. No device is contacted.";
  } catch (error) { status.textContent = error.message; }
}

async function executeMaintenanceIgnoreMutation() {
  const preview = state.maintenanceIgnorePreview;
  if (!preview || !state.maintenanceIgnoreMode) return;
  const button = byId("execute-maintenance-ignore"); const status = byId("maintenance-ignore-status"); button.disabled = true;
  try {
    const mode = state.maintenanceIgnoreMode;
    const actedCandidate = state.maintenanceIgnoreCandidate;
    const operation = mode === "ignore"
      ? "maintenance.discovery.ignore.execute"
      : "maintenance.discovery.restore.execute";
    const parameters = mode === "ignore"
      ? Object.assign(maintenanceIgnoreParameters(), { confirmation: preview.confirmation_phrase, expected_digest: preview.expected_digest })
      : { identity_key: preview.device.identity_key, confirmation: preview.confirmation_phrase, expected_digest: preview.expected_digest };
    const envelope = await callSoul(operation, parameters);
    if (envelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(envelope, "Ignored-device mutation failed safely."));
    const remainingCount = mode === "ignore"
      ? removeMaintenanceDiscoveryCandidate(actedCandidate)
      : (state.maintenanceDiscoveryCandidates || []).length;
    resetMaintenanceIgnorePanel(); await loadMaintenanceDiscovery();
    byId("maintenance-discovery-status").textContent = mode === "ignore"
      ? `Candidate ignored. ${remainingCount} candidate${remainingCount === 1 ? "" : "s"} remain from the current scan.`
      : `Ignored identity restored. ${remainingCount} current candidate${remainingCount === 1 ? "" : "s"} preserved; scan only if you want fresh discovery evidence.`;
  } catch (error) { status.textContent = error.message; button.disabled = false; }
}

function renderMaintenanceIgnored(records) {
  state.maintenanceIgnoredDevices = records;
  byId("maintenance-ignored-count").textContent = String(records.length);
  const list = byId("maintenance-discovery-ignored"); list.replaceChildren();
  if (!records.length) {
    const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No devices are excluded from discovery."; list.append(empty); return;
  }
  records.forEach((record) => {
    const row = document.createElement("article"); row.className = "maintenance-discovery-item";
    const copy = document.createElement("div"); const title = document.createElement("strong"); title.textContent = record.label;
    const detail = document.createElement("small"); detail.textContent = `${record.mac_address || record.address} · ${record.vendor || "vendor unavailable"} · ${record.subnet}`;
    copy.append(title, detail);
    const button = document.createElement("button"); button.type = "button"; button.className = "quiet-button"; button.textContent = "Restore";
    button.addEventListener("click", () => previewMaintenanceRestore(record));
    row.append(copy, button); list.append(row);
  });
}

async function previewMaintenanceRemoval(record) {
  const status = byId("maintenance-removal-status");
  state.maintenanceRemovalPreview = null; byId("maintenance-removal-panel").hidden = false;
  byId("maintenance-removal-heading").textContent = `Remove ${record.label}`;
  status.textContent = "Binding the current private registry record…";
  try {
    const envelope = await callSoul("maintenance.discovery.remove.preview", { device_id: record.id });
    if (envelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(envelope, "Removal preview failed safely."));
    const data = dataOf(envelope); state.maintenanceRemovalPreview = data;
    byId("maintenance-removal-scope").textContent = JSON.stringify(data.device, null, 2);
    status.textContent = "The gold-free destructive gate removes only this local registry record; the device is untouched.";
  } catch (error) { status.textContent = error.message; }
}

function renderMaintenanceDiscoveryRegistry(records) {
  state.maintenanceDiscoveryRegistry = records;
  byId("maintenance-registry-count").textContent = String(records.length);
  const ignoredCount = state.maintenanceIgnoredDevices?.length || 0;
  byId("maintenance-discovery-summary").textContent = `${records.length} enrolled · ${ignoredCount} ignored · discovery remains manual`;
  const list = byId("maintenance-discovery-registry"); list.replaceChildren();
  if (!records.length) {
    const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No portable devices enrolled on this installation."; list.append(empty); return;
  }
  records.forEach((record) => {
    const row = document.createElement("article"); row.className = "maintenance-discovery-item";
    const copy = document.createElement("div"); const title = document.createElement("strong"); title.textContent = record.label;
    const managers = Array(record.facts?.package_managers).join(" · ");
    const addressPolicy = record.address_policy === "dhcp_tracked" ? `DHCP tracked · ${record.mac_address}` : "fixed address";
    const detail = document.createElement("small"); detail.textContent = `${record.address} · ${record.connection_mode === "ssh" ? "SSH inventory" : "status only"} · ${addressPolicy}${managers ? ` · ${managers}` : ""}`;
    copy.append(title, detail);
    const button = document.createElement("button"); button.type = "button"; button.className = "quiet-button"; button.textContent = "Remove";
    button.addEventListener("click", () => previewMaintenanceRemoval(record));
    row.append(copy, button); list.append(row);
  });
}

async function loadMaintenanceDiscovery() {
  const status = byId("maintenance-discovery-status");
  try {
    const [dependencyEnvelope, registryEnvelope, ignoredEnvelope] = await Promise.all([
      callSoul("maintenance.discovery.status"),
      callSoul("maintenance.discovery.registry"),
      callSoul("maintenance.discovery.ignored")
    ]);
    const dependency = dataOf(dependencyEnvelope);
    byId("maintenance-discovery-dependency").textContent = dependency.available ? "Discovery ready" : "nmap required";
    byId("maintenance-discovery-dependency").dataset.state = dependency.available ? "healthy" : "attention";
    const subnetInput = byId("maintenance-discovery-subnet");
    if (!subnetInput.value.trim() && dependency.last_subnet) subnetInput.value = dependency.last_subnet;
    if (registryEnvelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(registryEnvelope, "Private registry could not be read."));
    if (ignoredEnvelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(ignoredEnvelope, "Ignored-device list could not be read."));
    renderMaintenanceIgnored(dataOf(ignoredEnvelope).devices || []);
    renderMaintenanceDiscoveryRegistry(dataOf(registryEnvelope).devices || []);
    status.textContent = dependency.available
      ? "Ready for one explicit private-subnet scan. No scan runs automatically."
      : "Install nmap, then refresh this inventory surface. Enrollment remains unavailable.";
  } catch (error) { status.textContent = error.message; }
}

async function scanMaintenanceSubnet() {
  const button = byId("scan-maintenance-subnet"); const status = byId("maintenance-discovery-status");
  button.disabled = true; resetMaintenanceEnrollmentPreview(); byId("maintenance-enrollment-panel").hidden = true;
  status.textContent = "Running one bounded foreground host-discovery scan…";
  try {
    const signal = typeof globalThis.AbortSignal?.timeout === "function" ? globalThis.AbortSignal.timeout(35_000) : undefined;
    const envelope = await callSoul("maintenance.discovery.scan", { subnet: byId("maintenance-discovery-subnet").value.trim() }, {}, { signal });
    if (envelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(envelope, "Subnet scan failed safely."));
    const data = dataOf(envelope); renderMaintenanceDiscoveryCandidates(data.candidates || []);
    const excluded = data.represented_count || 0;
    const ignored = data.ignored_count || 0;
    status.textContent = `${data.candidate_count || 0} unenrolled candidate${data.candidate_count === 1 ? "" : "s"} returned from ${data.subnet}${excluded ? ` · ${excluded} already represented and excluded` : ""}${ignored ? ` · ${ignored} ignored` : ""}. Results remain in this page session only.`;
  } catch (error) {
    status.textContent = error.name === "TimeoutError" ? "Discovery exceeded its foreground time limit; no background scan remains." : error.message;
  } finally { button.disabled = false; }
}

function maintenanceEnrollmentParameters() {
  const candidate = state.maintenanceEnrollmentCandidate || {};
  return {
    address: byId("maintenance-enrollment-address").value,
    label: byId("maintenance-enrollment-label").value.trim(),
    mode: byId("maintenance-enrollment-mode").value,
    ssh_alias: byId("maintenance-enrollment-ssh-alias").value.trim(),
    address_policy: byId("maintenance-enrollment-policy").value,
    subnet: candidate.subnet || "",
    mac_address: byId("maintenance-enrollment-mac").value
  };
}

async function previewMaintenanceEnrollment() {
  const button = byId("preview-maintenance-enrollment"); const status = byId("maintenance-enrollment-status");
  button.disabled = true; resetMaintenanceEnrollmentPreview(); status.textContent = "Collecting bounded reachability and capability evidence…";
  try {
    const envelope = await callSoul("maintenance.discovery.enroll.preview", maintenanceEnrollmentParameters());
    if (envelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(envelope, "Enrollment preview failed safely."));
    const data = dataOf(envelope); state.maintenanceEnrollmentPreview = data;
    byId("maintenance-enrollment-scope").textContent = JSON.stringify(data.device, null, 2);
    byId("maintenance-enrollment-confirm").hidden = false;
    status.textContent = "Review the exact inventory-only record. Clicking Enroll supplies authority for this private registry write only.";
  } catch (error) { status.textContent = error.message; }
  finally { button.disabled = false; }
}

async function executeMaintenanceEnrollment() {
  if (!state.maintenanceEnrollmentPreview) return;
  const button = byId("execute-maintenance-enrollment"); const status = byId("maintenance-enrollment-status");
  button.disabled = true; status.textContent = "Revalidating the candidate and exact private record…";
  try {
    const envelope = await callSoul("maintenance.discovery.enroll.execute", Object.assign(maintenanceEnrollmentParameters(), {
      confirmation: state.maintenanceEnrollmentPreview.confirmation_phrase,
      expected_digest: state.maintenanceEnrollmentPreview.expected_digest
    }));
    if (envelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(envelope, "Enrollment was blocked safely."));
    const actedCandidate = state.maintenanceEnrollmentCandidate;
    const remainingCount = removeMaintenanceDiscoveryCandidate(actedCandidate);
    status.textContent = `${dataOf(envelope).device.label} enrolled for inventory only. No maintenance authority was granted.`;
    resetMaintenanceEnrollmentPreview(); state.maintenanceEnrollmentCandidate = null; byId("maintenance-enrollment-panel").hidden = true;
    await loadMaintenanceDiscovery(); await loadMaintenanceFleet();
    byId("maintenance-discovery-status").textContent = `Enrollment complete. ${remainingCount} candidate${remainingCount === 1 ? "" : "s"} remain from the current scan.`;
  } catch (error) { status.textContent = error.message; }
  finally { button.disabled = false; }
}

async function executeMaintenanceRemoval() {
  if (!state.maintenanceRemovalPreview) return;
  const button = byId("execute-maintenance-removal"); const status = byId("maintenance-removal-status");
  button.disabled = true; status.textContent = "Revalidating the exact private registry record…";
  try {
    const preview = state.maintenanceRemovalPreview;
    const envelope = await callSoul("maintenance.discovery.remove.execute", {
      device_id: preview.device.device_id,
      confirmation: preview.confirmation_phrase,
      expected_digest: preview.expected_digest
    });
    if (envelope.lifecycle_state !== "complete") throw new Error(maintenanceDiscoveryError(envelope, "Removal was blocked safely."));
    state.maintenanceRemovalPreview = null; byId("maintenance-removal-panel").hidden = true;
    resetMaintenanceEnrollmentPreview(); byId("maintenance-enrollment-panel").hidden = true;
    await loadMaintenanceDiscovery(); await loadMaintenanceFleet();
    const remainingCount = (state.maintenanceDiscoveryCandidates || []).length;
    byId("maintenance-discovery-status").textContent = `${dataOf(envelope).removed_device.label} removed from the private inventory registry; the device was not contacted. ${remainingCount} current candidate${remainingCount === 1 ? "" : "s"} preserved; scan only to rediscover the removed device.`;
  } catch (error) { status.textContent = error.message; }
  finally { button.disabled = false; }
}

function maintenanceDeviceDialogDetails(plan) {
  const details = byId("maintenance-device-dialog-details"); details.replaceChildren();
  const rows = [
    ["Device", `${plan.device_label || "Workstation"}${plan.address ? ` · ${plan.address}` : ""}`],
    ["Action", plan.action || "maintenance"],
    ["Scope", plan.fleet_wide === false ? "one device only" : "reviewed local workstation transaction"],
    ["Automatic retry", "none"]
  ];
  if (canonicalMaintenanceDeviceId(plan.device_id) === "workstation") {
    rows.push(["Authentication", plan.authority_mode === "root_owned_passwordless" && plan.one_authentication_required === false
      ? "A4 fixed-operation authority · no password prompt"
      : "one native sudo prompt"]);
  }
  rows.forEach(([label, value]) => details.append(labeledRecord(label, value)));
  (plan.commands || []).forEach((command, index) => details.append(labeledRecord(`Fixed step ${index + 1}`, (command.argv || []).join(" "))));
  (plan.readiness || []).forEach((check, index) => {
    const target = check.ssh_alias ? `${check.ssh_alias} → ` : "";
    details.append(labeledRecord(`Fixed verification ${index + 1}`, `${check.label || "Readiness"} · ${target}${(check.argv || []).join(" ")}`));
  });
  (plan.impact || []).forEach((impact) => details.append(labeledRecord("Dependency impact", impact)));
  const blockers = plan.preflight?.live_blockers || plan.preflight?.a3_blockers || plan.preflight?.blockers || [];
  blockers.forEach((blocker) => details.append(labeledRecord("Blocker", blocker)));
}

function canonicalMaintenanceDeviceId(deviceId) {
  return deviceId === "maven" ? "workstation" : deviceId;
}

function maintenanceDeviceLabel(deviceId) {
  const canonicalId = canonicalMaintenanceDeviceId(deviceId);
  return state.maintenanceFleet?.devices?.find((device) => canonicalMaintenanceDeviceId(device.id) === canonicalId)?.label
    || ({ workstation: "Workstation", forge: "Forge", pihole: "Pi-hole" }[canonicalId])
    || canonicalId;
}

async function openMaintenanceDeviceAction(deviceId, action) {
  deviceId = canonicalMaintenanceDeviceId(deviceId);
  const dialog = byId("maintenance-device-dialog"); const status = byId("maintenance-device-dialog-status");
  state.maintenanceDevicePreview = null;
  byId("maintenance-device-confirmation").value = "";
  byId("maintenance-device-confirmation-row").hidden = true;
  byId("maintenance-workstation-evidence-actions").hidden = true;
  byId("execute-maintenance-device-action").disabled = true;
  const deviceLabel = maintenanceDeviceLabel(deviceId);
  byId("maintenance-device-dialog-title").textContent = `${action === "reboot" ? "Reboot" : "Maintain"} ${deviceLabel}`;
  byId("refresh-maintenance-device-evidence").textContent = `Refresh ${deviceLabel} evidence`;
  byId("recheck-maintenance-device-preflight").textContent = `Recheck ${deviceLabel} preflight`;
  if (!dialog.open) dialog.showModal();
  status.textContent = "Collecting a fresh device-scoped preview…";
  try {
    let envelope;
    if (deviceId === "workstation") {
      envelope = await callSoul(action === "maintenance" ? "maintenance.execution.preview" : "maintenance.reboot_restore.preview", { force_database_refresh: "false" });
    } else {
      envelope = await callSoul("maintenance.device.preview", { device_id: deviceId, action });
    }
    lifecycle(envelope);
    const data = dataOf(envelope); const plan = data.plan;
    if (!plan) throw new Error(envelope.errors?.[0]?.message || "Device preview failed safely.");
    const normalizedPlan = deviceId === "workstation"
      ? Object.assign({}, plan, { device_id: "workstation", device_label: deviceLabel, action, fleet_wide: false, impact: [] })
      : plan;
    maintenanceDeviceDialogDetails(normalizedPlan);
    byId("maintenance-workstation-evidence-actions").hidden = deviceId !== "workstation";
    state.maintenanceDevicePreview = { deviceId, action, data, plan: normalizedPlan };
    const available = deviceId === "workstation" ? plan.execution_available === true : plan.live_execution_enabled === true;
    const confirmation = data.confirmation || plan.confirmation;
    byId("maintenance-device-confirmation-phrase").textContent = confirmation || "—";
    byId("maintenance-device-confirmation-row").hidden = false;
    const blockers = plan.preflight?.live_blockers || plan.preflight?.a3_blockers || plan.preflight?.blockers || [];
    status.textContent = available
      ? `Review the exact ${action} plan, then type its device-specific confirmation.`
      : (deviceId === "workstation"
        ? `${deviceLabel} is blocked: ${blockers.join(" · ") || "A2/A3 preflight is incomplete"}. Refresh ${deviceLabel} evidence, then recheck this preflight.`
        : "Remote live execution remains locally disabled pending candidate review.");
    byId("execute-maintenance-device-action").disabled = !available;
  } catch (error) {
    status.textContent = error.message;
  }
}

async function refreshWorkstationDeviceEvidence() {
  const preview = state.maintenanceDevicePreview; const status = byId("maintenance-device-dialog-status");
  if (!preview || canonicalMaintenanceDeviceId(preview.deviceId) !== "workstation") return;
  const deviceLabel = maintenanceDeviceLabel("workstation");
  byId("refresh-maintenance-device-evidence").disabled = true;
  status.textContent = `Reserving one visible read-only ${deviceLabel} evidence terminal…`;
  try {
    const evidenceEnvelope = await callSoul("maintenance.evidence.reserve"); lifecycle(evidenceEnvelope);
    const evidence = dataOf(evidenceEnvelope);
    if (!evidence.launch_uri) throw new Error(evidenceEnvelope.errors?.[0]?.message || `${deviceLabel} evidence handoff is unavailable.`);
    launchMaintenanceUri(evidence.launch_uri);
    status.textContent = `Native evidence terminal requested. When it closes, select Recheck ${deviceLabel} preflight.`;
  } catch (error) { status.textContent = error.message; }
  finally { byId("refresh-maintenance-device-evidence").disabled = false; }
}

async function recheckWorkstationDevicePreflight() {
  const preview = state.maintenanceDevicePreview;
  if (!preview || canonicalMaintenanceDeviceId(preview.deviceId) !== "workstation") return;
  await openMaintenanceDeviceAction("workstation", preview.action);
}

async function executeMaintenanceDeviceAction() {
  const preview = state.maintenanceDevicePreview; if (!preview) return;
  const confirmation = byId("maintenance-device-confirmation").value;
  const expected = preview.data.confirmation || preview.plan.confirmation;
  if (confirmation !== expected) return;
  const progress = byId("maintenance-device-progress"); const status = byId("maintenance-device-dialog-status");
  showGenerationProgress(progress, `${preview.action === "reboot" ? "Rebooting" : "Maintaining"} ${preview.plan.device_label}`, "The exact device-scoped operation is running in the foreground…");
  byId("execute-maintenance-device-action").disabled = true;
  try {
    let envelope;
    if (canonicalMaintenanceDeviceId(preview.deviceId) === "workstation") {
      const operation = preview.action === "maintenance" ? "maintenance.execution.execute" : "maintenance.reboot_restore.execute";
      envelope = await callSoul(operation, {
        force_database_refresh: "false",
        confirmation,
        expected_digest: preview.data.expected_digest
      });
      const data = dataOf(envelope); lifecycle(envelope);
      if (!data.handoff?.launch_uri) throw new Error(envelope.errors?.[0]?.message || "Workstation transaction stopped safely.");
      launchMaintenanceUri(data.handoff.launch_uri);
      status.textContent = `The visible ${maintenanceDeviceLabel("workstation")} terminal owns this one-device transaction. Its successful completion refreshes the persisted fleet snapshot.`;
    } else {
      envelope = await callNdjson("/api/v1/administration-stream", "maintenance.device.execute", {
        device_id: preview.deviceId,
        action: preview.action,
        confirmation,
        expected_digest: preview.data.expected_digest
      }, {}, (event) => showGenerationProgress(progress, event));
      const data = dataOf(envelope); lifecycle(envelope);
      if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || data.receipt?.summary || "Device operation stopped safely.");
      if (data.fleet?.devices) renderMaintenanceFleet(data.fleet);
      status.textContent = data.receipt?.summary || "Device operation completed and fleet status was refreshed.";
    }
    state.maintenanceDevicePreview = null;
  } catch (error) {
    status.textContent = error.name === "TimeoutError" ? "The device operation exceeded its foreground bound and requires review." : error.message;
  } finally {
    hideGenerationProgress(progress);
  }
}

function renderHostPlans(records) {
  const list = byId("host-plan-list"); list.replaceChildren(); byId("host-plan-count").textContent = String(records.length);
  records.forEach((plan) => { const button = labeledRecord(plan.plan_id, `${plan.pending_update_count} pending · ${plan.risk_class} · terminal handoff`); button.tabIndex = 0; button.addEventListener("click", () => { state.selectedHostPlan = plan.plan_id; byId("verify-host-plan").disabled = false; byId("host-plan-status").textContent = `${plan.plan_id} selected for a foreground postcondition check.`; }); list.append(button); });
  if (!records.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No host handoff packets created."; list.append(empty); }
}

async function loadHostPlans() {
  const envelope = await callSoul("host_improvement.plans.list", { limit: 100 });
  if (envelope.lifecycle_state === "complete") renderHostPlans(dataOf(envelope).records || []);
}

async function previewHostPlan() {
  const status = byId("host-plan-status"); status.textContent = "Running fresh Arch update discovery…"; byId("preview-host-plan").disabled = true;
  try {
    const envelope = await callSoul("host_improvement.arch_upgrade.preview"); const data = dataOf(envelope);
    if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "A fresh Arch plan could not be prepared.");
    state.hostPlanPreview = data; const plan = data.plan; const list = byId("host-plan-preview-details"); list.replaceChildren();
    list.append(labeledRecord(`${plan.pending_update_count} pending package records`, "Class 5 · interactive terminal only"), labeledRecord("Exact command", "sudo pacman -Syu · never executed by Soul"));
    byId("host-plan-preview").hidden = false; prefillApprovalGate("host-plan-confirmation", "create-host-plan", data.confirmation_phrase || "CREATE_ARCH_FULL_UPGRADE_HANDOFF"); status.textContent = "Review the exact handoff boundary; clicking Create writes the terminal packet and runs no host command.";
  } catch (error) { status.textContent = error.message; }
  finally { byId("preview-host-plan").disabled = false; }
}

async function createHostPlan() {
  if (!state.hostPlanPreview) return; const status = byId("host-plan-status"); status.textContent = "Revalidating fresh package evidence…";
  const envelope = await callSoul("host_improvement.arch_upgrade.handoff", { confirmation: byId("host-plan-confirmation").value, expected_digest: state.hostPlanPreview.expected_digest });
  const data = dataOf(envelope); lifecycle(envelope);
  if (envelope.lifecycle_state !== "blocked_for_human_review" || !data.packet) { status.textContent = envelope.errors?.[0]?.message || "Handoff creation was blocked safely."; return; }
  state.selectedHostPlan = data.plan.plan_id; state.hostPlanPreview = null; byId("host-plan-preview").hidden = true; byId("verify-host-plan").disabled = false; status.textContent = `Terminal handoff created at ${data.packet}. Soul executed no host command.`; await loadHostPlans();
}

async function verifyHostPlan() {
  if (!state.selectedHostPlan) return; const status = byId("host-plan-status"); status.textContent = "Checking current postconditions…"; byId("verify-host-plan").disabled = true;
  try { const envelope = await callSoul("host_improvement.plans.verify", { plan_id: state.selectedHostPlan }); const receipt = dataOf(envelope).receipt; if (!receipt) throw new Error(envelope.errors?.[0]?.message || "Verification failed safely."); status.textContent = receipt.postcondition === "satisfied" ? "Postcondition satisfied: fresh discovery reports no remaining repository updates." : `Postcondition not satisfied: ${receipt.remaining_update_count} update records remain.`; }
  catch (error) { status.textContent = error.message; }
  finally { byId("verify-host-plan").disabled = !state.selectedHostPlan; }
}

function renderMaintenancePreview(plan) {
  const list = byId("maintenance-preview-details"); list.replaceChildren();
  const snapshot = plan.window_snapshot || {};
  list.append(
    labeledRecord("Authentication contract", "One password request · transaction-scoped · A1 does not authenticate"),
    labeledRecord("Package mode", plan.force_database_refresh ? "yay -Syyu · forced database refresh" : "yay -Syu · normal full upgrade"),
    labeledRecord("Restore map", `${snapshot.restorable_count || 0} restorable · ${snapshot.unsupported_count || 0} unsupported`),
    labeledRecord("Privacy boundary", "No titles, URLs, raw process commands, terminal contents, or environment values")
  );
  (plan.commands || []).forEach((command) => {
    list.append(labeledRecord(command.adapter || "planned operation", (command.argv || []).join(" ")));
  });
  (snapshot.windows || []).filter((window) => window.restore_status !== "restorable").slice(0, 12).forEach((window) => {
    const identity = window.initial_class || window.class || "unknown application";
    list.append(labeledRecord(`${identity} · skipped`, window.reason || "not safely restorable"));
  });
  (snapshot.background_applications || []).forEach((application) => {
    list.append(labeledRecord(
      `${application.process_identity} · background`,
      application.restore_status === "restorable" ? "launch only if absent after login" : (application.reason || "not safely restorable")
    ));
  });
}

async function previewMaintenance() {
  const status = byId("maintenance-rehearsal-status");
  const force = byId("maintenance-force-refresh").checked;
  status.textContent = "Collecting fresh package and Hyprland evidence…";
  byId("preview-maintenance").disabled = true;
  byId("rehearse-maintenance").disabled = true;
  try {
    const envelope = await callSoul("maintenance.preview", { force_database_refresh: String(force) });
    const data = dataOf(envelope);
    if (envelope.lifecycle_state !== "complete" || !data.plan) throw new Error(envelope.errors?.[0]?.message || "Maintenance preview failed safely.");
    state.maintenancePreview = data;
    renderMaintenancePreview(data.plan);
    byId("rehearse-maintenance").disabled = false;
    status.textContent = "Preview ready. No command was executed and no state was written.";
  } catch (error) {
    state.maintenancePreview = null;
    status.textContent = error.message;
  } finally {
    byId("preview-maintenance").disabled = false;
  }
}

async function rehearseMaintenance() {
  if (!state.maintenancePreview) return;
  const status = byId("maintenance-rehearsal-status");
  const output = byId("maintenance-rehearsal-output");
  status.textContent = "Rehearsing bounded lifecycle and restore decisions…";
  byId("rehearse-maintenance").disabled = true;
  try {
    const envelope = await callSoul("maintenance.rehearsal", { force_database_refresh: String(byId("maintenance-force-refresh").checked) });
    const data = dataOf(envelope); const journal = data.journal;
    if (!journal) throw new Error(envelope.errors?.[0]?.message || "Maintenance rehearsal failed safely.");
    output.hidden = false;
    output.textContent = [
      `State: ${journal.current_state}`,
      `Simulated: ${(journal.simulated_lifecycle || []).map((entry) => entry.state).join(" → ")}`,
      `Restorable: ${journal.restorable_count}`,
      `Unsupported: ${journal.unsupported_count}`,
      `Password requested: ${journal.password_requested}`,
      `Commands executed: ${(journal.commands_executed || []).length}`,
      `State written: ${journal.state_written}`,
      `Reboot requested: ${journal.reboot_requested}`,
      ...(journal.blockers || []).map((blocker) => `Blocker: ${blocker}`)
    ].join("\n");
    status.textContent = envelope.lifecycle_state === "complete"
      ? "Rehearsal complete. Every stage was simulated; the host was unchanged."
      : (envelope.errors?.[0]?.message || "Rehearsal stopped for human review; the host was unchanged.");
  } catch (error) {
    status.textContent = error.message;
  } finally {
    byId("rehearse-maintenance").disabled = !state.maintenancePreview;
  }
}

function renderMaintenanceExecutionPlan(plan) {
  const details = byId("maintenance-execution-details"); details.replaceChildren();
  const rows = [
    ["Authentication", plan.authority_mode === "root_owned_passwordless" && plan.one_authentication_required === false ? "A4 fixed-operation authority · no password prompt" : "one native sudo -v prompt · never enters the Dashboard"],
    ["Arch/AUR", plan.commands?.find((item) => item.adapter === "arch_and_aur.full_upgrade")?.argv?.join(" ") || "unavailable"],
    ["Flatpak scopes", (plan.flatpak_installations || []).map((item) => item.scope).join(", ") || "none"],
    ["Active work", plan.preflight?.active_work?.join(", ") || "none"],
    ["Disk evidence", (plan.preflight?.disk_free || []).map((item) => `${item.path} · ${Math.floor(Number(item.available_kib || 0) / 1024)} MiB free`).join(" · ") || "unavailable"],
    ["Restore map", `${plan.window_restore_summary?.restorable_count ?? 0} restorable · ${plan.window_restore_summary?.unsupported_count ?? 0} unsupported`],
    ["Reboot", "prohibited in A2"]
  ];
  rows.forEach(([label, value]) => details.append(labeledRecord(label, value)));
  (plan.preflight?.rehearsal_blockers || []).forEach((blocker) => details.append(labeledRecord("Blocker", blocker)));
  (plan.preflight?.live_blockers || []).filter((blocker) => !(plan.preflight?.rehearsal_blockers || []).includes(blocker))
    .forEach((blocker) => details.append(labeledRecord("Live blocker", blocker)));
}

function renderMaintenanceReceipt(receipt) {
  const container = byId("maintenance-receipts"); container.replaceChildren();
  if (!receipt) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No A2 receipt loaded."; container.append(empty); return; }
  [
    ["Transaction", receipt.transaction_id],
    ["Mode", receipt.mode],
    ["Lifecycle", receipt.lifecycle_state],
    ["Password prompts", receipt.password_prompts],
    ["Sudo ticket", receipt.sudo_ticket_invalidated ? "invalidated" : "attention required"],
    ["Commands", (receipt.commands || []).map((item) => `${item.adapter} · ${item.status}`).join(" · ") || "none"],
    ["Reboot", receipt.reboot_requested ? "unexpected request blocked" : "not requested"]
  ].forEach(([label, value]) => container.append(labeledRecord(label, String(value ?? "—"))));
}

function launchMaintenanceUri(uri) {
  const exact = String(uri || "");
  const allowed = /^soul-maintenance:\/\/(?:evidence\/maintenance_evidence_[a-f0-9]{16}|transaction\/maintenance_tx_[a-f0-9]{16})\/[a-f0-9]{64}$/;
  if (!allowed.test(exact)) throw new Error("Maintenance handoff URI failed local validation.");
  window.location.href = exact;
}

async function refreshNativeMaintenanceEvidence() {
  const status = byId("maintenance-execution-status");
  byId("refresh-maintenance-evidence").disabled = true;
  status.textContent = "Reserving one visible read-only native evidence terminal…";
  try {
    const envelope = await callSoul("maintenance.evidence.reserve"); lifecycle(envelope);
    const data = dataOf(envelope);
    if (!data.launch_uri) throw new Error(envelope.errors?.[0]?.message || data.reason || "Native evidence handoff is unavailable.");
    launchMaintenanceUri(data.launch_uri);
    status.textContent = "Native evidence terminal requested. When it closes, click Review A2 transaction again.";
  } catch (error) { status.textContent = error.message; }
  finally { byId("refresh-maintenance-evidence").disabled = false; }
}

async function previewMaintenanceExecution() {
  const force = byId("maintenance-force-refresh").checked; const status = byId("maintenance-execution-status");
  state.maintenanceExecutionPreview = null; byId("rehearse-maintenance-execution").disabled = true; byId("execute-maintenance").disabled = true;
  status.textContent = "Revalidating package, disk, active-work, and restore evidence…";
  try {
    const envelope = await callSoul("maintenance.execution.preview", { force_database_refresh: String(force) }); lifecycle(envelope);
    const data = dataOf(envelope); const plan = data.plan; if (!plan) throw new Error(envelope.errors?.[0]?.message || "A2 transaction preview failed safely");
    state.maintenanceExecutionPreview = data; renderMaintenanceExecutionPlan(plan);
    const rehearsalBlocked = (plan.preflight?.rehearsal_blockers || plan.preflight?.blockers || []).length > 0;
    const liveBlocked = (plan.preflight?.live_blockers || plan.preflight?.blockers || []).length > 0;
    byId("rehearse-maintenance-execution").disabled = rehearsalBlocked;
    byId("execute-maintenance").disabled = liveBlocked || !plan.execution_available;
    byId("execute-maintenance").textContent = plan.execution_available ? "Open maintenance terminal" : "Live update unavailable";
    byId("maintenance-execution-state").textContent = rehearsalBlocked ? "blocked" : (plan.execution_available ? "review ready" : "rehearsal ready");
    status.textContent = rehearsalBlocked
      ? "A2 rehearsal preflight found blockers; no terminal can open."
      : (liveBlocked
        ? "Fixture rehearsal is ready; live-update blockers remain visible and no host update is available."
        : "Exact A2 digest ready. Terminal rehearsal performs no authentication or host update.");
  } catch (error) { status.textContent = error.message; }
}

async function runMaintenanceExecution(mode) {
  const preview = state.maintenanceExecutionPreview; if (!preview) return;
  const progress = byId("maintenance-execution-progress"); const status = byId("maintenance-execution-status");
  showGenerationProgress(progress, "Foreground transaction", mode === "rehearsal" ? "Opening the visible no-mutation terminal rehearsal…" : "The visible terminal now owns the reviewed update transaction…");
  byId("preview-maintenance-execution").disabled = true; byId("rehearse-maintenance-execution").disabled = true; byId("execute-maintenance").disabled = true;
  try {
    const operation = mode === "rehearsal" ? "maintenance.execution.rehearsal" : "maintenance.execution.execute";
    const envelope = await callSoul(operation, {
      force_database_refresh: String(byId("maintenance-force-refresh").checked),
      confirmation: preview.confirmation,
      expected_digest: preview.expected_digest
    });
    const data = dataOf(envelope); lifecycle(envelope);
    if (mode === "live" && data.handoff?.launch_uri) {
      launchMaintenanceUri(data.handoff.launch_uri);
      status.textContent = "Visible maintenance terminal requested. The Dashboard will not poll; click Refresh receipt after the terminal closes.";
    } else {
      renderMaintenanceReceipt(data.receipt);
      status.textContent = data.receipt ? `${data.receipt.mode} · ${data.receipt.lifecycle_state} · sudo ticket ${data.receipt.sudo_ticket_invalidated ? "invalidated" : "requires review"}` : (envelope.errors?.[0]?.message || "Transaction stopped safely.");
    }
    state.maintenanceExecutionPreview = null;
  } catch (error) { status.textContent = error.message; }
  finally { hideGenerationProgress(progress); byId("preview-maintenance-execution").disabled = false; }
}

async function loadMaintenanceReceipts() {
  try {
    const envelope = await callSoul("maintenance.execution.receipts", { limit: 1 }); const data = dataOf(envelope); lifecycle(envelope);
    renderMaintenanceReceipt((data.receipts || [])[0]);
    const evidence = data.native_package_evidence || {}; const handoff = data.desktop_handoff || {};
    if (!handoff.available) byId("maintenance-execution-status").textContent = (handoff.problems || []).join(" · ") || "Maintenance desktop handoff is unavailable.";
    else if (evidence.available) byId("maintenance-execution-status").textContent = `Native package evidence ready until ${new Date(evidence.expires_at).toLocaleTimeString()}.`;
  } catch (error) { byId("maintenance-execution-status").textContent = error.message; }
}

function renderMaintenanceRebootPlan(plan) {
  const details = byId("maintenance-reboot-details"); details.replaceChildren();
  [
    ["Authentication", plan.authority_mode === "root_owned_passwordless" && plan.one_authentication_required === false ? "A4 fixed-operation authority · no password prompt" : "one native sudo -v prompt · never enters the Dashboard"],
    ["Arch/AUR", plan.commands?.find((item) => item.adapter === "arch_and_aur.full_upgrade")?.argv?.join(" ") || "unavailable"],
    ["Restore map", `${plan.window_restore_summary?.restorable_count ?? 0} restorable · ${plan.window_restore_summary?.unsupported_count ?? 0} unsupported`],
    ["Resume unit", plan.resume_unit?.ready ? "exact unit installed · enabled · one-shot" : "not ready"],
    ["Source boot", plan.source_boot_id || "unavailable"],
    ["Reboot", "one conditional request · no automatic retry"]
  ].forEach(([label, value]) => details.append(labeledRecord(label, value)));
  (plan.preflight?.a3_blockers || []).forEach((blocker) => details.append(labeledRecord("A3 blocker", blocker)));
}

async function previewMaintenanceReboot() {
  const force = byId("maintenance-force-refresh").checked; const status = byId("maintenance-reboot-status");
  state.maintenanceRebootPreview = null; byId("execute-maintenance-reboot").disabled = true;
  status.textContent = "Revalidating update, reboot, resume-unit, and restore evidence…";
  try {
    const envelope = await callSoul("maintenance.reboot_restore.preview", { force_database_refresh: String(force) }); lifecycle(envelope);
    const data = dataOf(envelope); const plan = data.plan;
    if (!plan) throw new Error(envelope.errors?.[0]?.message || "A3 transaction preview failed safely.");
    state.maintenanceRebootPreview = data; renderMaintenanceRebootPlan(plan);
    byId("execute-maintenance-reboot").disabled = !plan.execution_available;
    byId("execute-maintenance-reboot").textContent = plan.execution_available ? "Open update and reboot terminal" : "Live reboot unavailable";
    byId("maintenance-reboot-state").textContent = (plan.preflight?.a3_blockers || []).length ? "blocked" : (plan.execution_available ? "review ready" : "candidate ready");
    status.textContent = (plan.preflight?.a3_blockers || []).length
      ? "A3 blockers remain visible; no reboot transaction can open."
      : (plan.execution_available ? "Exact A3 digest ready for separately authorized supervision." : "A3 candidate is ready; live reboot remains locally disabled.");
  } catch (error) { status.textContent = error.message; }
}

async function executeMaintenanceReboot() {
  const preview = state.maintenanceRebootPreview; if (!preview) return;
  const progress = byId("maintenance-reboot-progress"); const status = byId("maintenance-reboot-status");
  showGenerationProgress(progress, "Conditional reboot", preview.plan?.authority_mode === "root_owned_passwordless" ? "Opening the visible zero-password update and reboot terminal…" : "Opening the visible one-password update and reboot terminal…");
  byId("preview-maintenance-reboot").disabled = true; byId("execute-maintenance-reboot").disabled = true;
  try {
    const envelope = await callSoul("maintenance.reboot_restore.execute", {
      force_database_refresh: String(byId("maintenance-force-refresh").checked),
      confirmation: preview.confirmation,
      expected_digest: preview.expected_digest
    });
    const data = dataOf(envelope); lifecycle(envelope);
    if (!data.handoff?.launch_uri) throw new Error(envelope.errors?.[0]?.message || "A3 transaction stopped safely.");
    launchMaintenanceUri(data.handoff.launch_uri);
    status.textContent = "Visible A3 terminal requested. If every postcondition passes, the host will reboot once and the one-shot resume unit will close the journal after login.";
    state.maintenanceRebootPreview = null;
  } catch (error) { status.textContent = error.message; }
  finally { hideGenerationProgress(progress); byId("preview-maintenance-reboot").disabled = false; }
}

async function loadMaintenanceRebootStatus() {
  try {
    const envelope = await callSoul("maintenance.reboot_restore.status"); const data = dataOf(envelope); lifecycle(envelope);
    const resume = data.resume_unit || {};
    byId("maintenance-reboot-state").textContent = data.pending_restore ? "pending restore" : (resume.ready ? "unit ready" : "unit unavailable");
    byId("maintenance-reboot-status").textContent = data.pending_restore
      ? "A boot-bound restoration journal is pending; do not start another maintenance transaction."
      : (resume.ready ? "The exact one-shot resume unit is installed and no restoration is pending." : "Install the reviewed one-shot resume unit before A3 can become available.");
  } catch (error) { byId("maintenance-reboot-status").textContent = error.message; }
}

function renderAugmentationProposals(records) {
  state.augmentationProposals = records; const list = byId("augmentation-proposal-list"); list.replaceChildren(); byId("augmentation-proposal-count").textContent = String(records.length);
  records.forEach((proposal) => { const item = labeledRecord(proposal.objective || proposal.proposal_id, `${proposal.stage} · ${proposal.risk_class} · select for Gate A1`); item.tabIndex = 0; item.setAttribute("role", "button"); const select = () => { state.selectedAugmentationProposal = proposal; byId("augmentation-selected-proposal").textContent = `${proposal.proposal_id} · ${proposal.objective}`; byId("preview-augmentation-experiment").disabled = false; byId("augmentation-experiment-status").textContent = "Define the exact file scope, then preview Gate A1."; }; item.addEventListener("click", select); item.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); select(); } }); list.append(item); });
  if (!records.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No augmentation proposal packets."; list.append(empty); }
}

function renderAugmentationCensus(report) {
  byId("augmentation-census-state").textContent = "ready"; const details = byId("augmentation-census"); details.replaceChildren();
  [["Revision", report.head?.slice(0, 12)], ["Tracked paths", report.tracked_path_count], ["Text inspected", report.text_file_count], ["Bytes read", report.content_bytes_read], ["Verifier scripts", report.verifier_count], ["Excluded", report.excluded_count]].forEach(([term, value]) => { const row = document.createElement("div"); const dt = document.createElement("dt"); const dd = document.createElement("dd"); dt.textContent = term; dd.textContent = String(value ?? "—"); row.append(dt, dd); details.append(row); });
}

async function loadSelfAugmentation() {
  byId("augmentation-status").textContent = "Loading local proposal inventory…";
  try { const [proposals, experiments] = await Promise.all([callSoul("self_augmentation.proposals.list", { limit: 100 }), callSoul("self_augmentation.experiments.list", { limit: 100 })]); renderAugmentationProposals(dataOf(proposals).records || []); renderAugmentationExperiments(dataOf(experiments).records || []); state.augmentationLoaded = true; byId("augmentation-status").textContent = "Observation runs only when requested."; }
  catch (error) { byId("augmentation-status").textContent = error.message; }
}

async function runAugmentationCensus() {
  const button = byId("run-augmentation-census"); button.disabled = true; byId("augmentation-census-state").textContent = "running"; byId("augmentation-status").textContent = "Surveying bounded Git-tracked construction…";
  try { const envelope = await callSoul("self_augmentation.census"); const data = dataOf(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Census failed safely."); renderAugmentationCensus(data.census); renderAugmentationProposals(data.proposals?.records || []); byId("augmentation-status").textContent = "Tracked-code census complete. No project files were changed."; }
  catch (error) { byId("augmentation-census-state").textContent = "failed"; byId("augmentation-status").textContent = error.message; }
  finally { button.disabled = false; }
}

async function previewAugmentationProposal() {
  const objective = byId("augmentation-objective").value; const why = byId("augmentation-why-not-skill").value; const status = byId("augmentation-status"); status.textContent = "Binding proposal to the current tracked-code census…";
  const envelope = await callSoul("self_augmentation.proposals.preview", { objective, why_not_skill: why }); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Proposal preview failed safely."; return; }
  state.augmentationPreview = data; const proposal = data.proposal; const list = byId("augmentation-proposal-preview-details"); list.replaceChildren(); list.append(labeledRecord(proposal.objective, `${proposal.risk_class} · source ${proposal.head.slice(0, 12)}`), labeledRecord("Core-change rationale", proposal.why_not_skill));
  byId("augmentation-proposal-preview").hidden = false; prefillApprovalGate("augmentation-confirmation", "create-augmentation-proposal", data.confirmation_phrase || "CREATE_SELF_AUGMENTATION_PROPOSAL"); status.textContent = "Review this exact census-bound packet; clicking Create writes no implementation.";
}

async function createAugmentationProposal() {
  if (!state.augmentationPreview) return; const status = byId("augmentation-status"); status.textContent = "Rechecking tracked repository evidence…";
  const envelope = await callSoul("self_augmentation.proposals.execute", { objective: byId("augmentation-objective").value, why_not_skill: byId("augmentation-why-not-skill").value, confirmation: byId("augmentation-confirmation").value, expected_digest: state.augmentationPreview.expected_digest }); const data = dataOf(envelope); lifecycle(envelope);
  if (envelope.lifecycle_state !== "blocked_for_human_review" || !data.packet) { status.textContent = envelope.errors?.[0]?.message || "Proposal creation was blocked safely."; return; }
  state.augmentationPreview = null; byId("augmentation-proposal-preview").hidden = true; status.textContent = `Review packet created at ${data.packet}. Experiment and integration remain locked.`; await loadSelfAugmentation();
}

function selectedAllowedFiles() { return byId("augmentation-allowed-files").value.split(/\r?\n/).map((value) => value.trim()).filter(Boolean); }

function selectAugmentationExperiment(record) {
  state.selectedAugmentationExperiment = record; state.augmentationGateA2Preview = null; state.augmentationCleanupPreview = null;
  byId("augmentation-selected-experiment").textContent = `${record.experiment_id} · ${record.stage} · base ${record.base_commit.slice(0, 12)}`;
  ["generate-augmentation-dossier", "preview-augmentation-gate-a2", "preview-augmentation-cleanup"].forEach((id) => { byId(id).disabled = false; });
  byId("augmentation-review-status").textContent = "Candidate actions run only when explicitly requested.";
}

function renderAugmentationExperiments(records) {
  state.augmentationExperiments = records; const list = byId("augmentation-experiment-list"); list.replaceChildren(); byId("augmentation-experiment-count").textContent = String(records.length);
  records.forEach((record) => { const item = labeledRecord(record.experiment_id, `${record.stage} · ${record.worktree}`); item.tabIndex = 0; item.setAttribute("role", "button"); const select = () => selectAugmentationExperiment(record); item.addEventListener("click", select); item.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); select(); } }); list.append(item); });
  if (!records.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No isolated experiments prepared."; list.append(empty); }
}

async function reloadAugmentationExperiments() { const envelope = await callSoul("self_augmentation.experiments.list", { limit: 100 }); renderAugmentationExperiments(dataOf(envelope).records || []); }

async function previewAugmentationExperiment() {
  if (!state.selectedAugmentationProposal) return; const status = byId("augmentation-experiment-status"); status.textContent = "Checking exact proposal, clean base, and file scope…";
  const envelope = await callSoul("self_augmentation.experiments.gate_a1.preview", { proposal_id: state.selectedAugmentationProposal.proposal_id, allowed_files: selectedAllowedFiles() }); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Gate A1 preview blocked safely."; return; }
  state.augmentationExperimentPreview = data; const list = byId("augmentation-experiment-preview-details"); list.replaceChildren(); list.append(labeledRecord("Exact base", data.base_commit), labeledRecord("Allowed scope", `${data.allowed_files.length} exact path(s) · no globs`));
  byId("augmentation-experiment-preview").hidden = false; prefillApprovalGate("augmentation-experiment-confirmation", "create-augmentation-experiment", data.confirmation_phrase || "APPROVE_AUGMENTATION_EXPERIMENT"); status.textContent = "Gate A1 creates one detached worktree and handoff; clicking Create does not invoke Codex.";
}

async function createAugmentationExperiment() {
  if (!state.augmentationExperimentPreview || !state.selectedAugmentationProposal) return; const status = byId("augmentation-experiment-status"); status.textContent = "Revalidating clean primary worktree and exact base…";
  const envelope = await callSoul("self_augmentation.experiments.gate_a1.execute", { proposal_id: state.selectedAugmentationProposal.proposal_id, allowed_files: state.augmentationExperimentPreview.allowed_files, confirmation: byId("augmentation-experiment-confirmation").value, expected_digest: state.augmentationExperimentPreview.expected_digest }); const data = dataOf(envelope); lifecycle(envelope);
  if (envelope.lifecycle_state !== "blocked_for_human_review" || !data.experiment) { status.textContent = envelope.errors?.[0]?.message || "Experiment preparation failed safely."; return; }
  state.augmentationExperimentPreview = null; byId("augmentation-experiment-preview").hidden = true; status.textContent = `Isolated worktree prepared at ${data.experiment.worktree}. Codex was not invoked.`; await reloadAugmentationExperiments();
}

function renderAugmentationDossier(dossier) {
  const list = byId("augmentation-dossier-summary"); list.replaceChildren(); const blockers = dossier.blockers || [];
  list.append(labeledRecord(`${dossier.changed_file_count} changed file(s)`, `${dossier.base_commit.slice(0, 10)} → ${dossier.candidate_commit.slice(0, 10)}`), labeledRecord("Deterministic verification", `${(dossier.deterministic_tests || []).filter((test) => test.status === "passed").length}/${(dossier.deterministic_tests || []).length} passed · no-network sandbox`), labeledRecord("Gate blockers", blockers.length ? blockers.join("; ") : "none", blockers.length ? "is-warning" : "is-available"));
  byId("augmentation-review-state").textContent = blockers.length ? "blocked" : "ready";
}

async function generateAugmentationDossier() {
  if (!state.selectedAugmentationExperiment) return; const status = byId("augmentation-review-status"); status.textContent = "Inspecting exact committed diff and running sandboxed checks…";
  const envelope = await callSoul("self_augmentation.reviews.generate", { experiment_id: state.selectedAugmentationExperiment.experiment_id }); const dossier = dataOf(envelope).dossier;
  if (!dossier) { status.textContent = envelope.errors?.[0]?.message || "Dossier generation failed safely."; return; }
  renderAugmentationDossier(dossier); status.textContent = dossier.blockers?.length ? "Dossier written with blockers; Gate A2 remains unavailable." : "Candidate dossier is clear for Gate A2 preview. Passing checks do not authorize integration.";
}

async function previewAugmentationGateA2() {
  if (!state.selectedAugmentationExperiment) return; const status = byId("augmentation-review-status"); status.textContent = "Revalidating candidate commit and dossier…";
  const envelope = await callSoul("self_augmentation.reviews.gate_a2.preview", { experiment_id: state.selectedAugmentationExperiment.experiment_id }); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { if (data.dossier) renderAugmentationDossier(data.dossier); status.textContent = envelope.errors?.[0]?.message || "Gate A2 remains blocked."; return; }
  state.augmentationGateA2Preview = data; renderAugmentationDossier(data.dossier); byId("augmentation-gate-a2-preview").hidden = false; prefillApprovalGate("augmentation-gate-a2-confirmation", "execute-augmentation-gate-a2", data.confirmation_phrase || "APPROVE_AUGMENTATION_FOR_INTEGRATION_REVIEW"); status.textContent = "Review the exact candidate; clicking Approve writes an external integration handoff only.";
}

async function executeAugmentationGateA2() {
  if (!state.augmentationGateA2Preview || !state.selectedAugmentationExperiment) return; const status = byId("augmentation-review-status"); status.textContent = "Revalidating exact candidate revision…";
  const envelope = await callSoul("self_augmentation.reviews.gate_a2.execute", { experiment_id: state.selectedAugmentationExperiment.experiment_id, confirmation: byId("augmentation-gate-a2-confirmation").value, expected_digest: state.augmentationGateA2Preview.expected_digest }); const data = dataOf(envelope); lifecycle(envelope);
  if (envelope.lifecycle_state !== "blocked_for_human_review" || !data.handoff) { status.textContent = envelope.errors?.[0]?.message || "Gate A2 approval blocked safely."; return; }
  state.augmentationGateA2Preview = null; byId("augmentation-gate-a2-preview").hidden = true; status.textContent = `External integration handoff written at ${data.handoff}. Soul integrated nothing.`; await reloadAugmentationExperiments();
}

async function previewAugmentationCleanup() {
  if (!state.selectedAugmentationExperiment) return; const status = byId("augmentation-review-status"); status.textContent = "Checking worktree cleanliness…";
  const envelope = await callSoul("self_augmentation.experiments.cleanup.preview", { experiment_id: state.selectedAugmentationExperiment.experiment_id }); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Dirty worktree removal refused."; return; }
  state.augmentationCleanupPreview = data; byId("augmentation-cleanup-preview").hidden = false; byId("augmentation-cleanup-confirmation").value = ""; byId("execute-augmentation-cleanup").disabled = true; status.textContent = "Only this clean worktree may be removed. Review records remain.";
}

async function executeAugmentationCleanup() {
  if (!state.augmentationCleanupPreview || !state.selectedAugmentationExperiment) return; const envelope = await callSoul("self_augmentation.experiments.cleanup.execute", { experiment_id: state.selectedAugmentationExperiment.experiment_id, confirmation: byId("augmentation-cleanup-confirmation").value, expected_digest: state.augmentationCleanupPreview.expected_digest }); lifecycle(envelope);
  if (envelope.lifecycle_state !== "canceled") { byId("augmentation-review-status").textContent = envelope.errors?.[0]?.message || "Cleanup failed safely."; return; }
  state.augmentationCleanupPreview = null; state.selectedAugmentationExperiment = null; byId("augmentation-cleanup-preview").hidden = true; byId("augmentation-review-status").textContent = "Clean worktree removed; review records retained."; await reloadAugmentationExperiments();
}

function augmentationModelParameters() { return { experiment_id: state.selectedAugmentationExperiment?.experiment_id, suite_id: byId("augmentation-model-suite").value.trim(), model_profile: byId("augmentation-model-profile").value.trim(), result: byId("augmentation-model-result").value, evidence_digest: byId("augmentation-model-evidence").value.trim() }; }
async function previewAugmentationModelResult() {
  if (!state.selectedAugmentationExperiment) return; const envelope = await callSoul("self_augmentation.model_qualification.preview", augmentationModelParameters()); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { byId("augmentation-review-status").textContent = envelope.errors?.[0]?.message || "Qualification record preview failed."; return; }
  state.augmentationModelPreview = data; byId("augmentation-model-preview").hidden = false; prefillApprovalGate("augmentation-model-confirmation", "record-augmentation-model-result", data.confirmation_phrase || "RECORD_AUGMENTATION_MODEL_QUALIFICATION"); byId("augmentation-review-status").textContent = "Review the evidence; clicking Record stores it but authorizes nothing else.";
}
async function recordAugmentationModelResult() {
  if (!state.augmentationModelPreview) return; const envelope = await callSoul("self_augmentation.model_qualification.execute", { ...augmentationModelParameters(), confirmation: byId("augmentation-model-confirmation").value, expected_digest: state.augmentationModelPreview.expected_digest }); lifecycle(envelope);
  if (envelope.lifecycle_state !== "complete") { byId("augmentation-review-status").textContent = envelope.errors?.[0]?.message || "Qualification record failed safely."; return; }
  state.augmentationModelPreview = null; byId("augmentation-model-preview").hidden = true; byId("augmentation-review-status").textContent = "Local-model qualification evidence recorded. Gate A2 still requires deterministic review and exact human approval.";
}

function reviewEmpty(target, titleText, detailText) {
  const empty = document.createElement("div"); empty.className = "review-empty";
  const sigil = document.createElement("span"); sigil.setAttribute("aria-hidden", "true"); sigil.textContent = "◇";
  const title = document.createElement("h3"); title.textContent = titleText;
  const detail = document.createElement("p"); detail.textContent = detailText;
  empty.append(sigil, title, detail); target.replaceChildren(empty);
}

function reviewRecordButton(titleText, metaText, tone, selected, onSelect) {
  const button = document.createElement("button"); button.type = "button"; button.className = `review-record ${tone || ""}`.trim();
  if (selected) button.classList.add("is-active");
  const marker = document.createElement("span"); marker.className = "review-record-marker"; marker.setAttribute("aria-hidden", "true"); marker.textContent = "◆";
  const copy = document.createElement("span"); const title = document.createElement("strong"); title.textContent = titleText; const meta = document.createElement("small"); meta.textContent = metaText;
  copy.append(title, meta); button.append(marker, copy); button.addEventListener("click", onSelect); return button;
}

function renderApprovalDetail(record) {
  state.selectedApproval = record; const detail = byId("approval-review-detail"); detail.replaceChildren();
  const heading = document.createElement("div"); heading.className = "review-detail-heading";
  const copy = document.createElement("div"); const eyebrow = document.createElement("p"); eyebrow.className = "eyebrow"; eyebrow.textContent = "Pending authorization"; const title = document.createElement("h3"); title.textContent = record.skill_id || "Unknown skill"; copy.append(eyebrow, title);
  const chip = document.createElement("span"); chip.className = "review-state-chip review-state-chip--attention"; chip.textContent = record.status || "pending"; heading.append(copy, chip);
  const intro = document.createElement("p"); intro.className = "review-detail-copy"; intro.textContent = "This record proves a bounded authorization exists. Review Center cannot reveal, consume, revoke, or execute it.";
  const metadata = document.createElement("dl"); metadata.className = "review-detail-meta"; renderDefinitionList(metadata, [["Reference", record.approval_ref], ["Issued", formatTime(record.issued_at)], ["Expires", formatTime(record.expires_at)], ["Scope digest", record.scope_digest || "unavailable"]]);
  const scopeTitle = document.createElement("h4"); scopeTitle.textContent = "Redacted scope shape"; const tags = document.createElement("div"); tags.className = "scope-key-list";
  (record.scope_keys || []).forEach((value) => { const tag = document.createElement("span"); tag.textContent = value; tags.append(tag); });
  if (!record.scope_keys?.length) { const none = document.createElement("span"); none.textContent = "No scope keys projected"; tags.append(none); }
  const boundary = document.createElement("div"); boundary.className = "review-detail-boundary"; const boundaryTitle = document.createElement("strong"); boundaryTitle.textContent = "Authorization value hidden"; const boundaryCopy = document.createElement("p"); boundaryCopy.textContent = "Return to Chat or the originating bounded workflow to continue. Skill proposal and Beta gates remain in Skill Studio."; boundary.append(boundaryTitle, boundaryCopy);
  detail.append(heading, intro, metadata, scopeTitle, tags, boundary); renderApprovalList();
}

function renderApprovalList() {
  const list = byId("approval-review-list"); list.replaceChildren(); byId("approval-list-count").textContent = String(state.approvals.length);
  if (!state.approvals.length) { const empty = document.createElement("p"); empty.className = "muted review-list-empty"; empty.textContent = "No pending approvals. New bounded approvals will appear here after an originating preview flow."; list.append(empty); reviewEmpty(byId("approval-review-detail"), "No active authorization records.", "Review Center is ready; nothing currently requires approval-state inspection."); return; }
  state.approvals.forEach((record) => list.append(reviewRecordButton(record.skill_id || "Unknown skill", `${record.status || "pending"} · expires ${formatTime(record.expires_at)}`, "is-attention", state.selectedApproval?.approval_ref === record.approval_ref, () => renderApprovalDetail(record))));
}

function activityTone(record) {
  if (record.status === "failed") return "is-failed";
  if (record.status === "blocked" || record.blocked_count > 0) return "is-attention";
  return record.executed ? "is-verified" : "";
}

function renderActivityDetail(record) {
  state.selectedActivity = record; const detail = byId("activity-review-detail"); detail.replaceChildren();
  const heading = document.createElement("div"); heading.className = "review-detail-heading";
  const copy = document.createElement("div"); const eyebrow = document.createElement("p"); eyebrow.className = "eyebrow"; eyebrow.textContent = record.source || "local activity"; const title = document.createElement("h3"); title.textContent = record.skill_id || "Unrouted activity"; copy.append(eyebrow, title);
  const chip = document.createElement("span"); chip.className = `review-state-chip ${activityTone(record)}`.trim(); chip.textContent = record.status || "unknown"; heading.append(copy, chip);
  const metadata = document.createElement("dl"); metadata.className = "review-detail-meta"; renderDefinitionList(metadata, [["Timestamp", formatTime(record.timestamp)], ["Executed", record.executed ? "yes" : "no"], ["Succeeded", record.ok ? "yes" : "no"], ["Risk", record.risk || "not recorded"], ["Confirmation", record.confirmation_required ? "required" : "not required"], ["Exit status", record.exit_status ?? "none"]]);
  const blockersTitle = document.createElement("h4"); blockersTitle.textContent = "Blocked categories"; const blockers = document.createElement("div"); blockers.className = "scope-key-list";
  (record.blocked_categories || []).forEach((value) => { const tag = document.createElement("span"); tag.textContent = value; blockers.append(tag); });
  if (!record.blocked_categories?.length) { const none = document.createElement("span"); none.textContent = "None recorded"; blockers.append(none); }
  const boundary = document.createElement("div"); boundary.className = "review-detail-boundary review-detail-boundary--neutral"; const boundaryTitle = document.createElement("strong"); boundaryTitle.textContent = "Private request omitted"; const boundaryCopy = document.createElement("p"); boundaryCopy.textContent = "This evidence projection cannot replay, retry, clear, prune, or export the underlying execution history."; boundary.append(boundaryTitle, boundaryCopy);
  detail.append(heading, metadata, blockersTitle, blockers, boundary); renderActivityList();
}

function renderActivityList() {
  const list = byId("activity-review-list"); list.replaceChildren(); byId("activity-list-count").textContent = String(state.activities.length);
  if (!state.activities.length) { const empty = document.createElement("p"); empty.className = "muted review-list-empty"; empty.textContent = "No activity matches this bounded filter."; list.append(empty); reviewEmpty(byId("activity-review-detail"), "No matching execution evidence.", "Choose another filter or refresh after a foreground skill run."); return; }
  state.activities.forEach((record) => list.append(reviewRecordButton(record.skill_id || "Unrouted activity", `${record.status || "unknown"} · ${formatTime(record.timestamp)}`, activityTone(record), state.selectedActivity === record, () => renderActivityDetail(record))));
}

function renderReviewSummary() {
  const summary = state.activitySummary; const blocked = summary.filter((record) => record.status === "blocked" || record.blocked_count > 0).length; const failed = summary.filter((record) => record.status === "failed").length;
  byId("review-pending-count").textContent = String(state.approvals.length); byId("review-activity-count").textContent = String(summary.length); byId("review-blocked-count").textContent = String(blocked); byId("review-failed-count").textContent = String(failed);
  const badge = byId("review-pending-badge"); badge.textContent = String(state.approvals.length); badge.hidden = state.approvals.length === 0;
}

function activityFilters(filter) {
  if (filter === "executed") return { executed: true };
  if (filter === "blocked") return { status: "blocked" };
  if (filter === "failed") return { status: "failed" };
  return {};
}

async function filterReviewActivity(filter) {
  state.activityFilter = filter; state.selectedActivity = null; document.querySelectorAll("[data-activity-filter]").forEach((button) => button.classList.toggle("is-active", button.dataset.activityFilter === filter));
  byId("review-center-status").textContent = `Loading ${filter} activity…`;
  try { const envelope = await callSoul("activities.recent", { limit: 100, filters: activityFilters(filter) }); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Activity filter failed safely"); state.activities = dataOf(envelope).records || []; renderActivityList(); byId("review-center-status").textContent = `${state.activities.length} ${filter} activity record${state.activities.length === 1 ? "" : "s"} shown.`; }
  catch (error) { byId("review-center-status").textContent = error.message || "Activity filter failed safely."; }
}

async function loadReviewCenter() {
  const refresh = byId("refresh-review-center"); refresh.disabled = true; byId("review-center-status").textContent = "Loading bounded approval and activity projections…";
  try {
    const [approvalEnvelope, activityEnvelope] = await Promise.all([callSoul("approvals.pending", { limit: 50 }), callSoul("activities.recent", { limit: 100, filters: {} })]);
    if (approvalEnvelope.lifecycle_state !== "complete" || activityEnvelope.lifecycle_state !== "complete") throw new Error("Review projections failed safely");
    state.approvals = dataOf(approvalEnvelope).records || []; state.activitySummary = dataOf(activityEnvelope).records || []; state.activities = state.activitySummary; state.activityFilter = "all"; state.selectedApproval = null; state.selectedActivity = null; state.reviewLoaded = true;
    document.querySelectorAll("[data-activity-filter]").forEach((button) => button.classList.toggle("is-active", button.dataset.activityFilter === "all")); renderReviewSummary(); renderApprovalList(); renderActivityList(); byId("review-center-status").textContent = `Loaded ${state.approvals.length} pending approval${state.approvals.length === 1 ? "" : "s"} and ${state.activities.length} recent activity record${state.activities.length === 1 ? "" : "s"}.`;
  } catch (error) { byId("review-center-status").textContent = error.message || "Review Center failed safely."; }
  finally { refresh.disabled = false; }
}

function switchReviewView(name) {
  const approvals = name === "approvals"; byId("review-approvals-view").hidden = !approvals; byId("review-activity-view").hidden = approvals;
  byId("review-approvals-tab").classList.toggle("is-active", approvals); byId("review-activity-tab").classList.toggle("is-active", !approvals); byId("review-approvals-tab").setAttribute("aria-selected", String(approvals)); byId("review-activity-tab").setAttribute("aria-selected", String(!approvals));
}

function openReviewCenter() {
  state.reviewOpener = document.activeElement; byId("review-center").showModal(); byId("close-review-center").focus(); if (!state.reviewLoaded) loadReviewCenter();
}

function closeReviewCenter() { byId("review-center").close(); }

function resetVisualForm() {
  state.selectedVisualProject = null; state.visualPreview = null; state.visualProjectDeletePreview = null;
  byId("visual-project-form").reset(); byId("visual-seed").value = String(Math.floor(Math.random() * 2147483647));
  byId("visual-workbench-title").textContent = "New visual"; byId("save-visual-project").hidden = false; byId("update-visual-project").hidden = true; byId("visual-project-release").hidden = true;
  byId("visual-generation-card").hidden = true; byId("visual-candidates").hidden = true; byId("visual-project-delete").hidden = true; byId("visual-form-status").textContent = "";
  byId("preview-native-motion").disabled = true; byId("visual-native-motion-confirm").hidden = true; byId("visual-native-motion-confirm").replaceChildren(); byId("visual-native-motion-status").textContent = "Select or create a visual project first.";
  renderVisualProjects();
}

function visualProjectInput() {
  return { title: byId("visual-title").value, intent: byId("visual-intent").value, prompt: byId("visual-prompt").value, negative_prompt: byId("visual-negative").value, aspect_ratio: byId("visual-aspect").value, seed: Number(byId("visual-seed").value) };
}

function renderVisualProjects() {
  const active = state.visualProjects.filter((project) => (project.release_state || "active") === "active"); const released = state.visualProjects.filter((project) => project.release_state === "released"); const visible = state.visualProjectView === "released" ? released : active;
  byId("visual-folder-active").textContent = `Active · ${active.length}`; byId("visual-folder-released").textContent = `Released · ${released.length}`; byId("visual-folder-active").classList.toggle("is-active", state.visualProjectView === "active"); byId("visual-folder-released").classList.toggle("is-active", state.visualProjectView === "released");
  const list = byId("visual-project-list"); list.replaceChildren(); byId("visual-project-count").textContent = String(visible.length);
  if (!visible.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = state.visualProjectView === "released" ? "No released visual projects." : "No active visual projects."; list.append(empty); return; }
  visible.forEach((project) => {
    const button = document.createElement("button"); button.type = "button"; button.className = "studio-item";
    if (state.selectedVisualProject?.project_id === project.project_id) button.classList.add("is-active");
    const title = document.createElement("strong"); title.textContent = project.title; const meta = document.createElement("small"); meta.textContent = `${project.aspect_ratio} · seed ${project.seed}`;
    button.append(title, meta); button.addEventListener("click", () => selectVisualProject(project.project_id)); list.append(button);
  });
}

function setVisualProjectView(view) { state.visualProjectView = view; state.selectedVisualProject = null; resetVisualForm(); }

function renderVisualCandidates(project) {
  const candidates = project.candidates || []; const motions = project.motions || []; const list = byId("visual-candidate-list"); list.replaceChildren();
  byId("visual-candidate-count").textContent = String(candidates.length + motions.length); byId("visual-candidates").hidden = candidates.length === 0 && motions.length === 0;
  candidates.forEach((candidate) => {
    const card = document.createElement("article"); card.className = "visual-candidate";
    const image = document.createElement("img"); image.alt = `${project.title} visual draft`; image.loading = "lazy"; image.src = `/api/v1/visual/image/${project.project_id}/${candidate.candidate_id}`;
    const footer = document.createElement("footer"); const timing = document.createElement("span"); timing.textContent = `${candidate.elapsed_seconds}s · ${candidate.generation_kind === "image_edit" ? "guided edit" : "text draft"}`; const stateLabel = document.createElement("span"); stateLabel.textContent = candidate.review ? `${candidate.review.disposition} · ${candidate.review.rating}/5` : "Review required";
    footer.append(timing, stateLabel);
    const controls = document.createElement("div"); controls.className = "visual-candidate-controls";
    const rating = document.createElement("select"); rating.ariaLabel = "Visual rating"; [1,2,3,4,5].forEach((value) => { const option = document.createElement("option"); option.value = String(value); option.textContent = `${value} · ${["failed","weak","workable","strong","exceptional"][value - 1]}`; rating.append(option); }); rating.value = String(candidate.review?.rating || 3);
    const disposition = document.createElement("select"); disposition.ariaLabel = "Visual disposition"; [["keep","Keep"],["revise","Revise"]].forEach(([value,label]) => { const option = document.createElement("option"); option.value = value; option.textContent = label; disposition.append(option); }); disposition.value = candidate.review?.disposition || "keep";
    const notes = document.createElement("textarea"); notes.rows = 3; notes.maxLength = 8000; notes.placeholder = "What worked, what should change, and why."; notes.value = candidate.review?.notes || "";
    const reviewButton = document.createElement("button"); reviewButton.type = "button"; reviewButton.className = "gate-button"; reviewButton.textContent = "Record review";
    const editButton = document.createElement("button"); editButton.type = "button"; editButton.className = "gate-button"; editButton.textContent = "Revise from this image";
    const promoteButton = document.createElement("button"); promoteButton.type = "button"; promoteButton.className = "gate-button gate-button--gold"; promoteButton.textContent = "Bind to Music candidate";
    const motionButton = document.createElement("button"); motionButton.type = "button"; motionButton.className = "gate-button gate-button--gold"; motionButton.textContent = "Create motion study"; motionButton.disabled = candidate.review?.disposition !== "keep";
    const deleteButton = document.createElement("button"); deleteButton.type = "button"; deleteButton.className = "danger-button"; deleteButton.textContent = "Delete candidate";
    const status = document.createElement("p"); status.className = "dialog-status"; status.role = "status";
    const gate = document.createElement("div"); gate.className = "visual-candidate-gate"; gate.hidden = true;
    reviewButton.addEventListener("click", async () => { reviewButton.disabled = true; try { const envelope = await callSoul("visual.candidates.review", { visual_project_id: project.project_id, visual_candidate_id: candidate.candidate_id, visual_review: { rating: Number(rating.value), disposition: disposition.value, notes: notes.value } }); lifecycle(envelope); await selectVisualProject(project.project_id); } catch (error) { status.textContent = error.message; reviewButton.disabled = false; } });
    editButton.addEventListener("click", () => renderVisualEditGate(gate, project, candidate, status));
    promoteButton.addEventListener("click", () => renderVisualPromotionGate(gate, project, candidate, status));
    motionButton.addEventListener("click", () => renderVisualMotionGate(gate, project, candidate, status));
    deleteButton.addEventListener("click", () => previewVisualCandidateDeletion(gate, project, candidate, status));
    controls.append(rating, disposition, notes, reviewButton, editButton, motionButton, promoteButton, deleteButton, gate, status);
    card.append(image, footer, controls); list.append(card);
  });
  motions.forEach((motion) => list.append(renderVisualMotionCandidate(project, motion)));
}

function renderVisualMotionCandidate(project, motion) {
  const card = document.createElement("article"); card.className = "visual-candidate visual-motion-candidate";
  const video = document.createElement("video"); video.controls = true; video.loop = true; video.muted = true; video.preload = "none"; video.src = `/api/v1/visual/motion/${project.project_id}/${motion.motion_candidate_id}`; video.setAttribute("aria-label", `${project.title} generated motion study`);
  const footer = document.createElement("footer"); const timing = document.createElement("span"); const isNative = ["text_to_video", "text_to_video_revision"].includes(motion.generation_kind); const kind = isNative ? (motion.generation_kind === "text_to_video_revision" ? "native scene revision" : "native scene") : "image-guided motion"; const duration = Number(motion.duration_seconds); const durationLabel = Number.isFinite(duration) && Math.abs(duration - Math.round(duration)) < 0.1 ? String(Math.round(duration)) : String(motion.duration_seconds); timing.textContent = `${durationLabel}s ${kind} · ${motion.elapsed_seconds}s render`; const stateLabel = document.createElement("span"); stateLabel.textContent = motion.review ? `${motion.review.disposition} · ${motion.review.rating}/5` : "Motion review required"; footer.append(timing, stateLabel);
  const controls = document.createElement("div"); controls.className = "visual-candidate-controls";
  const rating = document.createElement("select"); [1,2,3,4,5].forEach((value) => { const option = document.createElement("option"); option.value = String(value); option.textContent = `${value} · ${["failed","weak","workable","strong","exceptional"][value - 1]}`; rating.append(option); }); rating.value = String(motion.review?.rating || 3);
  const disposition = document.createElement("select"); [["keep","Keep"],["revise","Revise"]].forEach(([value,label]) => { const option = document.createElement("option"); option.value = value; option.textContent = label; disposition.append(option); }); disposition.value = motion.review?.disposition || "keep";
  const notes = document.createElement("textarea"); notes.rows = 3; notes.maxLength = 8000; notes.placeholder = "Motion stability, fidelity, pacing, and visible artifacts."; notes.value = motion.review?.notes || "";
  const review = document.createElement("button"); review.type = "button"; review.className = "gate-button"; review.textContent = "Record motion review";
  const revise = document.createElement("button"); revise.type = "button"; revise.className = "gate-button"; revise.textContent = "Revise native scene"; revise.disabled = !isNative || motion.review?.disposition !== "revise"; revise.hidden = !isNative;
  const bind = document.createElement("button"); bind.type = "button"; bind.className = "gate-button gate-button--gold"; bind.textContent = "Bind motion to Music"; bind.disabled = motion.review?.disposition !== "keep";
  const remove = document.createElement("button"); remove.type = "button"; remove.className = "danger-button"; remove.textContent = "Delete motion study";
  const gate = document.createElement("div"); gate.className = "visual-candidate-gate"; gate.hidden = true; const status = document.createElement("p"); status.className = "dialog-status";
  review.addEventListener("click", async () => { review.disabled = true; try { const envelope = await callSoul("visual.motion.review", { visual_project_id: project.project_id, motion_candidate_id: motion.motion_candidate_id, visual_review: { rating: Number(rating.value), disposition: disposition.value, notes: notes.value } }); lifecycle(envelope); await selectVisualProject(project.project_id); } catch (error) { status.textContent = error.message; review.disabled = false; } });
  revise.addEventListener("click", () => renderNativeMotionRevisionGate(gate, project, motion, status));
  bind.addEventListener("click", () => renderVisualMotionPromotionGate(gate, project, motion, status));
  remove.addEventListener("click", async () => { remove.disabled = true; try { const envelope = await callSoul("visual.motion.delete.preview", { visual_project_id: project.project_id, motion_candidate_id: motion.motion_candidate_id }); lifecycle(envelope); const scope = dataOf(envelope); const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2); const execute = document.createElement("button"); execute.type = "button"; execute.className = "danger-button"; execute.textContent = "Permanently delete exact motion"; execute.addEventListener("click", async () => { execute.disabled = true; try { const result = await callSoul("visual.motion.delete.execute", { visual_project_id: project.project_id, motion_candidate_id: motion.motion_candidate_id, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }); lifecycle(result); await selectVisualProject(project.project_id); } catch (error) { status.textContent = error.message; execute.disabled = false; } }); gate.replaceChildren(summary, execute); gate.hidden = false; } catch (error) { status.textContent = error.message; remove.disabled = false; } });
  controls.append(rating, disposition, notes, review, revise, bind, remove, gate, status); card.append(video, footer, controls); return card;
}

function renderNativeMotionRevisionGate(gate, project, motion, status) {
  gate.replaceChildren(); gate.hidden = false;
  const label = document.createElement("label"); label.textContent = "Revised native scene direction"; const instruction = document.createElement("textarea"); instruction.rows = 8; instruction.maxLength = 8000; instruction.value = motion.review?.notes || motion.instruction || ""; label.append(instruction);
  const seedLabel = document.createElement("label"); seedLabel.textContent = "Revision seed"; const seed = document.createElement("input"); seed.type = "number"; seed.min = "0"; seed.max = "2147483647"; seed.value = String(Math.floor(Math.random() * 2147483647)); seedLabel.append(seed);
  const durationLabel = document.createElement("label"); durationLabel.textContent = "Duration"; const duration = document.createElement("select"); [["4","4 seconds"],["8","8 seconds"],["12","12 seconds"]].forEach(([value, text]) => { const option = document.createElement("option"); option.value = value; option.textContent = text; duration.append(option); }); duration.value = Number(motion.duration_seconds) >= 11 ? "12" : (Number(motion.duration_seconds) >= 7 ? "8" : "4"); durationLabel.append(duration);
  const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button gate-button--gold"; preview.textContent = "Preview native revision";
  const progress = createGenerationProgress();
  preview.addEventListener("click", async () => {
    preview.disabled = true; status.textContent = "Verifying the exact native-scene revision…";
    try {
      const envelope = await callSoul("visual.native_motion.revision.preview", { visual_project_id: project.project_id, source_motion_candidate_id: motion.motion_candidate_id, instruction: instruction.value, seed: seed.value, duration_seconds: duration.value }); lifecycle(envelope); const scope = dataOf(envelope);
      if (!scope.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Native-scene revision preview failed safely");
      const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2);
      const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = "Generate exact native revision";
      execute.addEventListener("click", async () => {
        execute.disabled = true; status.textContent = "Generating the approved native-scene revision…"; showGenerationProgress(progress, { stage: "preparing", message: "Engaging FastWan for the revised scene." });
        try {
          const result = await callNdjson("/api/v1/music-stream", "visual.native_motion.revision.execute", { visual_project_id: project.project_id, source_motion_candidate_id: motion.motion_candidate_id, motion_candidate_id: scope.motion_candidate_id, instruction: instruction.value, seed: seed.value, duration_seconds: duration.value, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }, {}, (event) => showGenerationProgress(progress, event));
          requireLifecycle(result, ["blocked_for_human_review"], "Native-scene revision failed safely"); await selectVisualProject(project.project_id); status.textContent = "Native-scene revision generated. Review the new candidate below.";
          emitSoulNotification("visual_ready", `visual:${scope.motion_candidate_id}`);
        } catch (error) { status.textContent = error.message; execute.disabled = false; emitSoulNotification("attention"); } finally { hideGenerationProgress(progress); }
      });
      gate.append(summary, execute, progress); status.textContent = "The exact revised direction, seed, duration, and model are ready for approval.";
    } catch (error) { status.textContent = error.message; preview.disabled = false; }
  });
  gate.append(label, seedLabel, durationLabel, preview, progress);
}

function renderVisualMotionGate(gate, project, candidate, status) {
  gate.replaceChildren(); gate.hidden = false;
  const label = document.createElement("label"); label.textContent = "Motion direction"; const instruction = document.createElement("textarea"); instruction.rows = 5; instruction.maxLength = 2000; instruction.value = "Locked camera. Preserve the exact composition, subject geometry, lighting, and color palette. Add restrained, physically coherent ambient motion within the scene. No zoom, pan, cuts, or new objects."; label.append(instruction);
  const seedLabel = document.createElement("label"); seedLabel.textContent = "Motion seed"; const seed = document.createElement("input"); seed.type = "number"; seed.min = "0"; seed.max = "2147483647"; seed.value = String(Math.floor(Math.random() * 2147483647)); seedLabel.append(seed);
  const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button"; preview.textContent = "Preview motion generation";
  const progress = createGenerationProgress();
  preview.addEventListener("click", async () => { preview.disabled = true; try { const envelope = await callSoul("visual.motion.preview", { visual_project_id: project.project_id, source_visual_candidate_id: candidate.candidate_id, instruction: instruction.value, seed: seed.value }); lifecycle(envelope); const scope = dataOf(envelope); if (!scope.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Motion runtime is not ready"); const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2); const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = "Generate exact motion study"; execute.addEventListener("click", async () => { execute.disabled = true; status.textContent = "Rendering bounded image-to-video study…"; showGenerationProgress(progress, { stage: "preparing", message: "Engaging Wan for the exact image-guided study." }); try { const result = await callNdjson("/api/v1/music-stream", "visual.motion.execute", { visual_project_id: project.project_id, source_visual_candidate_id: candidate.candidate_id, motion_candidate_id: scope.motion_candidate_id, instruction: instruction.value, seed: seed.value, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }, {}, (event) => showGenerationProgress(progress, event)); requireLifecycle(result, ["blocked_for_human_review"], "Motion generation failed safely"); await selectVisualProject(project.project_id); emitSoulNotification("visual_ready", `visual:${scope.motion_candidate_id}`); } catch (error) { status.textContent = error.message; execute.disabled = false; emitSoulNotification("attention"); } finally { hideGenerationProgress(progress); } }); gate.append(summary, execute, progress); } catch (error) { status.textContent = error.message; preview.disabled = false; } });
  gate.append(label, seedLabel, preview, progress);
}

function renderVisualEditGate(gate, project, candidate, status) {
  gate.replaceChildren(); gate.hidden = false;
  const label = document.createElement("label"); label.textContent = "Image-guided revision"; const instruction = document.createElement("textarea"); instruction.rows = 5; instruction.maxLength = 8000; instruction.placeholder = "Preserve the composition and architecture. Refine the distant horizon, deepen the cyan instrument light, and add subtle low mist."; label.append(instruction);
  const seedLabel = document.createElement("label"); seedLabel.textContent = "Revision seed"; const seed = document.createElement("input"); seed.type = "number"; seed.min = "0"; seed.max = "2147483647"; seed.value = String(Math.floor(Math.random() * 2147483647)); seedLabel.append(seed);
  const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button"; preview.textContent = "Preview guided edit";
  const progress = createGenerationProgress();
  preview.addEventListener("click", async () => { preview.disabled = true; try { const envelope = await callSoul("visual.edit.preview", { visual_project_id: project.project_id, source_visual_candidate_id: candidate.candidate_id, instruction: instruction.value, seed: seed.value }); lifecycle(envelope); const scope = dataOf(envelope); if (!scope.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Edit preview failed safely"); const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2); const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = "Generate exact guided edit"; execute.addEventListener("click", async () => { execute.disabled = true; status.textContent = "Rendering bounded image-guided revision…"; showGenerationProgress(progress, { stage: "preparing", message: "Engaging the visual runtime for the guided revision." }); try { const result = await callNdjson("/api/v1/music-stream", "visual.edit.execute", { visual_project_id: project.project_id, source_visual_candidate_id: candidate.candidate_id, visual_candidate_id: scope.candidate_id, instruction: instruction.value, seed: seed.value, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }, {}, (event) => showGenerationProgress(progress, event)); requireLifecycle(result, ["blocked_for_human_review"], "Guided visual revision failed safely"); await selectVisualProject(project.project_id); emitSoulNotification("visual_ready", `visual:${scope.candidate_id}`); } catch (error) { status.textContent = error.message; execute.disabled = false; emitSoulNotification("attention"); } finally { hideGenerationProgress(progress); } }); gate.append(summary, execute, progress); } catch (error) { status.textContent = error.message; preview.disabled = false; } });
  gate.append(label, seedLabel, preview, progress);
}

async function ensureVisualMusicProjects() {
  if (state.musicProjects.length) return state.musicProjects;
  const envelope = await callSoul("music.projects.list", { limit: 100 }); lifecycle(envelope); state.musicProjects = dataOf(envelope).projects || []; return state.musicProjects;
}

async function renderVisualPromotionGate(gate, project, candidate, status) {
  gate.replaceChildren(); gate.hidden = false; status.textContent = "Inspecting Music Studio candidates…";
  try {
    const projects = await ensureVisualMusicProjects(); if (!projects.length) throw new Error("Create and generate a Music Studio candidate before binding artwork.");
    const projectSelect = document.createElement("select"); const candidateSelect = document.createElement("select"); const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button"; preview.textContent = "Preview exact binding";
    projects.forEach((item) => { const option = document.createElement("option"); option.value = item.project_id; option.textContent = item.title; projectSelect.append(option); });
    const loadCandidates = async () => { candidateSelect.replaceChildren(); const envelope = await callSoul("music.projects.get", { project_id: projectSelect.value }); lifecycle(envelope); const candidates = dataOf(envelope).generations || []; candidates.forEach((item) => { const option = document.createElement("option"); option.value = item.candidate_id; option.textContent = `${item.candidate_id.slice(-8)} · ${item.created_at || "candidate"}`; candidateSelect.append(option); }); preview.disabled = candidates.length === 0; };
    projectSelect.addEventListener("change", loadCandidates); preview.addEventListener("click", async () => { preview.disabled = true; try { const envelope = await callSoul("visual.promotion.preview", { visual_project_id: project.project_id, visual_candidate_id: candidate.candidate_id, project_id: projectSelect.value, candidate_id: candidateSelect.value }); lifecycle(envelope); const scope = dataOf(envelope); if (!scope.expected_digest) { status.textContent = envelope.data?.message || "This exact image may already be bound."; return; } const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2); const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = "Bind exact visual companion"; execute.addEventListener("click", async () => { execute.disabled = true; try { const result = await callSoul("visual.promotion.execute", { visual_project_id: project.project_id, visual_candidate_id: candidate.candidate_id, project_id: projectSelect.value, candidate_id: candidateSelect.value, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }); lifecycle(result); status.textContent = "Bound to the exact Music candidate. Continue loop review in Music Studio."; } catch (error) { status.textContent = error.message; execute.disabled = false; } }); gate.append(summary, execute); } catch (error) { status.textContent = error.message; preview.disabled = false; } });
    gate.append(projectSelect, candidateSelect, preview); await loadCandidates(); status.textContent = "Choose the exact composition candidate to receive this still.";
  } catch (error) { status.textContent = error.message; }
}

async function renderVisualMotionPromotionGate(gate, project, motion, status) {
  gate.replaceChildren(); gate.hidden = false; status.textContent = "Inspecting Music Studio candidates…";
  try {
    const projects = await ensureVisualMusicProjects(); if (!projects.length) throw new Error("Create and generate a Music Studio candidate before binding motion.");
    const projectSelect = document.createElement("select"); const candidateSelect = document.createElement("select"); const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button"; preview.textContent = "Preview exact motion binding";
    projects.forEach((item) => { const option = document.createElement("option"); option.value = item.project_id; option.textContent = item.title; projectSelect.append(option); });
    const loadCandidates = async () => { candidateSelect.replaceChildren(); const envelope = await callSoul("music.projects.get", { project_id: projectSelect.value }); lifecycle(envelope); const candidates = dataOf(envelope).generations || []; candidates.forEach((item) => { const option = document.createElement("option"); option.value = item.candidate_id; option.textContent = `${item.candidate_id.slice(-8)} · ${item.created_at || "candidate"}`; candidateSelect.append(option); }); preview.disabled = candidates.length === 0; };
    projectSelect.addEventListener("change", loadCandidates);
    preview.addEventListener("click", async () => { preview.disabled = true; try { const envelope = await callSoul("visual.motion.promotion.preview", { visual_project_id: project.project_id, motion_candidate_id: motion.motion_candidate_id, project_id: projectSelect.value, candidate_id: candidateSelect.value }); lifecycle(envelope); const scope = dataOf(envelope); if (!scope.expected_digest) { status.textContent = "This exact motion may already be bound."; return; } const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2); const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = "Bind exact reviewed motion"; execute.addEventListener("click", async () => { execute.disabled = true; try { const result = await callSoul("visual.motion.promotion.execute", { visual_project_id: project.project_id, motion_candidate_id: motion.motion_candidate_id, project_id: projectSelect.value, candidate_id: candidateSelect.value, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }); lifecycle(result); status.textContent = "Motion bound. Create the full-duration preview in Music Studio."; } catch (error) { status.textContent = error.message; execute.disabled = false; } }); gate.append(summary, execute); } catch (error) { status.textContent = error.message; preview.disabled = false; } });
    gate.append(projectSelect, candidateSelect, preview); await loadCandidates(); status.textContent = "Choose the exact composition candidate to receive this reviewed motion.";
  } catch (error) { status.textContent = error.message; }
}

async function previewVisualCandidateDeletion(gate, project, candidate, status) {
  gate.replaceChildren(); gate.hidden = false;
  try { const envelope = await callSoul("visual.candidates.delete.preview", { visual_project_id: project.project_id, visual_candidate_id: candidate.candidate_id }); lifecycle(envelope); const scope = dataOf(envelope); const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2); const execute = document.createElement("button"); execute.type = "button"; execute.className = "danger-button"; execute.textContent = "Permanently delete exact candidate"; execute.addEventListener("click", async () => { execute.disabled = true; try { const result = await callSoul("visual.candidates.delete.execute", { visual_project_id: project.project_id, visual_candidate_id: candidate.candidate_id, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }); lifecycle(result); await selectVisualProject(project.project_id); } catch (error) { status.textContent = error.message; execute.disabled = false; } }); gate.append(summary, execute); } catch (error) { status.textContent = error.message; }
}

async function selectVisualProject(projectId) {
  try {
    const envelope = await callSoul("visual.projects.get", { visual_project_id: projectId }); lifecycle(envelope); const project = dataOf(envelope).project;
    state.selectedVisualProject = project; byId("visual-title").value = project.title; byId("visual-intent").value = project.intent; byId("visual-prompt").value = project.prompt; byId("visual-negative").value = project.negative_prompt; byId("visual-aspect").value = project.aspect_ratio; byId("visual-seed").value = String(project.seed);
    byId("visual-native-motion-instruction").value = project.prompt; byId("visual-native-motion-seed").value = String(project.seed);
    byId("visual-workbench-title").textContent = project.title; byId("save-visual-project").hidden = true; byId("update-visual-project").hidden = false; const release = byId("visual-project-release"); release.hidden = false; release.textContent = project.release_state === "released" ? "Restore to Active" : "Move to Released"; byId("visual-generation-card").hidden = false; byId("visual-project-delete").hidden = false; byId("visual-generation-confirm").hidden = true; byId("visual-project-delete-confirm").hidden = true; state.visualPreview = null; state.visualProjectDeletePreview = null;
    byId("preview-native-motion").disabled = false; byId("visual-native-motion-confirm").hidden = true; byId("visual-native-motion-confirm").replaceChildren(); byId("visual-native-motion-status").textContent = "The stored scene prompt is prefilled as an editable text-to-video direction; no still candidate is read.";
    renderVisualProjects(); renderVisualCandidates(project);
  } catch (error) { byId("visual-form-status").textContent = error.message; }
}

async function toggleVisualProjectRelease() {
  const project = state.selectedVisualProject; if (!project) return; const released = project.release_state === "released"; const button = byId("visual-project-release"); button.disabled = true;
  try { const envelope = await callSoul(released ? "visual.projects.restore" : "visual.projects.release", { visual_project_id: project.project_id }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || envelope.lifecycle_state); await loadVisualStudio(); resetVisualForm(); byId("visual-form-status").textContent = released ? "Visual project restored to Active. IDs and bindings were preserved." : "Visual project moved to Released. IDs and bindings were preserved."; }
  catch (error) { byId("visual-form-status").textContent = error.message; } finally { button.disabled = false; }
}

async function previewNativeMotion() {
  const project = state.selectedVisualProject; if (!project) return;
  const button = byId("preview-native-motion"); const status = byId("visual-native-motion-status"); const confirm = byId("visual-native-motion-confirm");
  const instruction = byId("visual-native-motion-instruction").value; const seed = byId("visual-native-motion-seed").value; const durationSeconds = byId("visual-native-motion-duration").value;
  button.disabled = true; status.textContent = "Verifying the native-video runtime, exact model, Core, and scene direction…"; confirm.hidden = true; confirm.replaceChildren();
  try {
    const envelope = await callSoul("visual.native_motion.preview", { visual_project_id: project.project_id, instruction, seed, duration_seconds: durationSeconds }); lifecycle(envelope); const scope = dataOf(envelope);
    if (!scope.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Native-video runtime is not ready");
    const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2);
    const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = "Generate exact native scene";
    const progress = createGenerationProgress();
    execute.addEventListener("click", async () => { execute.disabled = true; status.textContent = "Generating a bounded scene directly from text…"; showGenerationProgress(progress, { stage: "preparing", message: "Engaging FastWan for the exact native scene." }); try { const result = await callNdjson("/api/v1/music-stream", "visual.native_motion.execute", { visual_project_id: project.project_id, motion_candidate_id: scope.motion_candidate_id, instruction, seed, duration_seconds: durationSeconds, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }, {}, (event) => showGenerationProgress(progress, event)); requireLifecycle(result, ["blocked_for_human_review"], "Native scene generation failed safely"); await selectVisualProject(project.project_id); status.textContent = "Native scene generated. Review it below before binding it to music."; emitSoulNotification("visual_ready", `visual:${scope.motion_candidate_id}`); } catch (error) { status.textContent = error.message; execute.disabled = false; emitSoulNotification("attention"); } finally { hideGenerationProgress(progress); } });
    confirm.append(summary, execute, progress); confirm.hidden = false; status.textContent = "The exact scene direction, seed, model, duration, and output envelope are ready for approval.";
  } catch (error) { status.textContent = error.message; }
  finally { button.disabled = false; }
}

async function refreshVisualResources() {
  const button = byId("refresh-visual-resources"); button.disabled = true; byId("visual-form-status").textContent = "Verifying the pinned visual runtime and model files… the first pass may take several seconds.";
  try { const envelope = await callSoul("visual.resources.status"); lifecycle(envelope); const data = dataOf(envelope); const native = data.native_motion || {}; const label = byId("visual-resource-state"); label.textContent = data.ready && native.ready ? "Still + native video ready" : (data.ready ? `${data.profile} ready` : "Runtime attention"); label.classList.toggle("is-ready", data.ready && native.ready); byId("visual-form-status").textContent = data.ready ? `${data.accelerator} · still verified · native video ${native.ready ? `${native.profile} verified` : `attention (${(native.missing_roles || []).join(", ") || native.core?.reason || "runtime"})`} · ${data.core?.core_id || "bounded lane"}` : (data.core?.reason || `Missing: ${(data.missing_roles || []).join(", ") || "runtime"}`); }
  catch (error) { byId("visual-form-status").textContent = error.message; }
  finally { button.disabled = false; }
}

async function refreshMotionQualification() {
  const button = byId("refresh-motion-qualification"); const summary = byId("motion-qualification-summary"); const status = byId("motion-qualification-status");
  button.disabled = true; status.textContent = "Reading retained motion receipts and human reviews…";
  try {
    const envelope = await callSoul("visual.motion.qualification"); lifecycle(envelope); const data = dataOf(envelope);
    const overview = document.createElement("dl");
    [["Samples", data.sample_count], ["Human reviewed", data.reviewed_count], ["Awaiting review", data.unreviewed_count], ["Archive attention", (data.inspection_failures || []).length]].forEach(([label, value]) => {
      const row = document.createElement("div"); const term = document.createElement("dt"); const detail = document.createElement("dd"); term.textContent = label; detail.textContent = String(value); row.append(term, detail); overview.append(row);
    });
    const coverage = document.createElement("div");
    (data.coverage || []).forEach((item) => {
      const row = document.createElement("div"); row.className = "qualification-duration";
      const heading = document.createElement("strong"); heading.textContent = `${item.duration_seconds} seconds`;
      const evidence = document.createElement("span"); const rating = item.average_rating == null ? "no rating" : `${item.average_rating}/5 average`;
      evidence.textContent = `${item.reviewed_count}/${item.sample_count} reviewed · ${item.kept_count} kept · ${item.revise_count} revise · ${rating}`;
      row.append(heading, evidence); coverage.append(row);
    });
    const next = document.createElement("p"); next.className = "muted"; next.textContent = data.next_review;
    summary.replaceChildren(overview, coverage, next);
    status.textContent = `${String(data.evidence_state || "pending").replaceAll("_", " ")} · human qualification only`;
  } catch (error) {
    status.textContent = error.message;
  } finally {
    button.disabled = false;
  }
}

async function loadVisualStudio() {
  try { const envelope = await callSoul("visual.projects.list", { limit: 200 }); lifecycle(envelope); state.visualProjects = dataOf(envelope).projects || []; state.visualLoaded = true; renderVisualProjects(); await Promise.all([refreshVisualResources(), refreshMotionQualification()]); }
  catch (error) { byId("visual-form-status").textContent = error.message; }
}

async function createVisualProject(event) {
  event.preventDefault(); const visualProject = visualProjectInput();
  try { const envelope = await callSoul("visual.projects.create", { visual_project: visualProject }); lifecycle(envelope); const project = dataOf(envelope).project; state.visualProjects.unshift(project); await selectVisualProject(project.project_id); byId("visual-form-status").textContent = "Visual project created."; }
  catch (error) { byId("visual-form-status").textContent = error.message; }
}

async function updateVisualProject() {
  if (!state.selectedVisualProject) return;
  const button = byId("update-visual-project"); button.disabled = true; byId("visual-form-status").textContent = "Saving the revised brief…";
  try { const envelope = await callSoul("visual.projects.update", { visual_project_id: state.selectedVisualProject.project_id, visual_project: visualProjectInput() }); lifecycle(envelope); await loadVisualStudio(); await selectVisualProject(state.selectedVisualProject.project_id); byId("visual-form-status").textContent = "Revised brief saved. Existing candidate inputs remain immutable."; }
  catch (error) { byId("visual-form-status").textContent = error.message; }
  finally { button.disabled = false; }
}

async function previewVisualProjectDeletion() {
  if (!state.selectedVisualProject) return;
  try { const envelope = await callSoul("visual.projects.delete.preview", { visual_project_id: state.selectedVisualProject.project_id }); lifecycle(envelope); state.visualProjectDeletePreview = dataOf(envelope); byId("visual-project-delete-scope").textContent = JSON.stringify(state.visualProjectDeletePreview, null, 2); byId("visual-project-delete-confirm").hidden = false; byId("visual-project-delete-status").textContent = "Clicking delete authorizes only this exact inventoried project."; }
  catch (error) { byId("visual-project-delete-status").textContent = error.message; }
}

async function executeVisualProjectDeletion() {
  if (!state.selectedVisualProject || !state.visualProjectDeletePreview) return;
  const projectId = state.selectedVisualProject.project_id; const scope = state.visualProjectDeletePreview;
  try { const envelope = await callSoul("visual.projects.delete.execute", { visual_project_id: projectId, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }); lifecycle(envelope); state.visualProjects = state.visualProjects.filter((item) => item.project_id !== projectId); resetVisualForm(); byId("visual-form-status").textContent = "Visual project permanently deleted."; }
  catch (error) { byId("visual-project-delete-status").textContent = error.message; }
}

async function previewVisualGeneration() {
  if (!state.selectedVisualProject) return;
  const button = byId("preview-visual-generation"); button.disabled = true; byId("visual-generation-status").textContent = "Revalidating the exact visual project, Core, runtime, and pinned models…";
  try { const envelope = await callSoul("visual.generation.preview", { visual_project_id: state.selectedVisualProject.project_id }); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.data?.message || "Visual runtime is not ready"); state.visualPreview = data; byId("visual-generation-scope").textContent = JSON.stringify(data, null, 2); byId("visual-generation-confirm").hidden = false; byId("start-visual-generation").disabled = false; byId("visual-generation-status").textContent = "Clicking generate authorizes this exact local draft."; }
  catch (error) { byId("visual-generation-status").textContent = error.message; }
  finally { button.disabled = false; }
}

async function startVisualGeneration() {
  if (!state.visualPreview || state.visualGenerating) return; state.visualGenerating = true; byId("start-visual-generation").disabled = true; showGenerationProgress(byId("visual-progress"), { stage: "preparing", message: "Engaging the bounded visual runtime." });
  try {
    const parameters = { visual_project_id: state.visualPreview.project_id, visual_candidate_id: state.visualPreview.candidate_id, confirmation: state.visualPreview.confirmation_phrase, expected_digest: state.visualPreview.expected_digest };
    const envelope = await callNdjson("/api/v1/music-stream", "visual.generation.execute", parameters, {}, (event) => showGenerationProgress(byId("visual-progress"), event));
    requireLifecycle(envelope, ["blocked_for_human_review"], "Visual draft generation failed safely"); byId("visual-generation-status").textContent = "Visual draft generated; review the candidate below."; const candidateId = state.visualPreview.candidate_id; await selectVisualProject(state.visualPreview.project_id); emitSoulNotification("visual_ready", `visual:${candidateId}`);
  } catch (error) { byId("visual-generation-status").textContent = error.message; emitSoulNotification("attention"); }
  finally { state.visualGenerating = false; hideGenerationProgress(byId("visual-progress")); }
}

function backupPassword() {
  const password = byId("backup-password").value;
  if (!password) throw new Error("Enter the repository password for this operation.");
  return password;
}

function backupResult(envelope, accepted = ["complete"]) {
  const lifecycleState = envelope.lifecycle_state || "failed";
  if (!accepted.includes(lifecycleState)) throw new Error(envelope.errors?.[0]?.message || "Backup administration stopped safely.");
  return dataOf(envelope);
}

function renderBackupFacts(target, facts) {
  target.replaceChildren();
  Object.entries(facts).forEach(([term, value]) => {
    const row = document.createElement("div");
    const dt = document.createElement("dt"); dt.textContent = term;
    const dd = document.createElement("dd"); dd.textContent = String(value);
    row.append(dt, dd); target.append(row);
  });
}

function renderBackupSnapshots(snapshots) {
  const list = byId("backup-snapshot-list"); list.replaceChildren();
  state.backupSnapshots = Array.isArray(snapshots) ? snapshots : [];
  byId("backup-snapshot-count").textContent = String(state.backupSnapshots.length);
  if (!state.backupSnapshots.length) {
    const empty = document.createElement("p"); empty.className = "muted";
    empty.textContent = byId("backup-password").value ? "No Soul state snapshots were found." : "Enter the repository password to inspect encrypted history.";
    list.append(empty); return;
  }
  state.backupSnapshots.forEach((snapshot, index) => {
    const row = document.createElement("div"); row.className = `backup-snapshot${index === 0 ? " is-newest" : ""}`;
    const controls = document.createElement("div"); controls.className = "backup-snapshot-controls";
    const retain = document.createElement("input"); retain.type = "checkbox"; retain.className = "backup-retention-select"; retain.value = snapshot.id;
    retain.disabled = index === 0; retain.title = index === 0 ? "The newest snapshot cannot be forgotten" : "Select for retention";
    const restore = document.createElement("input"); restore.type = "radio"; restore.name = "backup-restore-snapshot"; restore.value = snapshot.id;
    restore.title = "Select for staged restore";
    controls.append(retain, restore);
    const copy = document.createElement("div");
    const heading = document.createElement("strong"); heading.textContent = `${snapshot.short_id || snapshot.id.slice(0, 8)}${index === 0 ? " · newest" : ""}`;
    const time = document.createElement("span"); time.textContent = snapshot.time || "time unavailable";
    const detail = document.createElement("small"); detail.textContent = `${snapshot.hostname || "unknown host"} · ${Array.isArray(snapshot.paths) ? snapshot.paths.length : 0} recorded roots`;
    copy.append(heading, time, detail); row.append(controls, copy); list.append(row);
  });
}

function renderBackupStatus(payload) {
  const mount = payload.mount || {};
  const ready = payload.available && payload.configured && mount.mounted && mount.writable && mount.expected_target;
  byId("backup-repository-state").textContent = ready ? "READY" : "ATTENTION";
  renderBackupFacts(byId("backup-repository-details"), {
    "Repository": payload.repository || "Unavailable",
    "Mount": mount.target || "Unavailable",
    "Filesystem": mount.filesystem || "Unavailable",
    "Write state": mount.mounted ? (mount.writable ? "writable" : "read only") : "not mounted",
    "Configuration": payload.configured ? `${payload.source_count} sources` : "not configured"
  });
  byId("backup-ledger-state").textContent = payload.ledger_present ? "PRESENT" : "BASELINE";
  renderBackupFacts(byId("backup-ledger-details"), {
    "Ledger": payload.ledger_present ? "Deletion evidence available" : "Created by first verified capture",
    "Retention": "30 days after source deletion",
    "Automation": "Disabled",
    "Password": "Never retained"
  });
  byId("backup-receipt-count").textContent = String(payload.receipt_count || 0);
  renderBackupFacts(byId("backup-evidence-details"), {
    "Receipts": payload.receipt_count || 0,
    "Staged restores": payload.restore_count || 0,
    "Snapshot access": payload.snapshot_access || "locked",
    "Live promotion": "External human procedure"
  });
  renderBackupSnapshots(payload.snapshots);
  const status = !payload.available ? "Restic is unavailable."
    : !payload.configured ? "Backup source and exclusion manifests need configuration."
      : !mount.mounted ? "The configured recovery target is not mounted."
        : !mount.expected_target ? "The repository is not on the configured recovery mount."
          : !mount.writable ? "The recovery target is mounted read-only; capture and retention are blocked."
            : payload.snapshot_access === "unlocked" ? "Encrypted history unlocked for this page session." : "Recovery target inspected; enter the repository password to unlock history.";
  byId("backup-status").textContent = status;
}

async function loadBackupAdministration({ unlock = false } = {}) {
  byId("refresh-backup").disabled = true;
  try {
    const parameters = {};
    if (unlock) parameters.password = backupPassword();
    const envelope = await callSoul("backup.status", parameters);
    renderBackupStatus(backupResult(envelope));
    state.backupLoaded = true;
  } catch (error) { byId("backup-status").textContent = error.message; }
  finally { byId("refresh-backup").disabled = false; }
}

function resetBackupPreviews() {
  state.backupCreatePreview = null; state.backupRetentionPreview = null; state.backupRestorePreview = null;
  ["backup-create-confirm", "backup-retention-confirm", "backup-restore-confirm"].forEach((id) => { byId(id).hidden = true; });
}

function selectedBackupSnapshotIds() {
  return Array.from(document.querySelectorAll(".backup-retention-select:checked")).map((input) => input.value);
}

function selectedBackupRestoreId() {
  return document.querySelector('input[name="backup-restore-snapshot"]:checked')?.value || "";
}

function backupRestorePaths() {
  return byId("backup-restore-paths").value.split("\n").map((line) => line.trim()).filter(Boolean);
}

async function previewBackupCreate() {
  byId("preview-backup-create").disabled = true;
  try {
    const envelope = await callSoul("backup.create.preview", { password: backupPassword() });
    state.backupCreatePreview = backupResult(envelope);
    byId("backup-create-scope").textContent = JSON.stringify({
      sources: state.backupCreatePreview.sources,
      estimated_bytes: state.backupCreatePreview.estimated_bytes,
      prior_snapshot_id: state.backupCreatePreview.prior_snapshot_id,
      verification: state.backupCreatePreview.verification
    }, null, 2);
    byId("backup-create-confirm").hidden = false;
    byId("backup-create-status").textContent = "Exact capture scope prepared. Clicking the gold gate supplies the displayed authority.";
  } catch (error) { byId("backup-create-status").textContent = error.message; }
  finally { byId("preview-backup-create").disabled = false; }
}

async function executeBackupCreate() {
  if (!state.backupCreatePreview || state.backupBusy) return;
  state.backupBusy = true; byId("execute-backup-create").disabled = true;
  const progress = byId("backup-create-progress");
  try {
    showGenerationProgress(progress, { stage: "preparing", message: "Revalidating the exact capture scope." });
    const envelope = await callNdjson("/api/v1/administration-stream", "backup.create.execute", {
      password: backupPassword(), confirmation: state.backupCreatePreview.confirmation_phrase,
      expected_digest: state.backupCreatePreview.expected_digest
    }, {}, (event) => showGenerationProgress(progress, event));
    const result = backupResult(envelope);
    byId("backup-create-status").textContent = `Verified snapshot ${result.snapshot_id?.slice(0, 12) || "created"}; receipt recorded.`;
    resetBackupPreviews(); await loadBackupAdministration({ unlock: true });
  } catch (error) { byId("backup-create-status").textContent = error.message; }
  finally { state.backupBusy = false; byId("execute-backup-create").disabled = false; hideGenerationProgress(progress); }
}

async function previewBackupRetention() {
  byId("preview-backup-retention").disabled = true;
  try {
    const snapshotIds = selectedBackupSnapshotIds();
    const envelope = await callSoul("backup.retention.preview", { password: backupPassword(), snapshot_ids: snapshotIds });
    state.backupRetentionPreview = backupResult(envelope);
    byId("backup-retention-scope").textContent = JSON.stringify({
      selected_snapshot_ids: state.backupRetentionPreview.selected_snapshot_ids,
      remaining_snapshot_count: state.backupRetentionPreview.remaining_snapshot_count,
      max_repack_size: state.backupRetentionPreview.max_repack_size,
      post_operation_check: state.backupRetentionPreview.post_operation_check
    }, null, 2);
    byId("backup-retention-confirm").hidden = false;
    byId("backup-retention-status").textContent = "Exact hold-clear snapshot set prepared. No other snapshot may be forgotten by this gate.";
  } catch (error) { byId("backup-retention-status").textContent = error.message; }
  finally { byId("preview-backup-retention").disabled = false; }
}

async function executeBackupRetention() {
  if (!state.backupRetentionPreview || state.backupBusy) return;
  state.backupBusy = true; byId("execute-backup-retention").disabled = true;
  const progress = byId("backup-retention-progress");
  try {
    showGenerationProgress(progress, { stage: "preparing", message: "Revalidating snapshot holds and inventory." });
    const envelope = await callNdjson("/api/v1/administration-stream", "backup.retention.execute", {
      password: backupPassword(), snapshot_ids: state.backupRetentionPreview.selected_snapshot_ids,
      confirmation: state.backupRetentionPreview.confirmation_phrase, expected_digest: state.backupRetentionPreview.expected_digest
    }, {}, (event) => showGenerationProgress(progress, event));
    const result = backupResult(envelope);
    byId("backup-retention-status").textContent = `${result.forgotten_snapshot_ids?.length || 0} exact snapshots forgotten; repository verification passed.`;
    resetBackupPreviews(); await loadBackupAdministration({ unlock: true });
  } catch (error) { byId("backup-retention-status").textContent = error.message; }
  finally { state.backupBusy = false; byId("execute-backup-retention").disabled = false; hideGenerationProgress(progress); }
}

async function previewBackupRestore() {
  byId("preview-backup-restore").disabled = true;
  try {
    const envelope = await callSoul("backup.restore.preview", {
      password: backupPassword(), snapshot_id: selectedBackupRestoreId(), paths: backupRestorePaths()
    });
    state.backupRestorePreview = backupResult(envelope);
    byId("backup-restore-scope").textContent = JSON.stringify({
      snapshot_id: state.backupRestorePreview.snapshot_id,
      scope: state.backupRestorePreview.scope,
      includes: state.backupRestorePreview.includes,
      target_root: state.backupRestorePreview.target_root,
      live_tree_mutation: false
    }, null, 2);
    byId("backup-restore-confirm").hidden = false;
    byId("backup-restore-status").textContent = "Exact isolated restore prepared. The operation stops after staging and verification.";
  } catch (error) { byId("backup-restore-status").textContent = error.message; }
  finally { byId("preview-backup-restore").disabled = false; }
}

async function executeBackupRestore() {
  if (!state.backupRestorePreview || state.backupBusy) return;
  state.backupBusy = true; byId("execute-backup-restore").disabled = true;
  const progress = byId("backup-restore-progress");
  try {
    showGenerationProgress(progress, { stage: "preparing", message: "Revalidating the exact isolated restore." });
    const envelope = await callNdjson("/api/v1/administration-stream", "backup.restore.execute", {
      password: backupPassword(), snapshot_id: state.backupRestorePreview.snapshot_id,
      paths: state.backupRestorePreview.includes, confirmation: state.backupRestorePreview.confirmation_phrase,
      expected_digest: state.backupRestorePreview.expected_digest
    }, {}, (event) => showGenerationProgress(progress, event));
    const result = backupResult(envelope, ["blocked_for_human_review"]);
    byId("backup-restore-status").textContent = `Restore verified in ${result.staged_path}; live state remains unchanged.`;
    resetBackupPreviews(); await loadBackupAdministration({ unlock: true });
  } catch (error) { byId("backup-restore-status").textContent = error.message; }
  finally { state.backupBusy = false; byId("execute-backup-restore").disabled = false; hideGenerationProgress(progress); }
}

async function bootstrap() {
  if (state.bootstrapped) return;
  state.bootstrapped = true;
  try {
    const envelope = await callSoul("application.bootstrap"); lifecycle(envelope); const data = dataOf(envelope); const providers = data.providers?.providers || [];
    const active = providers.find((provider) => provider.available || provider.configured) || providers[0]; byId("provider-label").textContent = active ? `Provider ${active.id || active.name || "ready"}` : "Provider local";
    byId("config-label").textContent = data.configuration?.ok ? "Config valid" : "Config attention"; switchTab(tabFromLocation() || "chat"); await loadChats(true); await refreshCores({ automatic: true }); await refreshStatus({ automatic: true }); await refreshModelRuntime({ automatic: true }); await refreshVoicePresence();
  } catch (error) { state.bootstrapped = false; byId("connection-label").textContent = "Disconnected"; showError(error); }
}

byId("login-form").addEventListener("submit", login);
byId("password-change-form").addEventListener("submit", changePassword);
byId("logout-button").addEventListener("click", logout);
byId("voice-presence-launch").addEventListener("click", launchVoicePresence);
byId("core-selector").addEventListener("click", () => setCoreMenu(byId("core-menu").hidden));
byId("review-center-button").addEventListener("click", openReviewCenter);
byId("close-review-center").addEventListener("click", closeReviewCenter);
byId("refresh-review-center").addEventListener("click", loadReviewCenter);
byId("review-approvals-tab").addEventListener("click", () => switchReviewView("approvals"));
byId("review-activity-tab").addEventListener("click", () => switchReviewView("activity"));
document.querySelectorAll("[data-activity-filter]").forEach((button) => button.addEventListener("click", () => filterReviewActivity(button.dataset.activityFilter)));
byId("review-center").addEventListener("close", () => { if (state.reviewOpener instanceof HTMLElement) state.reviewOpener.focus(); });
byId("review-center").addEventListener("click", (event) => { if (event.target === byId("review-center")) closeReviewCenter(); });
byId("chat-tab").addEventListener("click", () => switchTab("chat"));
byId("timeline-tab").addEventListener("click", () => switchTab("timeline"));
byId("self-improvement-tab").addEventListener("click", () => setSelfImprovementMenu(byId("self-improvement-menu").hidden));
byId("creative-tab").addEventListener("click", () => setCreativeMenu(byId("creative-menu").hidden));
byId("administration-tab").addEventListener("click", () => setAdministrationMenu(byId("administration-menu").hidden));
byId("studio-tab").addEventListener("click", () => switchTab("studio"));
byId("improvement-tab").addEventListener("click", () => switchTab("improvement"));
byId("augmentation-tab").addEventListener("click", () => switchTab("augmentation"));
byId("music-tab").addEventListener("click", () => switchTab("music"));
byId("visual-tab").addEventListener("click", () => switchTab("visual"));
byId("maintenance-tab").addEventListener("click", () => switchTab("maintenance"));
byId("backup-tab").addEventListener("click", () => switchTab("backup"));
byId("refresh-maintenance-fleet").addEventListener("click", loadMaintenanceFleet);
byId("scan-maintenance-subnet").addEventListener("click", scanMaintenanceSubnet);
byId("refresh-maintenance-registry").addEventListener("click", loadMaintenanceDiscovery);
byId("maintenance-enrollment-mode").addEventListener("change", () => {
  const ssh = byId("maintenance-enrollment-mode").value === "ssh";
  byId("maintenance-enrollment-ssh-row").hidden = !ssh;
  byId("maintenance-enrollment-policy").disabled = ssh;
  if (ssh) byId("maintenance-enrollment-policy").value = "fixed";
  resetMaintenanceEnrollmentPreview();
});
["maintenance-enrollment-label", "maintenance-enrollment-ssh-alias", "maintenance-enrollment-policy"].forEach((id) => byId(id).addEventListener("input", resetMaintenanceEnrollmentPreview));
byId("preview-maintenance-enrollment").addEventListener("click", previewMaintenanceEnrollment);
byId("execute-maintenance-enrollment").addEventListener("click", executeMaintenanceEnrollment);
byId("execute-maintenance-removal").addEventListener("click", executeMaintenanceRemoval);
byId("maintenance-ignore-label").addEventListener("input", () => {
  if (state.maintenanceIgnoreMode === "ignore") {
    state.maintenanceIgnorePreview = null; byId("maintenance-ignore-scope").hidden = true; byId("execute-maintenance-ignore").disabled = true;
  }
});
byId("preview-maintenance-ignore").addEventListener("click", previewMaintenanceIgnore);
byId("execute-maintenance-ignore").addEventListener("click", executeMaintenanceIgnoreMutation);
byId("maintenance-device-confirmation").addEventListener("input", () => {
  const preview = state.maintenanceDevicePreview;
  const expected = preview && (preview.data.confirmation || preview.plan.confirmation);
  const available = preview && (canonicalMaintenanceDeviceId(preview.deviceId) === "workstation" ? preview.plan.execution_available === true : preview.plan.live_execution_enabled === true);
  byId("execute-maintenance-device-action").disabled = !available || byId("maintenance-device-confirmation").value !== expected;
});
byId("execute-maintenance-device-action").addEventListener("click", executeMaintenanceDeviceAction);
byId("refresh-maintenance-device-evidence").addEventListener("click", refreshWorkstationDeviceEvidence);
byId("recheck-maintenance-device-preflight").addEventListener("click", recheckWorkstationDevicePreflight);
byId("maintenance-device-dialog").addEventListener("close", () => {
  state.maintenanceDevicePreview = null;
  byId("maintenance-device-confirmation").value = "";
});
byId("preview-maintenance-execution").addEventListener("click", previewMaintenanceExecution);
byId("refresh-maintenance-evidence").addEventListener("click", refreshNativeMaintenanceEvidence);
byId("rehearse-maintenance-execution").addEventListener("click", () => runMaintenanceExecution("rehearsal"));
byId("execute-maintenance").addEventListener("click", () => runMaintenanceExecution("live"));
byId("refresh-maintenance-receipt").addEventListener("click", loadMaintenanceReceipts);
byId("preview-maintenance-reboot").addEventListener("click", previewMaintenanceReboot);
byId("execute-maintenance-reboot").addEventListener("click", executeMaintenanceReboot);
byId("refresh-maintenance-reboot-status").addEventListener("click", loadMaintenanceRebootStatus);
byId("refresh-backup").addEventListener("click", () => loadBackupAdministration({ unlock: true }));
byId("forget-backup-password").addEventListener("click", () => {
  byId("backup-password").value = ""; resetBackupPreviews(); renderBackupSnapshots([]);
  byId("backup-status").textContent = "Repository password forgotten; encrypted history is locked.";
});
byId("preview-backup-create").addEventListener("click", previewBackupCreate);
byId("execute-backup-create").addEventListener("click", executeBackupCreate);
byId("preview-backup-retention").addEventListener("click", previewBackupRetention);
byId("execute-backup-retention").addEventListener("click", executeBackupRetention);
byId("preview-backup-restore").addEventListener("click", previewBackupRestore);
byId("execute-backup-restore").addEventListener("click", executeBackupRestore);
byId("new-timeline-item").addEventListener("click", () => openTimelineEditor());
byId("refresh-timeline").addEventListener("click", () => loadProjectTimeline({ announceLoad: true }));
byId("timeline-status-filter").addEventListener("change", renderProjectTimeline);
byId("timeline-editor").addEventListener("submit", saveTimelineItem);
byId("close-timeline-editor").addEventListener("click", closeTimelineEditor);
window.addEventListener("hashchange", () => { const tab = tabFromLocation(); if (tab) switchTab(tab, { updateLocation: false }); });
document.addEventListener("click", (event) => { if (!byId("self-improvement-navigation").contains(event.target)) setSelfImprovementMenu(false); if (!byId("creative-navigation").contains(event.target)) setCreativeMenu(false); if (!byId("administration-navigation").contains(event.target)) setAdministrationMenu(false); if (!byId("core-navigation").contains(event.target)) setCoreMenu(false); });
byId("self-improvement-navigation").addEventListener("keydown", (event) => { if (event.key === "Escape") { setSelfImprovementMenu(false); byId("self-improvement-tab").focus(); } });
byId("core-navigation").addEventListener("keydown", (event) => { if (event.key === "Escape") { setCoreMenu(false); byId("core-selector").focus(); } });
byId("creative-navigation").addEventListener("keydown", (event) => { if (event.key === "Escape") { setCreativeMenu(false); byId("creative-tab").focus(); } });
byId("administration-navigation").addEventListener("keydown", (event) => { if (event.key === "Escape") { setAdministrationMenu(false); byId("administration-tab").focus(); } });
byId("new-visual-project").addEventListener("click", resetVisualForm);
byId("visual-folder-active").addEventListener("click", () => setVisualProjectView("active"));
byId("visual-folder-released").addEventListener("click", () => setVisualProjectView("released"));
byId("visual-project-release").addEventListener("click", toggleVisualProjectRelease);
byId("visual-project-form").addEventListener("submit", createVisualProject);
byId("update-visual-project").addEventListener("click", updateVisualProject);
byId("refresh-visual-resources").addEventListener("click", refreshVisualResources);
byId("preview-visual-generation").addEventListener("click", previewVisualGeneration);
byId("preview-native-motion").addEventListener("click", previewNativeMotion);
byId("refresh-motion-qualification").addEventListener("click", refreshMotionQualification);
byId("start-visual-generation").addEventListener("click", startVisualGeneration);
byId("preview-visual-project-delete").addEventListener("click", previewVisualProjectDeletion);
byId("execute-visual-project-delete").addEventListener("click", executeVisualProjectDeletion);
byId("new-music-project").addEventListener("click", resetMusicForm);
byId("music-folder-active").addEventListener("click", () => setMusicProjectView("active"));
byId("music-folder-released").addEventListener("click", () => setMusicProjectView("released"));
byId("music-project-release").addEventListener("click", toggleMusicProjectRelease);
byId("music-project-form").addEventListener("submit", createMusicProject);
byId("music-vocal-mode").addEventListener("change", syncMusicCompositionMode);
byId("refresh-music-resources").addEventListener("click", refreshMusicResources);
byId("preview-music-reference").addEventListener("click", previewMusicReference);
byId("music-reference-confirmation").addEventListener("input", () => { byId("analyze-music-reference").disabled = !state.musicReferencePreview || byId("music-reference-confirmation").value !== state.musicReferencePreview.confirmation_phrase; });
byId("analyze-music-reference").addEventListener("click", analyzeMusicReference);
byId("draft-music-reference-synthesis").addEventListener("click", draftMusicReferenceSynthesis);
byId("draft-music-reference-fusion").addEventListener("click", draftMusicReferenceFusion);
byId("preview-music-reference-synthesis-approval").addEventListener("click", previewMusicReferenceSynthesisApproval);
byId("preview-music-reference-synthesis-rejection").addEventListener("click", previewMusicReferenceSynthesisRejection);
byId("music-reference-synthesis-confirmation").addEventListener("input", () => { byId("approve-music-reference-synthesis").disabled = !state.musicSynthesisApproval || byId("music-reference-synthesis-confirmation").value !== state.musicSynthesisApproval.confirmation_phrase; });
byId("approve-music-reference-synthesis").addEventListener("click", approveMusicReferenceSynthesis);
byId("music-reference-synthesis-reject-confirmation").addEventListener("input", () => { byId("reject-music-reference-synthesis").disabled = !state.musicSynthesisRejection || byId("music-reference-synthesis-reject-confirmation").value !== state.musicSynthesisRejection.confirmation_phrase; });
byId("reject-music-reference-synthesis").addEventListener("click", rejectMusicReferenceSynthesis);
byId("preview-music-reference-delete").addEventListener("click", previewMusicReferenceDelete);
byId("music-reference-delete-confirmation").addEventListener("input", () => { byId("delete-music-reference").disabled = !state.musicReferenceDelete || byId("music-reference-delete-confirmation").value !== state.musicReferenceDelete.confirmation_phrase; });
byId("delete-music-reference").addEventListener("click", deleteMusicReference);
byId("reanalyze-music-reference").addEventListener("click", previewMusicReferenceReanalysis);
byId("music-reference-reanalysis-confirmation").addEventListener("input", () => { byId("execute-music-reference-reanalysis").disabled = !state.musicReferenceReanalysis || byId("music-reference-reanalysis-confirmation").value !== state.musicReferenceReanalysis.confirmation_phrase; });
byId("execute-music-reference-reanalysis").addEventListener("click", executeMusicReferenceReanalysis);
byId("preview-music-generation").addEventListener("click", previewMusicGeneration);
byId("preview-music-project-delete").addEventListener("click", previewMusicProjectDelete);
byId("music-project-delete-confirmation").addEventListener("input", () => { byId("execute-music-project-delete").disabled = !state.musicProjectDeletePreview || byId("music-project-delete-confirmation").value !== state.musicProjectDeletePreview.confirmation_phrase; });
byId("execute-music-project-delete").addEventListener("click", executeMusicProjectDelete);
byId("music-generation-confirmation").addEventListener("input", () => { byId("start-music-generation").disabled = !state.musicPreview || byId("music-generation-confirmation").value !== state.musicPreview.confirmation_phrase; });
byId("start-music-generation").addEventListener("click", startMusicGeneration);
byId("cancel-music-generation").addEventListener("click", cancelMusicGeneration);
document.querySelectorAll("[data-assessment-scope]").forEach((button) => button.addEventListener("click", () => refreshSelfImprovement(button.dataset.assessmentScope)));
byId("preview-improvement-proposals").addEventListener("click", previewImprovementProposals);
byId("improvement-proposal-confirmation").addEventListener("input", () => { byId("execute-improvement-proposals").disabled = !state.improvementProposalPreview || byId("improvement-proposal-confirmation").value !== state.improvementProposalPreview.confirmation_phrase; });
byId("execute-improvement-proposals").addEventListener("click", executeImprovementProposals);
byId("preview-storage-cleanup").addEventListener("click", previewStorageCleanup);
byId("preview-host-plan").addEventListener("click", previewHostPlan);
byId("host-plan-confirmation").addEventListener("input", () => { byId("create-host-plan").disabled = !state.hostPlanPreview || byId("host-plan-confirmation").value !== state.hostPlanPreview.confirmation_phrase; });
byId("create-host-plan").addEventListener("click", createHostPlan);
byId("verify-host-plan").addEventListener("click", verifyHostPlan);
byId("preview-maintenance").addEventListener("click", previewMaintenance);
byId("rehearse-maintenance").addEventListener("click", rehearseMaintenance);
byId("maintenance-force-refresh").addEventListener("change", () => {
  state.maintenancePreview = null;
  byId("rehearse-maintenance").disabled = true;
  byId("maintenance-rehearsal-output").hidden = true;
  byId("maintenance-rehearsal-status").textContent = "Refresh the preview after changing the package mode.";
});
byId("run-augmentation-census").addEventListener("click", runAugmentationCensus);
byId("preview-augmentation-proposal").addEventListener("click", previewAugmentationProposal);
byId("augmentation-confirmation").addEventListener("input", () => { byId("create-augmentation-proposal").disabled = !state.augmentationPreview || byId("augmentation-confirmation").value !== state.augmentationPreview.confirmation_phrase; });
byId("create-augmentation-proposal").addEventListener("click", createAugmentationProposal);
byId("preview-augmentation-experiment").addEventListener("click", previewAugmentationExperiment);
byId("augmentation-allowed-files").addEventListener("input", () => { state.augmentationExperimentPreview = null; byId("augmentation-experiment-preview").hidden = true; });
byId("augmentation-experiment-confirmation").addEventListener("input", () => { byId("create-augmentation-experiment").disabled = !state.augmentationExperimentPreview || byId("augmentation-experiment-confirmation").value !== state.augmentationExperimentPreview.confirmation_phrase; });
byId("create-augmentation-experiment").addEventListener("click", createAugmentationExperiment);
byId("generate-augmentation-dossier").addEventListener("click", generateAugmentationDossier);
byId("preview-augmentation-gate-a2").addEventListener("click", previewAugmentationGateA2);
byId("augmentation-gate-a2-confirmation").addEventListener("input", () => { byId("execute-augmentation-gate-a2").disabled = !state.augmentationGateA2Preview || byId("augmentation-gate-a2-confirmation").value !== state.augmentationGateA2Preview.confirmation_phrase; });
byId("execute-augmentation-gate-a2").addEventListener("click", executeAugmentationGateA2);
byId("preview-augmentation-cleanup").addEventListener("click", previewAugmentationCleanup);
byId("augmentation-cleanup-confirmation").addEventListener("input", () => { byId("execute-augmentation-cleanup").disabled = !state.augmentationCleanupPreview || byId("augmentation-cleanup-confirmation").value !== state.augmentationCleanupPreview.confirmation_phrase; });
byId("execute-augmentation-cleanup").addEventListener("click", executeAugmentationCleanup);
byId("preview-augmentation-model-result").addEventListener("click", previewAugmentationModelResult);
byId("augmentation-model-confirmation").addEventListener("input", () => { byId("record-augmentation-model-result").disabled = !state.augmentationModelPreview || byId("augmentation-model-confirmation").value !== state.augmentationModelPreview.confirmation_phrase; });
byId("record-augmentation-model-result").addEventListener("click", recordAugmentationModelResult);
byId("preview-proposal-approval").addEventListener("click", previewProposalApproval);
byId("proposal-confirmation").addEventListener("input", () => { byId("execute-proposal-approval").disabled = !state.proposalApproval || byId("proposal-confirmation").value !== "APPROVE_PROPOSAL_FOR_BETA_BUILD"; });
byId("execute-proposal-approval").addEventListener("click", executeProposalApproval);
byId("preview-beta-build").addEventListener("click", previewBetaBuild);
byId("beta-build-skill-id").addEventListener("input", () => { state.betaBuildPreview = null; byId("beta-build-confirm").hidden = true; });
byId("beta-build-confirmation").addEventListener("input", () => { byId("execute-beta-build").disabled = !state.betaBuildPreview || byId("beta-build-confirmation").value !== state.betaBuildPreview.confirmation_phrase; });
byId("execute-beta-build").addEventListener("click", executeBetaBuild);
byId("view-linked-skill").addEventListener("click", () => { if (state.selectedProposal?.linked_skill_id) focusProductionSkill(state.selectedProposal.linked_skill_id); });
byId("preview-proposal-close").addEventListener("click", previewProposalClose);
byId("proposal-close-confirmation").addEventListener("input", () => { byId("execute-proposal-close").disabled = !state.proposalClosePreview || byId("proposal-close-confirmation").value !== "CLOSE_PRODUCTION_PROPOSAL"; });
byId("execute-proposal-close").addEventListener("click", executeProposalClose);
byId("preview-beta-run").addEventListener("click", previewBetaRun);
byId("beta-run-confirmation").addEventListener("input", () => { byId("execute-beta-run").disabled = !state.betaRunPreview || byId("beta-run-confirmation").value !== state.betaRunPreview.confirmation_phrase; });
byId("execute-beta-run").addEventListener("click", executeBetaRun);
byId("preview-beta-promotion").addEventListener("click", previewBetaPromotion);
byId("beta-promotion-confirmation").addEventListener("input", () => { byId("execute-beta-promotion").disabled = !state.betaPromotionPreview?.ready || byId("beta-promotion-confirmation").value !== "APPROVE_BETA_FOR_PROMOTION"; });
byId("execute-beta-promotion").addEventListener("click", executeBetaPromotion);
byId("preview-production-promotion").addEventListener("click", previewProductionPromotion);
byId("production-promotion-confirmation").addEventListener("input", () => { byId("execute-production-promotion").disabled = !state.productionPromotionPreview || byId("production-promotion-confirmation").value !== state.productionPromotionPreview.confirmation_phrase; });
byId("execute-production-promotion").addEventListener("click", executeProductionPromotion);
byId("new-chat").addEventListener("click", createChat);
byId("clear-chats").addEventListener("click", openClearDialog);
byId("close-clear-dialog").addEventListener("click", () => byId("clear-dialog").close());
byId("clear-mode").addEventListener("change", () => { setClearModeFields(); resetConversationPreviews(); });
byId("clear-title").addEventListener("input", resetConversationPreviews);
byId("select-all-clear").addEventListener("click", () => { byId("clear-selection-list").querySelectorAll('input[type="checkbox"]').forEach((input) => { input.checked = true; }); updateClearSelectionCount(); resetConversationPreviews(); });
byId("select-none-clear").addEventListener("click", () => { byId("clear-selection-list").querySelectorAll('input[type="checkbox"]').forEach((input) => { input.checked = false; }); updateClearSelectionCount(); resetConversationPreviews(); });
byId("preview-clear").addEventListener("click", previewClear);
byId("clear-confirmation").addEventListener("input", () => { byId("execute-clear").disabled = !state.clearPreview || byId("clear-confirmation").value !== "CLEAR_CONVERSATIONS"; });
byId("execute-clear").addEventListener("click", executeClear);
byId("preview-forget").addEventListener("click", previewForget);
byId("forget-confirmation").addEventListener("input", () => { byId("execute-forget").disabled = !state.forgetPreview || byId("forget-confirmation").value !== state.forgetPreview.confirmation; });
byId("execute-forget").addEventListener("click", executeForget);
byId("pin-chat").addEventListener("click", togglePin);
byId("refresh-status").addEventListener("click", refreshStatus);
byId("refresh-model-runtime").addEventListener("click", refreshModelRuntime);
byId("load-model-runtime").addEventListener("click", () => previewModelRuntime("load"));
byId("unload-model-runtime").addEventListener("click", () => previewModelRuntime("unload"));
byId("close-model-runtime-dialog").addEventListener("click", () => byId("model-runtime-dialog").close());
byId("model-runtime-confirmation").addEventListener("input", () => { byId("execute-model-runtime").disabled = !state.modelRuntimePreview || byId("model-runtime-confirmation").value !== state.modelRuntimePreview.confirmation; });
byId("execute-model-runtime").addEventListener("click", executeModelRuntime);
byId("composer").addEventListener("submit", sendMessage);
byId("attach-picture").addEventListener("click", () => byId("picture-input").click());
byId("picture-input").addEventListener("change", selectPictureAttachment);
byId("picture-attachment-remove").addEventListener("click", () => { clearPictureAttachment(); byId("message-input").focus(); });
byId("capture-screen").addEventListener("click", openScreenCaptureDialog);
byId("execute-screen-capture").addEventListener("click", captureScreenPreview);
byId("record-voice").addEventListener("click", toggleVoiceRecording);
byId("notification-mode").addEventListener("click", cycleNotificationMode);
byId("open-invocation-catalog").addEventListener("click", openInvocationCatalog);
byId("close-invocation-catalog").addEventListener("click", closeInvocationCatalog);
byId("refresh-invocation-catalog").addEventListener("click", loadInvocationCatalog);
byId("invocation-category").addEventListener("change", renderInvocationCatalog);
byId("invocation-query").addEventListener("input", renderInvocationCatalog);
byId("invocation-catalog").addEventListener("click", (event) => { if (event.target === byId("invocation-catalog")) closeInvocationCatalog(); });
renderNotificationMode();
byId("voice-output-profile").value = state.voiceOutputProfile;
byId("voice-output-profile").addEventListener("change", (event) => {
  const voice = event.target.value;
  if (!VOICE_OUTPUT_PROFILES.has(voice)) { event.target.value = state.voiceOutputProfile; return; }
  stopVoicePlayback(); state.voiceOutputProfile = voice;
  try { localStorage.setItem("soul.voice.output.profile", voice); } catch (_error) { /* browser preference remains session-local */ }
  announce(`${event.target.selectedOptions[0].textContent} selected for the next spoken response`);
});
byId("voice-output-quality").value = state.voiceOutputQuality;
byId("voice-output-quality").addEventListener("change", (event) => {
  const quality = event.target.value;
  if (!VOICE_OUTPUT_QUALITIES.has(quality)) { event.target.value = state.voiceOutputQuality; return; }
  stopVoicePlayback(); state.voiceOutputQuality = quality;
  try { localStorage.setItem("soul.voice.output.quality", quality); } catch (_error) { /* browser preference remains session-local */ }
  announce(`${event.target.selectedOptions[0].textContent} delivery selected`);
});
byId("message-input").addEventListener("keydown", (event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); if (state.busy) { announce("Soul is still working; the draft was not sent or used as an interruption."); return; } byId("composer").requestSubmit(); } });
syncMusicCompositionMode();
initializeAuthentication();
