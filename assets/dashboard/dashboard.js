"use strict";

const csrf = document.querySelector('meta[name="soul-csrf"]').content;
const TAB_LOCATIONS = Object.freeze({ chat: "#chat-panel", studio: "#studio-panel", improvement: "#improvement-panel", augmentation: "#augmentation-panel", music: "#music-panel", visual: "#visual-panel" });
const state = { authenticated: false, bootstrapped: false, chats: [], activeChat: null, busy: false, clearPreview: null, forgetPreview: null, coreStatus: null, modelRuntime: null, modelRuntimePreview: null, studioLoaded: false, proposals: [], betas: [], productionSkills: [], linkedProductionSkill: null, selectedProposal: null, selectedBeta: null, proposalApproval: null, betaBuildPreview: null, proposalClosePreview: null, betaRunPreview: null, betaPromotionPreview: null, productionPromotionPreview: null, improvementLoaded: false, improvementProposalPreview: null, hostPlanPreview: null, selectedHostPlan: null, augmentationLoaded: false, augmentationPreview: null, augmentationProposals: [], selectedAugmentationProposal: null, augmentationExperiments: [], selectedAugmentationExperiment: null, augmentationExperimentPreview: null, augmentationGateA2Preview: null, augmentationCleanupPreview: null, augmentationModelPreview: null, musicLoaded: false, musicProjects: [], musicReferences: { artists: [], tracks: [], fusions: [] }, musicReferencePreview: null, musicReferenceAnalyzing: false, selectedMusicReference: null, musicReferenceDelete: null, musicReferenceReanalysis: null, musicSynthesisApproval: null, musicSynthesisRejection: null, musicSynthesisBusy: false, musicFusionSources: new Set(), selectedMusicProject: null, musicProjectDeletePreview: null, musicPreview: null, musicGenerating: false, musicCandidateId: null, reviewLoaded: false, approvals: [], activities: [], activitySummary: [], activityFilter: "all", selectedApproval: null, selectedActivity: null, reviewOpener: null };
const byId = (id) => document.getElementById(id);
state.musicJobId = null;
Object.assign(state, { visualLoaded: false, visualProjects: [], selectedVisualProject: null, visualPreview: null, visualGenerating: false, visualProjectDeletePreview: null });

function formatBytes(value) {
  const bytes = Number(value); if (!Number.isFinite(bytes) || bytes < 0) return "unavailable";
  const units = ["B", "KiB", "MiB", "GiB", "TiB"]; let amount = bytes; let unit = 0;
  while (amount >= 1024 && unit < units.length - 1) { amount /= 1024; unit += 1; }
  return `${amount >= 10 || unit === 0 ? amount.toFixed(0) : amount.toFixed(1)} ${units[unit]}`;
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

async function callNdjson(endpoint, operation, parameters = {}, context = {}, onProgress = () => {}) {
  if (endpoint === "/api/v1/music-stream" && ["music.generation.execute", "music.candidates.revision.execute"].includes(operation)) endpoint = "/api/v1/music-job-stream";
  const response = await fetch(endpoint, {
    method: "POST", credentials: "same-origin",
    headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf },
    body: JSON.stringify({ schema_version: "soul.application.v1", request_id: requestId(), operation, parameters, context: { interface: "dashboard", ...context } }),
    cache: "no-store"
  });
  if (!response.ok || !response.body) { const failure = await response.json().catch(() => ({})); throw new Error(failure.error?.reason || "Chat stream failed safely"); }
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

const callSoulStream = (operation, parameters = {}, context = {}, onProgress = () => {}) => callNdjson("/api/v1/chat-stream", operation, parameters, context, onProgress);

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
  [document.querySelector(".app-header"), document.querySelector("main"), byId("review-center"), byId("clear-dialog"), byId("model-runtime-dialog")].forEach((element) => { if (element) element.inert = locked; });
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

function setSoulActivity(activityState, summary) {
  const presence = byId("soul-presence"); if (!presence) return;
  presence.dataset.state = activityState || "idle";
  const titles = { idle: "Soul is listening.", received: "Transmission received.", context: "Reading the thread.", planning: "Tracing a path.", inspecting: "Inspecting local evidence.", researching: "Following public signals.", synthesizing: "Shaping a response.", drafting: "Preparing an artifact.", reviewing: "Reviewing the result.", finalizing: "Sealing continuity.", complete: "Soul is present.", failed: "The path closed safely." };
  byId("soul-presence-title").textContent = titles[activityState] || "Soul is working.";
  byId("soul-activity-summary").textContent = summary || "Foreground work remains bounded to this request.";
}

function setBusy(busy, message = "") {
  state.busy = busy;
  byId("send-message").disabled = busy || !state.activeChat;
  byId("message-input").disabled = !state.activeChat;
  byId("send-message").querySelector("span").textContent = busy ? "Working" : "Send";
  byId("composer-hint").textContent = busy ? "Soul is working · you may draft, but ordinary Enter will not interrupt" : (state.activeChat ? "Ready · local continuity enabled" : "No conversation selected");
  if (message) announce(message);
}

function tabFromLocation() { return Object.entries(TAB_LOCATIONS).find(([, hash]) => hash === window.location.hash)?.[0] || null; }

function switchTab(name, { updateLocation = true } = {}) {
  if (!Object.hasOwn(TAB_LOCATIONS, name)) name = "chat";
  const chat = name === "chat";
  const studio = name === "studio";
  const improvement = name === "improvement";
  const augmentation = name === "augmentation";
  const music = name === "music";
  const visual = name === "visual";
  const selfImprovement = studio || improvement || augmentation;
  const creative = music || visual;
  byId("chat-panel").hidden = !chat;
  byId("studio-panel").hidden = !studio;
  byId("improvement-panel").hidden = !improvement;
  byId("augmentation-panel").hidden = !augmentation;
  byId("music-panel").hidden = !music;
  byId("visual-panel").hidden = !visual;
  byId("chat-tab").classList.toggle("is-active", chat);
  byId("self-improvement-tab").classList.toggle("is-active", selfImprovement);
  byId("studio-tab").classList.toggle("is-active", studio);
  byId("improvement-tab").classList.toggle("is-active", improvement);
  byId("augmentation-tab").classList.toggle("is-active", augmentation);
  byId("creative-tab").classList.toggle("is-active", creative);
  byId("music-tab").classList.toggle("is-active", music);
  byId("visual-tab").classList.toggle("is-active", visual);
  byId("chat-tab").setAttribute("aria-selected", String(chat));
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
  setSelfImprovementMenu(false);
  setCreativeMenu(false);
  if (updateLocation && window.location.hash !== TAB_LOCATIONS[name]) window.history.replaceState(null, "", TAB_LOCATIONS[name]);
  if (studio && state.authenticated && !state.studioLoaded) loadSkillStudio();
  if (improvement && state.authenticated && !state.improvementLoaded) loadSelfImprovement();
  if (augmentation && state.authenticated && !state.augmentationLoaded) loadSelfAugmentation();
  if (music && state.authenticated && !state.musicLoaded) loadMusicStudio();
  if (visual && state.authenticated && !state.visualLoaded) loadVisualStudio();
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
    const meta = document.createElement("small"); meta.textContent = chat.updated_at ? `updated ${formatTime(chat.updated_at)}` : chat.id;
    copy.append(title, meta); button.append(sigil, copy);
    if (chat.pinned) { const pin = document.createElement("span"); pin.className = "pin"; pin.textContent = "PIN"; button.append(pin); }
    button.addEventListener("click", () => selectChat(chat)); list.append(button);
  });
}

function formatTime(value) {
  const date = new Date(value); return Number.isNaN(date.valueOf()) ? "recently" : date.toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

async function loadChats(selectFirst = true) {
  const envelope = await callSoul("chats.list", { limit: 50 }); lifecycle(envelope);
  state.chats = dataOf(envelope).records || []; renderChatList();
  if (selectFirst && !state.activeChat && state.chats.length) await selectChat(state.chats[0]);
  if (!state.chats.length) resetConversationView();
}

function resetConversationView() {
  state.activeChat = null;
  byId("active-chat-kicker").textContent = "No active thread";
  byId("active-chat-title").textContent = "Open a conversation";
  byId("pin-chat").disabled = true;
  byId("pin-chat").textContent = "Pin";
  byId("message-input").disabled = true;
  byId("message-input").placeholder = "Create a conversation to begin…";
  byId("send-message").disabled = true;
  byId("composer-hint").textContent = "No conversation selected";
  renderMessages([], true); renderWorkspace([]); renderInbox({ records: [] });
}

async function selectChat(chat) {
  state.activeChat = chat; renderChatList();
  byId("active-chat-kicker").textContent = chat.id;
  byId("active-chat-title").textContent = chat.title || "Untitled conversation";
  byId("pin-chat").disabled = false; byId("pin-chat").textContent = chat.pinned ? "Unpin" : "Pin";
  byId("composer-hint").textContent = "Local provider request · foreground only";
  byId("message-input").placeholder = "Write a message to Soul…"; setBusy(true, "Loading conversation");
  try {
    const [messages, workspace, inbox] = await Promise.all([
      callSoul("chats.messages", { chat_id: chat.id, limit: 200 }, { current_chat_id: chat.id }),
      callSoul("workspace.chat", { chat_id: chat.id, limit: 50 }, { current_chat_id: chat.id }),
      callSoul("inbox.list", { chat_id: chat.id, limit: 50 }, { current_chat_id: chat.id })
    ]);
    lifecycle(messages); renderMessages(dataOf(messages).records || []); renderWorkspace(dataOf(workspace).records || []); renderInbox(dataOf(inbox));
    announce(`Opened ${chat.title || "conversation"}`);
  } catch (error) { showError(error); } finally { setBusy(false); }
}

function messageArticle(record, { pending = false, working = false } = {}) {
  const article = document.createElement("article"); const role = record.role === "user" ? "user" : "assistant"; article.className = `message message--${role}`;
  if (pending) article.classList.add("message--pending"); if (working) article.classList.add("message--working");
  const label = document.createElement("div"); label.className = "message-label"; label.textContent = role === "user" ? (pending ? "You · sending" : "You") : "Soul /";
  const body = document.createElement("div"); body.className = "message-body"; body.textContent = record.content || record.text || ""; article.append(label, body); return article;
}

function renderMessages(records, noChat = false) {
  const area = byId("messages"); area.replaceChildren();
  if (!records.length) { const empty = document.createElement("div"); empty.className = "empty-state"; const copy = document.createElement("div"); const eyebrow = document.createElement("p"); eyebrow.className = "eyebrow"; eyebrow.textContent = noChat ? "Active list clear" : "Fresh context"; const heading = document.createElement("h2"); heading.textContent = noChat ? "Create a conversation when you’re ready." : "This conversation is ready."; const note = document.createElement("p"); note.textContent = noChat ? "Archived transcripts remain stored locally and are not deleted." : "Your first message will use Soul’s configured provider and shared context boundary."; copy.append(eyebrow, heading, note); empty.append(copy); area.append(empty); return; }
  records.forEach((record) => area.append(messageArticle(record)));
  area.scrollTop = area.scrollHeight;
}

function appendPendingExchange(message) {
  const area = byId("messages"); area.querySelector(".empty-state")?.remove(); area.append(messageArticle({ role: "user", content: message }, { pending: true }));
  const working = messageArticle({ role: "assistant", content: "Reading the transmission…" }, { working: true }); working.id = "soul-working-message"; area.append(working); area.scrollTop = area.scrollHeight;
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

async function loadMusicStudio() {
  state.musicLoaded = true;
  try {
    const envelope = await callSoul("music.projects.list", { limit: 100 }); lifecycle(envelope);
    state.musicProjects = dataOf(envelope).projects || []; renderMusicProjects(); await loadMusicReferences(); await refreshMusicReferenceStatus(); await refreshMusicResources();
    if (state.musicProjects.length) await selectMusicProject(state.musicProjects[0]);
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
  byId("music-project-count").textContent = String(state.musicProjects.length); const list = byId("music-project-list"); list.replaceChildren();
  if (!state.musicProjects.length) { const p = document.createElement("p"); p.className = "muted"; p.textContent = "No compositions yet."; list.append(p); return; }
  state.musicProjects.forEach((project) => { const button = document.createElement("button"); button.type = "button"; button.className = `studio-item${state.selectedMusicProject?.project_id === project.project_id ? " is-active" : ""}`; const title = document.createElement("strong"); title.textContent = project.title; const meta = document.createElement("small"); meta.textContent = `${project.target_duration_seconds}s · ${project.vocal_mode} · ${project.bpm} BPM`; button.append(title, meta); button.addEventListener("click", () => selectMusicProject(project)); list.append(button); });
}

function resetMusicForm() {
  state.selectedMusicProject = null; state.musicProjectDeletePreview = null; state.musicPreview = null; byId("music-project-form").reset(); byId("music-project-form").querySelectorAll("input,textarea,select").forEach((field) => { field.disabled = false; }); byId("music-bpm").value = "110"; byId("music-key").value = "C minor"; byId("music-time").value = "4"; byId("music-seed").value = String(Math.floor(Math.random() * 2147483647)); byId("music-workbench-title").textContent = "New composition"; byId("save-music-project").hidden = false; byId("music-project-delete-card").hidden = true; byId("music-project-delete-confirm").hidden = true; byId("music-generation-card").hidden = true; byId("music-candidates").hidden = true; byId("music-form-status").textContent = "A new project preserves its exact creative inputs."; renderMusicProjects();
}

async function createMusicProject(event) {
  event.preventDefault(); byId("save-music-project").disabled = true;
  try { const envelope = await callSoul("music.projects.create", { project: musicProjectInput() }); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Project needs attention"); state.musicLoaded = false; await loadMusicStudio(); byId("music-form-status").textContent = "Project created. Preview before generation."; } catch (error) { byId("music-form-status").textContent = error.message; } finally { byId("save-music-project").disabled = false; }
}

async function selectMusicProject(project) {
  try { const envelope = await callSoul("music.projects.get", { project_id: project.project_id }); lifecycle(envelope); const data = dataOf(envelope); state.selectedMusicProject = data.project; state.musicProjectDeletePreview = null; state.musicPreview = null; renderMusicProjects(); const p = data.project; byId("music-workbench-title").textContent = p.title; byId("music-title").value = p.title; byId("music-intent").value = p.intent; byId("music-duration").value = String(p.target_duration_seconds); byId("music-vocal-mode").value = p.vocal_mode; byId("music-rights").value = p.rights_status; byId("music-bpm").value = String(p.bpm); byId("music-key").value = p.keyscale; byId("music-time").value = p.timesignature; byId("music-seed").value = String(p.seed); byId("music-caption").value = p.caption; byId("music-lyrics").value = p.lyrics; byId("music-project-form").querySelectorAll("input,textarea,select").forEach((field) => { field.disabled = true; }); byId("save-music-project").hidden = true; byId("music-project-delete-card").hidden = false; byId("music-project-delete-confirm").hidden = true; byId("music-project-delete-status").textContent = "Preview inventories this project before permanent deletion."; byId("music-generation-card").hidden = false; byId("music-generation-confirm").hidden = true; renderMusicCandidates(data.generations || []); } catch (error) { byId("music-form-status").textContent = error.message; }
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
  if (!state.musicPreview || state.musicGenerating) return; state.musicGenerating = true; byId("start-music-generation").disabled = true; byId("cancel-music-generation").disabled = false; byId("music-progress").hidden = false;
  const params = { project_id: state.selectedMusicProject.project_id, candidate_id: state.musicPreview.candidate_id, confirmation: byId("music-generation-confirmation").value, expected_digest: state.musicPreview.expected_digest };
  try { const envelope = await callNdjson("/api/v1/music-stream", "music.generation.execute", params, {}, (event) => { byId("music-progress-stage").textContent = (event.stage || "working").replaceAll("_", " "); const line = String(event.message || "").trim().split("\n").filter(Boolean).pop(); if (line) byId("music-progress-message").textContent = line.slice(0, 240); }); lifecycle(envelope); byId("music-generation-status").textContent = envelope.lifecycle_state === "blocked_for_human_review" ? "Candidate complete. Listen and record adherence evidence below." : (envelope.errors?.[0]?.message || envelope.lifecycle_state); await selectMusicProject(state.selectedMusicProject); } catch (error) { byId("music-generation-status").textContent = error.message; } finally { state.musicGenerating = false; byId("cancel-music-generation").disabled = true; byId("music-progress").hidden = true; }
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
    byId("cancel-music-generation").disabled = false; byId("music-progress").hidden = false;
    showMusicProgress(job.latest_progress || { stage: "working", message: "Reattached to the active bounded generation job." });
    const envelope = await followMusicJob(job.job_id, showMusicProgress); lifecycle(envelope);
    if (state.selectedMusicProject?.project_id === projectId) { byId("music-generation-status").textContent = envelope.lifecycle_state === "blocked_for_human_review" ? "Candidate complete. Listen and record adherence evidence below." : (envelope.errors?.[0]?.message || envelope.lifecycle_state); await selectMusicProject({ project_id: projectId }); }
  } catch (error) { if (state.selectedMusicProject?.project_id === projectId) byId("music-generation-status").textContent = error.message; }
  finally { state.musicGenerating = false; state.musicJobId = null; byId("cancel-music-generation").disabled = true; byId("music-progress").hidden = true; }
}

function showMusicProgress(event) {
  byId("music-progress-stage").textContent = String(event.stage || "working").replaceAll("_", " ");
  const line = String(event.message || "").trim().split("\n").filter(Boolean).pop(); if (line) byId("music-progress-message").textContent = line.slice(0, 240);
}

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
    const audio = document.createElement("audio"); audio.controls = true; audio.preload = "metadata"; audio.src = `/api/v1/music/audio/${candidate.project_id}/${candidate.candidate_id}/mp3`;
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
  const lineage = document.createElement("section"); lineage.className = "music-visual-lineage";
  const heading = document.createElement("div"); heading.className = "card-heading"; const title = document.createElement("strong"); title.textContent = staticProfile ? "Static visual presentation" : "Historical visual effect"; const badge = document.createElement("small"); badge.textContent = visual.stage.replaceAll("_", " "); heading.append(title, badge); lineage.append(heading);
  const status = document.createElement("p"); status.className = "dialog-status";
  const media = document.createElement("div"); media.className = "music-visual-media";
  const base = document.createElement("img"); base.src = musicVisualUrl(candidate, visual, "base"); base.alt = "Approved visual companion base scene"; media.append(base);
  if (visual.artifacts?.loop) { const loop = document.createElement("video"); loop.controls = true; loop.loop = true; loop.muted = true; loop.preload = "metadata"; loop.src = musicVisualUrl(candidate, visual, "loop"); loop.setAttribute("aria-label", staticProfile ? "Static visual presentation preview" : "Retired visual effect preview"); media.append(loop); }
  if (visual.artifacts?.preview) { const preview = document.createElement("video"); preview.controls = true; preview.preload = "metadata"; preview.src = musicVisualUrl(candidate, visual, "preview"); preview.setAttribute("aria-label", "Three-minute visual companion with candidate audio"); media.append(preview); }
  lineage.append(media);
  const metrics = document.createElement("p"); metrics.className = "music-candidate-timing"; metrics.textContent = visual.artifacts?.loop ? `${staticProfile ? "Static hold · no synthesized motion" : "Historical effect"} · ${visual.artifacts.loop.duration_seconds}s · ${visual.artifacts.loop.width}×${visual.artifacts.loop.height} · ${visual.artifacts.loop.fps} fps` : "Approved still is immutable; presentation encoding has not started."; lineage.append(metrics);
  if (staticProfile && !visual.artifacts?.loop) {
    const settings = musicVisualPresentationSettings(visual); lineage.append(settings.element);
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button"; button.textContent = "Preview static presentation"; button.addEventListener("click", () => previewMusicVisualAction(candidate, lineage, button, status, "loop", { visual_id: visual.visual_id, visual_presentation: settings.value() })); lineage.append(button);
  } else if (staticProfile && !visual.artifacts?.preview) {
    const note = document.createElement("p"); note.textContent = "The frame is held exactly as approved. FFmpeg only handles framing, encoding, fades, and audio muxing.";
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button gate-button--gold"; button.textContent = "Preview three-minute render"; button.addEventListener("click", () => previewMusicVisualAction(candidate, lineage, button, status, "final", { visual_id: visual.visual_id })); lineage.append(note, button);
  } else if (!staticProfile) {
    const note = document.createElement("p"); note.textContent = "Historical effect evidence remains playable, but retired procedural-motion profiles cannot advance."; lineage.append(note);
    if (source) { const replacement = document.createElement("button"); replacement.type = "button"; replacement.className = "gate-button"; replacement.textContent = "Prepare static replacement"; replacement.addEventListener("click", () => previewMusicVisualAction(candidate, lineage, replacement, status, "import", { asset_id: source.asset_id })); lineage.append(replacement); }
  } else {
    const note = document.createElement("p"); note.textContent = "Static local companion ready. It remains unpublished and bound to this exact audio digest."; lineage.append(note);
    const packageButton = document.createElement("button"); packageButton.type = "button"; packageButton.className = "gate-button gate-button--gold"; packageButton.textContent = "Prepare YouTube upload package";
    packageButton.addEventListener("click", () => draftMusicPublicationPackage(candidate, visual, lineage, packageButton, status)); lineage.append(packageButton);
  }
  const motion = document.createElement("div"); motion.className = "music-visual-motion-boundary"; const motionTitle = document.createElement("strong"); motionTitle.textContent = "Generated motion"; const motionState = document.createElement("span"); motionState.textContent = "Qualification pending"; const motionNote = document.createElement("small"); motionNote.textContent = "Unavailable until the Visual Studio A3 motion model passes AMD compatibility, integrity, resource, and cleanup gates."; motion.append(motionTitle, motionState, motionNote); lineage.append(motion);
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
    const gate = document.createElement("div"); gate.className = "music-disposition-gate"; const scope = document.createElement("pre"); scope.className = "diagnostic-output"; scope.textContent = JSON.stringify(data.preview_scope, null, 2); const label = document.createElement("label"); label.textContent = `Approval phrase · ${data.confirmation_phrase}`; const input = document.createElement("input"); const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = kind === "import" ? "Bind exact source" : (kind === "loop" ? "Encode exact static preview" : "Render three-minute companion"); prefillApprovalGate(input, execute, data.confirmation_phrase); execute.addEventListener("click", () => executeMusicVisualAction(candidate, kind, base, data, input.value, execute, status)); label.append(input); gate.append(scope, label, execute); button.replaceWith(gate); status.textContent = kind === "final" ? "This creates one local MP4; it does not publish or upload anything." : "One bounded foreground encode; no image or motion model is loaded.";
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
    const button = document.createElement("button"); button.type = "button"; button.className = "gate-button gate-button--gold"; button.textContent = "Preview finished-song export";
    button.addEventListener("click", () => previewMusicDisposition(candidate, "export", panel, button, status)); panel.append(button, status);
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
  try { const envelope = await callNdjson("/api/v1/music-stream", "music.candidates.analysis.execute", params, {}, (event) => { const line = String(event.message || "").trim().split("\n").filter(Boolean).pop(); if (line) status.textContent = `${String(event.stage || "working").replaceAll("_", " ")}: ${line.slice(0, 240)}`; }); lifecycle(envelope); if (!dataOf(envelope).analysis) throw new Error(envelope.errors?.[0]?.message || "Analysis did not complete"); await selectMusicProject(state.selectedMusicProject); } catch (error) { status.textContent = error.message; button.disabled = false; }
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
  const gate = document.createElement("div"); gate.className = "music-revision-gate"; const scope = document.createElement("pre"); scope.className = "diagnostic-output"; scope.textContent = JSON.stringify(preview.preview_scope, null, 2); const label = document.createElement("label"); label.textContent = `Approval phrase · ${preview.confirmation_phrase}`; const input = document.createElement("input"); input.autocomplete = "off"; input.spellcheck = false; const actions = document.createElement("div"); actions.className = "music-actions"; const start = document.createElement("button"); start.type = "button"; start.className = "gate-button gate-button--gold"; start.textContent = "Generate revised candidate"; start.disabled = true; const cancel = document.createElement("button"); cancel.type = "button"; cancel.className = "danger-button"; cancel.textContent = "Cancel active revision"; cancel.disabled = true; input.addEventListener("input", () => { start.disabled = input.value !== preview.confirmation_phrase; }); prefillApprovalGate(input, start, preview.confirmation_phrase); start.addEventListener("click", async () => { start.disabled = true; cancel.disabled = false; input.disabled = true; state.musicGenerating = true; state.musicCandidateId = preview.candidate_id; status.textContent = "Starting the bounded Music Core revision pass…"; const params = { project_id: sourceCandidate.project_id, source_candidate_id: sourceCandidate.candidate_id, candidate_id: preview.candidate_id, revision, confirmation: input.value, expected_digest: preview.expected_digest }; try { const envelope = await callNdjson("/api/v1/music-stream", "music.candidates.revision.execute", params, {}, (event) => { const line = String(event.message || "").trim().split("\n").filter(Boolean).pop(); if (line) status.textContent = `${String(event.stage || "working").replaceAll("_", " ")}: ${line.slice(0, 240)}`; }); lifecycle(envelope); if (!dataOf(envelope).candidate) throw new Error(envelope.errors?.[0]?.message || "Revision did not complete"); await selectMusicProject(state.selectedMusicProject); } catch (error) { status.textContent = error.message; start.disabled = false; input.disabled = false; } finally { state.musicGenerating = false; cancel.disabled = true; } }); cancel.addEventListener("click", () => cancelRevisionGeneration(preview.candidate_id, status)); actions.append(start, cancel); gate.append(scope, label, input, actions); return gate;
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

async function sendMessage(event) {
  event.preventDefault(); const input = byId("message-input"); const message = input.value.trim(); if (!message || !state.activeChat || state.busy) return;
  const chatId = state.activeChat.id; input.value = ""; appendPendingExchange(message); setSoulActivity("received", "The interface has accepted your transmission.");
  setBusy(true, "Soul is responding"); byId("lifecycle-state").textContent = "pending"; document.querySelector(".state-ribbon").dataset.lifecycle = "pending"; document.querySelector(".conversation").dataset.lifecycle = "pending";
  try {
    const envelope = await callSoulStream("chats.send", { chat_id: chatId, message }, { current_chat_id: chatId }, (progress) => { setSoulActivity(progress.state, progress.summary); updateWorkingMessage(progress.summary); }); lifecycle(envelope);
    const messages = await callSoul("chats.messages", { chat_id: chatId, limit: 200 }, { current_chat_id: chatId }); renderMessages(dataOf(messages).records || []);
    const workspace = await callSoul("workspace.chat", { chat_id: chatId, limit: 50 }, { current_chat_id: chatId }); renderWorkspace(dataOf(workspace).records || []);
    await loadChats(false); announce(`Request ${envelope.lifecycle_state || "finished"}`);
  } catch (error) { try { const messages = await callSoul("chats.messages", { chat_id: chatId, limit: 200 }, { current_chat_id: chatId }); const records = dataOf(messages).records || []; renderMessages(records); if (!records.some((record) => record.role === "user" && record.content === message)) input.value = message; } catch (_reconcileError) { input.value = message; } setSoulActivity("failed", "The exchange failed safely; an unsent draft has been restored."); showError(error); } finally { setBusy(false); input.focus(); }
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
  byId("visual-workbench-title").textContent = "New visual"; byId("save-visual-project").hidden = false; byId("update-visual-project").hidden = true;
  byId("visual-generation-card").hidden = true; byId("visual-candidates").hidden = true; byId("visual-project-delete").hidden = true; byId("visual-form-status").textContent = "";
  renderVisualProjects();
}

function visualProjectInput() {
  return { title: byId("visual-title").value, intent: byId("visual-intent").value, prompt: byId("visual-prompt").value, negative_prompt: byId("visual-negative").value, aspect_ratio: byId("visual-aspect").value, seed: Number(byId("visual-seed").value) };
}

function renderVisualProjects() {
  const list = byId("visual-project-list"); list.replaceChildren(); byId("visual-project-count").textContent = String(state.visualProjects.length);
  if (!state.visualProjects.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No visual projects yet."; list.append(empty); return; }
  state.visualProjects.forEach((project) => {
    const button = document.createElement("button"); button.type = "button"; button.className = "studio-item";
    if (state.selectedVisualProject?.project_id === project.project_id) button.classList.add("is-active");
    const title = document.createElement("strong"); title.textContent = project.title; const meta = document.createElement("small"); meta.textContent = `${project.aspect_ratio} · seed ${project.seed}`;
    button.append(title, meta); button.addEventListener("click", () => selectVisualProject(project.project_id)); list.append(button);
  });
}

function renderVisualCandidates(project) {
  const candidates = project.candidates || []; const list = byId("visual-candidate-list"); list.replaceChildren();
  byId("visual-candidate-count").textContent = String(candidates.length); byId("visual-candidates").hidden = candidates.length === 0;
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
    const deleteButton = document.createElement("button"); deleteButton.type = "button"; deleteButton.className = "danger-button"; deleteButton.textContent = "Delete candidate";
    const status = document.createElement("p"); status.className = "dialog-status"; status.role = "status";
    const gate = document.createElement("div"); gate.className = "visual-candidate-gate"; gate.hidden = true;
    reviewButton.addEventListener("click", async () => { reviewButton.disabled = true; try { const envelope = await callSoul("visual.candidates.review", { visual_project_id: project.project_id, visual_candidate_id: candidate.candidate_id, visual_review: { rating: Number(rating.value), disposition: disposition.value, notes: notes.value } }); lifecycle(envelope); await selectVisualProject(project.project_id); } catch (error) { status.textContent = error.message; reviewButton.disabled = false; } });
    editButton.addEventListener("click", () => renderVisualEditGate(gate, project, candidate, status));
    promoteButton.addEventListener("click", () => renderVisualPromotionGate(gate, project, candidate, status));
    deleteButton.addEventListener("click", () => previewVisualCandidateDeletion(gate, project, candidate, status));
    controls.append(rating, disposition, notes, reviewButton, editButton, promoteButton, deleteButton, gate, status);
    card.append(image, footer, controls); list.append(card);
  });
}

function renderVisualEditGate(gate, project, candidate, status) {
  gate.replaceChildren(); gate.hidden = false;
  const label = document.createElement("label"); label.textContent = "Image-guided revision"; const instruction = document.createElement("textarea"); instruction.rows = 5; instruction.maxLength = 8000; instruction.placeholder = "Preserve the composition and architecture. Refine the distant horizon, deepen the cyan instrument light, and add subtle low mist."; label.append(instruction);
  const seedLabel = document.createElement("label"); seedLabel.textContent = "Revision seed"; const seed = document.createElement("input"); seed.type = "number"; seed.min = "0"; seed.max = "2147483647"; seed.value = String(Math.floor(Math.random() * 2147483647)); seedLabel.append(seed);
  const preview = document.createElement("button"); preview.type = "button"; preview.className = "gate-button"; preview.textContent = "Preview guided edit";
  preview.addEventListener("click", async () => { preview.disabled = true; try { const envelope = await callSoul("visual.edit.preview", { visual_project_id: project.project_id, source_visual_candidate_id: candidate.candidate_id, instruction: instruction.value, seed: seed.value }); lifecycle(envelope); const scope = dataOf(envelope); if (!scope.expected_digest) throw new Error(envelope.errors?.[0]?.message || "Edit preview failed safely"); const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2); const execute = document.createElement("button"); execute.type = "button"; execute.className = "gate-button gate-button--gold"; execute.textContent = "Generate exact guided edit"; execute.addEventListener("click", async () => { execute.disabled = true; status.textContent = "Rendering bounded image-guided revision…"; try { const result = await callNdjson("/api/v1/music-stream", "visual.edit.execute", { visual_project_id: project.project_id, source_visual_candidate_id: candidate.candidate_id, visual_candidate_id: scope.candidate_id, instruction: instruction.value, seed: seed.value, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }, {}, (event) => { status.textContent = event.message || "Local edit in progress."; }); lifecycle(result); await selectVisualProject(project.project_id); } catch (error) { status.textContent = error.message; execute.disabled = false; } }); gate.append(summary, execute); } catch (error) { status.textContent = error.message; preview.disabled = false; } });
  gate.append(label, seedLabel, preview);
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

async function previewVisualCandidateDeletion(gate, project, candidate, status) {
  gate.replaceChildren(); gate.hidden = false;
  try { const envelope = await callSoul("visual.candidates.delete.preview", { visual_project_id: project.project_id, visual_candidate_id: candidate.candidate_id }); lifecycle(envelope); const scope = dataOf(envelope); const summary = document.createElement("pre"); summary.className = "diagnostic-output"; summary.textContent = JSON.stringify(scope, null, 2); const execute = document.createElement("button"); execute.type = "button"; execute.className = "danger-button"; execute.textContent = "Permanently delete exact candidate"; execute.addEventListener("click", async () => { execute.disabled = true; try { const result = await callSoul("visual.candidates.delete.execute", { visual_project_id: project.project_id, visual_candidate_id: candidate.candidate_id, confirmation: scope.confirmation_phrase, expected_digest: scope.expected_digest }); lifecycle(result); await selectVisualProject(project.project_id); } catch (error) { status.textContent = error.message; execute.disabled = false; } }); gate.append(summary, execute); } catch (error) { status.textContent = error.message; }
}

async function selectVisualProject(projectId) {
  try {
    const envelope = await callSoul("visual.projects.get", { visual_project_id: projectId }); lifecycle(envelope); const project = dataOf(envelope).project;
    state.selectedVisualProject = project; byId("visual-title").value = project.title; byId("visual-intent").value = project.intent; byId("visual-prompt").value = project.prompt; byId("visual-negative").value = project.negative_prompt; byId("visual-aspect").value = project.aspect_ratio; byId("visual-seed").value = String(project.seed);
    byId("visual-workbench-title").textContent = project.title; byId("save-visual-project").hidden = true; byId("update-visual-project").hidden = false; byId("visual-generation-card").hidden = false; byId("visual-project-delete").hidden = false; byId("visual-generation-confirm").hidden = true; byId("visual-project-delete-confirm").hidden = true; state.visualPreview = null; state.visualProjectDeletePreview = null;
    renderVisualProjects(); renderVisualCandidates(project);
  } catch (error) { byId("visual-form-status").textContent = error.message; }
}

async function refreshVisualResources() {
  try { const envelope = await callSoul("visual.resources.status"); lifecycle(envelope); const data = dataOf(envelope); const label = byId("visual-resource-state"); label.textContent = data.ready ? `${data.profile} ready` : "Runtime attention"; label.classList.toggle("is-ready", data.ready); byId("visual-form-status").textContent = data.ready ? `${data.accelerator} · exact model set verified · ${data.core?.core_id || "bounded lane"}` : (data.core?.reason || `Missing: ${(data.missing_roles || []).join(", ") || "runtime"}`); }
  catch (error) { byId("visual-form-status").textContent = error.message; }
}

async function loadVisualStudio() {
  try { const envelope = await callSoul("visual.projects.list", { limit: 200 }); lifecycle(envelope); state.visualProjects = dataOf(envelope).projects || []; state.visualLoaded = true; renderVisualProjects(); await refreshVisualResources(); }
  catch (error) { byId("visual-form-status").textContent = error.message; }
}

async function createVisualProject(event) {
  event.preventDefault(); const visualProject = visualProjectInput();
  try { const envelope = await callSoul("visual.projects.create", { visual_project: visualProject }); lifecycle(envelope); const project = dataOf(envelope).project; state.visualProjects.unshift(project); await selectVisualProject(project.project_id); byId("visual-form-status").textContent = "Visual project created."; }
  catch (error) { byId("visual-form-status").textContent = error.message; }
}

async function updateVisualProject() {
  if (!state.selectedVisualProject) return;
  try { const envelope = await callSoul("visual.projects.update", { visual_project_id: state.selectedVisualProject.project_id, visual_project: visualProjectInput() }); lifecycle(envelope); await loadVisualStudio(); await selectVisualProject(state.selectedVisualProject.project_id); byId("visual-form-status").textContent = "Revised brief saved. Existing candidate inputs remain immutable."; }
  catch (error) { byId("visual-form-status").textContent = error.message; }
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
  try { const envelope = await callSoul("visual.generation.preview", { visual_project_id: state.selectedVisualProject.project_id }); lifecycle(envelope); const data = dataOf(envelope); if (!data.expected_digest) throw new Error(envelope.data?.message || "Visual runtime is not ready"); state.visualPreview = data; byId("visual-generation-scope").textContent = JSON.stringify(data, null, 2); byId("visual-generation-confirm").hidden = false; byId("start-visual-generation").disabled = false; byId("visual-generation-status").textContent = "Clicking generate authorizes this exact local draft."; }
  catch (error) { byId("visual-generation-status").textContent = error.message; }
}

async function startVisualGeneration() {
  if (!state.visualPreview || state.visualGenerating) return; state.visualGenerating = true; byId("start-visual-generation").disabled = true; byId("visual-progress").hidden = false;
  try {
    const parameters = { visual_project_id: state.visualPreview.project_id, visual_candidate_id: state.visualPreview.candidate_id, confirmation: state.visualPreview.confirmation_phrase, expected_digest: state.visualPreview.expected_digest };
    const envelope = await callNdjson("/api/v1/music-stream", "visual.generation.execute", parameters, {}, (event) => { byId("visual-progress-stage").textContent = event.stage || "Working"; byId("visual-progress-message").textContent = event.message || "Local render in progress."; });
    lifecycle(envelope); byId("visual-generation-status").textContent = "Visual draft generated; review the candidate below."; await selectVisualProject(state.visualPreview.project_id);
  } catch (error) { byId("visual-generation-status").textContent = error.message; }
  finally { state.visualGenerating = false; byId("visual-progress").hidden = true; }
}

async function bootstrap() {
  if (state.bootstrapped) return;
  state.bootstrapped = true;
  try {
    const envelope = await callSoul("application.bootstrap"); lifecycle(envelope); const data = dataOf(envelope); const providers = data.providers?.providers || [];
    const active = providers.find((provider) => provider.available || provider.configured) || providers[0]; byId("provider-label").textContent = active ? `Provider ${active.id || active.name || "ready"}` : "Provider local";
    byId("config-label").textContent = data.configuration?.ok ? "Config valid" : "Config attention"; switchTab(tabFromLocation() || "chat"); await loadChats(true); await refreshCores({ automatic: true }); await refreshStatus({ automatic: true }); await refreshModelRuntime({ automatic: true });
  } catch (error) { state.bootstrapped = false; byId("connection-label").textContent = "Disconnected"; showError(error); }
}

byId("login-form").addEventListener("submit", login);
byId("password-change-form").addEventListener("submit", changePassword);
byId("logout-button").addEventListener("click", logout);
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
byId("self-improvement-tab").addEventListener("click", () => setSelfImprovementMenu(byId("self-improvement-menu").hidden));
byId("creative-tab").addEventListener("click", () => setCreativeMenu(byId("creative-menu").hidden));
byId("studio-tab").addEventListener("click", () => switchTab("studio"));
byId("improvement-tab").addEventListener("click", () => switchTab("improvement"));
byId("augmentation-tab").addEventListener("click", () => switchTab("augmentation"));
byId("music-tab").addEventListener("click", () => switchTab("music"));
byId("visual-tab").addEventListener("click", () => switchTab("visual"));
window.addEventListener("hashchange", () => { const tab = tabFromLocation(); if (tab) switchTab(tab, { updateLocation: false }); });
document.addEventListener("click", (event) => { if (!byId("self-improvement-navigation").contains(event.target)) setSelfImprovementMenu(false); if (!byId("creative-navigation").contains(event.target)) setCreativeMenu(false); if (!byId("core-navigation").contains(event.target)) setCoreMenu(false); });
byId("self-improvement-navigation").addEventListener("keydown", (event) => { if (event.key === "Escape") { setSelfImprovementMenu(false); byId("self-improvement-tab").focus(); } });
byId("core-navigation").addEventListener("keydown", (event) => { if (event.key === "Escape") { setCoreMenu(false); byId("core-selector").focus(); } });
byId("creative-navigation").addEventListener("keydown", (event) => { if (event.key === "Escape") { setCreativeMenu(false); byId("creative-tab").focus(); } });
byId("new-visual-project").addEventListener("click", resetVisualForm);
byId("visual-project-form").addEventListener("submit", createVisualProject);
byId("update-visual-project").addEventListener("click", updateVisualProject);
byId("refresh-visual-resources").addEventListener("click", refreshVisualResources);
byId("preview-visual-generation").addEventListener("click", previewVisualGeneration);
byId("start-visual-generation").addEventListener("click", startVisualGeneration);
byId("preview-visual-project-delete").addEventListener("click", previewVisualProjectDeletion);
byId("execute-visual-project-delete").addEventListener("click", executeVisualProjectDeletion);
byId("new-music-project").addEventListener("click", resetMusicForm);
byId("music-project-form").addEventListener("submit", createMusicProject);
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
byId("message-input").addEventListener("keydown", (event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); if (state.busy) { announce("Soul is still working; the draft was not sent or used as an interruption."); return; } byId("composer").requestSubmit(); } });
initializeAuthentication();
