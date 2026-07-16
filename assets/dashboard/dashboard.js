"use strict";

const csrf = document.querySelector('meta[name="soul-csrf"]').content;
const state = { authenticated: false, bootstrapped: false, chats: [], activeChat: null, busy: false, clearPreview: null, forgetPreview: null, modelRuntime: null, modelRuntimePreview: null, studioLoaded: false, proposals: [], betas: [], productionSkills: [], linkedProductionSkill: null, selectedProposal: null, selectedBeta: null, proposalApproval: null, betaBuildPreview: null, proposalClosePreview: null, betaRunPreview: null, betaPromotionPreview: null, productionPromotionPreview: null, improvementLoaded: false, improvementProposalPreview: null, reviewLoaded: false, approvals: [], activities: [], activitySummary: [], activityFilter: "all", selectedApproval: null, selectedActivity: null, reviewOpener: null };
const byId = (id) => document.getElementById(id);

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
    signal: requestOptions.signal
  });
  const envelope = await response.json();
  if (response.status === 401 || envelope.error?.code === "password_change_required") { window.location.reload(); throw new Error("Dashboard session expired"); }
  if (!response.ok) throw new Error(envelope.error?.reason || "Dashboard transport failed");
  return envelope;
}

async function authRequest(path, body) {
  const options = { credentials: "same-origin", headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf } };
  if (body !== undefined) { options.method = "POST"; options.body = JSON.stringify(body); }
  const response = await fetch(path, options);
  const envelope = await response.json();
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
function lifecycle(envelope) {
  const value = envelope.lifecycle_state || "failed";
  byId("lifecycle-state").textContent = value.replaceAll("_", " ");
  document.querySelector(".state-ribbon").dataset.lifecycle = value;
  document.querySelector(".conversation").dataset.lifecycle = value;
  byId("mutation-state").textContent = `mutation ${envelope.meta?.mutation || "none"}`;
  return value;
}

function setBusy(busy, message = "") {
  state.busy = busy;
  byId("send-message").disabled = busy || !state.activeChat;
  byId("message-input").disabled = busy || !state.activeChat;
  if (message) announce(message);
}

function switchTab(name) {
  const chat = name === "chat";
  const studio = name === "studio";
  const improvement = name === "improvement";
  byId("chat-panel").hidden = !chat;
  byId("studio-panel").hidden = !studio;
  byId("improvement-panel").hidden = !improvement;
  byId("chat-tab").classList.toggle("is-active", chat);
  byId("studio-tab").classList.toggle("is-active", studio);
  byId("improvement-tab").classList.toggle("is-active", improvement);
  byId("chat-tab").setAttribute("aria-selected", String(chat));
  byId("studio-tab").setAttribute("aria-selected", String(studio));
  byId("improvement-tab").setAttribute("aria-selected", String(improvement));
  if (studio && !state.studioLoaded) loadSkillStudio();
  if (improvement && !state.improvementLoaded) loadSelfImprovement();
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

function renderMessages(records, noChat = false) {
  const area = byId("messages"); area.replaceChildren();
  if (!records.length) { const empty = document.createElement("div"); empty.className = "empty-state"; const copy = document.createElement("div"); const eyebrow = document.createElement("p"); eyebrow.className = "eyebrow"; eyebrow.textContent = noChat ? "Active list clear" : "Fresh context"; const heading = document.createElement("h2"); heading.textContent = noChat ? "Create a conversation when you’re ready." : "This conversation is ready."; const note = document.createElement("p"); note.textContent = noChat ? "Archived transcripts remain stored locally and are not deleted." : "Your first message will use Soul’s configured provider and shared context boundary."; copy.append(eyebrow, heading, note); empty.append(copy); area.append(empty); return; }
  records.forEach((record) => {
    const article = document.createElement("article"); const role = record.role === "user" ? "user" : "assistant"; article.className = `message message--${role}`;
    const label = document.createElement("div"); label.className = "message-label"; label.textContent = role === "user" ? "You" : "Soul /";
    const body = document.createElement("div"); body.className = "message-body"; body.textContent = record.content || record.text || ""; article.append(label, body); area.append(article);
  });
  area.scrollTop = area.scrollHeight;
}

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
    const data = dataOf(envelope); state.forgetPreview = { parameters, digest: data.inventory_digest, confirmation: data.confirmation_phrase };
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
    const count = dataOf(envelope).conversation_count || 0; state.activeChat = null; state.forgetPreview = null; byId("clear-dialog").close(); await loadChats(true); announce(`${count} conversation${count === 1 ? "" : "s"} permanently deleted and linked memories forgotten`);
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
  setBusy(true, "Soul is responding"); byId("lifecycle-state").textContent = "pending"; document.querySelector(".state-ribbon").dataset.lifecycle = "pending"; document.querySelector(".conversation").dataset.lifecycle = "pending";
  try {
    const envelope = await callSoul("chats.send", { chat_id: state.activeChat.id, message }, { current_chat_id: state.activeChat.id }); lifecycle(envelope);
    if (envelope.lifecycle_state === "complete") input.value = "";
    const messages = await callSoul("chats.messages", { chat_id: state.activeChat.id, limit: 200 }, { current_chat_id: state.activeChat.id }); renderMessages(dataOf(messages).records || []);
    const workspace = await callSoul("workspace.chat", { chat_id: state.activeChat.id, limit: 50 }, { current_chat_id: state.activeChat.id }); renderWorkspace(dataOf(workspace).records || []);
    await loadChats(false); announce(`Request ${envelope.lifecycle_state || "finished"}`);
  } catch (error) { showError(error); } finally { setBusy(false); input.focus(); }
}

async function togglePin() {
  if (!state.activeChat) return; const operation = state.activeChat.pinned ? "chats.unpin" : "chats.pin";
  try { const envelope = await callSoul(operation, { chat_id: state.activeChat.id }); lifecycle(envelope); state.activeChat = dataOf(envelope).record; await loadChats(false); renderChatList(); byId("pin-chat").textContent = state.activeChat.pinned ? "Unpin" : "Pin"; } catch (error) { showError(error); }
}

function detailRow(term, description) { const row = document.createElement("div"); const dt = document.createElement("dt"); dt.textContent = term; const dd = document.createElement("dd"); dd.textContent = description; row.append(dt, dd); return row; }
async function refreshStatus({ automatic = false } = {}) {
  const button = byId("refresh-status"); button.disabled = true; announce("Collecting bounded host status");
  try { const envelope = await callSoul("system_status.refresh"); lifecycle(envelope); const data = dataOf(envelope); const host = data.collected?.host?.hostname || data.hostname || data.host || "Unavailable"; const details = byId("system-details"); details.replaceChildren(detailRow("Host", host), detailRow("Collected", data.collected_at ? formatTime(data.collected_at) : "Completed"), detailRow("Scope", data.scope || "Bounded host"), detailRow("State", envelope.lifecycle_state || "unknown")); announce(automatic ? "Initial system status collected" : "System status refreshed manually"); } catch (error) { const details = byId("system-details"); details.replaceChildren(detailRow("Host", "Unavailable"), detailRow("Collected", "Initial collection failed"), detailRow("Scope", "Bounded host"), detailRow("State", "failed")); if (!automatic) showError(error); } finally { button.disabled = false; }
}

function renderModelRuntime(runtime, message = "") {
  state.modelRuntime = runtime; const card = document.querySelector(".runtime-card"); const runtimeState = runtime.state || "unavailable"; card.dataset.state = runtimeState;
  byId("runtime-state-label").textContent = runtimeState.replaceAll("_", " ");
  byId("runtime-details").replaceChildren(
    detailRow("Profile", runtime.profile || "not configured"), detailRow("Model", runtime.model || "not configured"),
    detailRow("Service", runtime.service || "control disabled"), detailRow("Active work", String(runtime.active_work_count ?? 0)),
    detailRow("Server", runtime.server?.health || "unavailable")
  );
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

async function previewModelRuntime(action) {
  state.modelRuntimePreview = null; const status = byId("runtime-card-status"); status.textContent = `Checking whether ${action} is safe…`;
  try {
    const envelope = await callSoul(`model_runtime.${action}.preview`); const runtime = dataOf(envelope); renderModelRuntime(runtime);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || `Model ${action} is blocked.`; return; }
    state.modelRuntimePreview = { action, digest: runtime.expected_digest, confirmation: runtime.confirmation_phrase };
    byId("model-runtime-dialog-title").textContent = action === "load" ? "Load model runtime" : "Unload model runtime";
    byId("model-runtime-preview-title").textContent = action === "load" ? "Start the configured user service" : "Release model GPU memory";
    byId("model-runtime-preview-details").replaceChildren(
      detailRow("Profile", runtime.profile || "not configured"), detailRow("Model", runtime.model || "not configured"),
      detailRow("Service", runtime.service || "unavailable"), detailRow("Active work", String(runtime.active_work_count ?? 0)),
      detailRow("Slots", runtime.server?.slots_reachable ? `${runtime.server.active_slots} active / ${runtime.server.total_slots} total` : "offline")
    );
    byId("model-runtime-confirmation-phrase").textContent = runtime.confirmation_phrase; byId("model-runtime-confirmation").value = ""; byId("execute-model-runtime").disabled = true;
    byId("execute-model-runtime").textContent = action === "load" ? "Load verified model runtime" : "Unload verified model runtime";
    byId("model-runtime-dialog-status").textContent = "The runtime state will be checked again before the service changes."; byId("model-runtime-dialog").showModal();
  } catch (error) { status.textContent = error.message || `Model ${action} preview failed safely.`; }
}

async function executeModelRuntime() {
  const preview = state.modelRuntimePreview; if (!preview || byId("model-runtime-confirmation").value !== preview.confirmation) return;
  const button = byId("execute-model-runtime"); const status = byId("model-runtime-dialog-status"); button.disabled = true; status.textContent = "Revalidating active work and service state…";
  try {
    const envelope = await callSoul(`model_runtime.${preview.action}.execute`, { confirmation: preview.confirmation, expected_digest: preview.digest }); const runtime = dataOf(envelope); renderModelRuntime(runtime);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Runtime change was blocked safely."; state.modelRuntimePreview = null; return; }
    state.modelRuntimePreview = null; byId("model-runtime-dialog").close(); announce(`Model runtime ${preview.action} complete`); await refreshModelRuntime();
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
  state.proposalApproval = data; byId("proposal-approval-confirm").hidden = false; byId("proposal-confirmation").value = ""; byId("execute-proposal-approval").disabled = true; status.textContent = "Approval authorizes implementation work only; it does not generate, execute, register, or promote a skill.";
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
  state.betaBuildPreview = data; byId("beta-build-confirm").hidden = false; byId("beta-build-phrase").textContent = data.confirmation_phrase; byId("beta-build-confirmation").value = ""; byId("execute-beta-build").disabled = true; status.textContent = "Review the exact skill ID and candidate-only boundary, then type the preparation phrase.";
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
  state.betaRunPreview = data; byId("beta-run-confirm").hidden = false; byId("beta-run-phrase").textContent = data.confirmation_phrase; byId("beta-run-confirmation").value = ""; byId("execute-beta-run").disabled = true; status.textContent = `Foreground timeout: ${data.timeout_seconds}s. A bounded local diagnostic record will be written.`;
}

async function executeBetaRun() {
  if (!state.selectedBeta || !state.betaRunPreview) return; const status = byId("beta-run-status"); status.textContent = "Running Beta in the foreground…";
  const envelope = await callSoul("skill_studio.betas.run.execute", { beta_id: state.selectedBeta.beta_id, args: betaArguments(), expected_digest: state.betaRunPreview.expected_digest, confirmation: byId("beta-run-confirmation").value }); const data = dataOf(envelope);
  const output = byId("beta-run-output"); output.hidden = false; output.textContent = [data.stdout, data.stderr].filter(Boolean).join("\n") || envelope.errors?.[0]?.message || "Beta returned no output."; status.textContent = data.diagnostic_log ? `Finished ${envelope.lifecycle_state}; diagnostic record: ${data.diagnostic_log}` : `Beta run ${envelope.lifecycle_state}.`;
}

async function previewBetaPromotion() {
  if (!state.selectedBeta) return; const status = byId("beta-promotion-status"); status.textContent = "Checking test evidence and revision integrity…";
  const envelope = await callSoul("skill_studio.betas.promotion.preview", { beta_id: state.selectedBeta.beta_id }); const data = dataOf(envelope); if (!data.expected_digest) { status.textContent = envelope.errors?.[0]?.message || data.reason || "Promotion preview blocked."; return; }
  state.betaPromotionPreview = data; byId("beta-promotion-confirm").hidden = false; const blockers = (data.blockers || []).map((text) => ({ text, passed: false })); renderChecklist(byId("beta-promotion-blockers"), blockers, "All deterministic prerequisites are satisfied."); byId("beta-promotion-confirmation").value = ""; byId("execute-beta-promotion").disabled = true; status.textContent = data.ready ? "Ready for your Gate 2 decision. Approval will not perform promotion." : "Promotion approval is blocked until every listed requirement is satisfied.";
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
  state.productionPromotionPreview = data; byId("production-promotion-confirm").hidden = false; byId("production-promotion-phrase").textContent = data.confirmation_phrase; byId("production-promotion-confirmation").value = ""; byId("execute-production-promotion").disabled = true;
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
  if (scope === "environment" || scope === "updates") renderImprovementEnvironment(report);
  if (scope === "models") renderModelSummary(report);
  if (scope === "capabilities") { renderCapabilitySummary(report.summary); renderModelSummary(report.sources?.model_runtime); }
  if (data.cached_capabilities?.available) renderCapabilitySummary(data.cached_capabilities.summary, `Cached assessment from ${formatTime(data.cached_capabilities.generated_at)}; run Capabilities to refresh.`);
  renderRecommendations(report.recommendations || []); renderImprovementProposals(data.proposals);
}

function setAssessmentButtonsDisabled(disabled) { document.querySelectorAll("[data-assessment-scope]").forEach((button) => { button.disabled = disabled; }); }

async function loadSelfImprovement() {
  setAssessmentButtonsDisabled(true); byId("improvement-scope").textContent = "assessing"; announce("Collecting lightweight read-only environment assessment");
  try { const envelope = await callSoul("self_improvement.snapshot"); lifecycle(envelope); if (envelope.lifecycle_state !== "complete") throw new Error(envelope.errors?.[0]?.message || "Assessment failed safely"); renderSelfImprovement(dataOf(envelope)); state.improvementLoaded = true; announce("Self Assessment snapshot ready"); }
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
  byId("improvement-proposal-confirm").hidden = false; byId("improvement-proposal-confirmation").value = ""; byId("execute-improvement-proposals").disabled = true;
  status.textContent = "Review this exact candidate set. Confirmation writes proposal packets only.";
}

async function executeImprovementProposals() {
  if (!state.improvementProposalPreview) return; const status = byId("improvement-proposal-status"); status.textContent = "Revalidating exact assessment revision…";
  const envelope = await callSoul("self_improvement.proposals.execute", { expected_digest: state.improvementProposalPreview.expected_digest, confirmation: byId("improvement-proposal-confirmation").value }); const data = dataOf(envelope);
  if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Generation blocked; preview again."; return; }
  renderImprovementProposals(data.proposals); status.textContent = `${data.written_count || 0} new advisory packet${data.written_count === 1 ? "" : "s"} written. Human review is still required.`;
  state.improvementProposalPreview = null; byId("improvement-proposal-confirm").hidden = true; announce("Improvement proposal generation complete");
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

async function bootstrap() {
  if (state.bootstrapped) return;
  state.bootstrapped = true;
  try {
    const envelope = await callSoul("application.bootstrap"); lifecycle(envelope); const data = dataOf(envelope); const providers = data.providers?.providers || [];
    const active = providers.find((provider) => provider.available || provider.configured) || providers[0]; byId("provider-label").textContent = active ? `Provider ${active.id || active.name || "ready"}` : "Provider local";
    byId("config-label").textContent = data.configuration?.ok ? "Config valid" : "Config attention"; await loadChats(true); await refreshStatus({ automatic: true }); await refreshModelRuntime({ automatic: true });
  } catch (error) { state.bootstrapped = false; byId("connection-label").textContent = "Disconnected"; showError(error); }
}

byId("login-form").addEventListener("submit", login);
byId("password-change-form").addEventListener("submit", changePassword);
byId("logout-button").addEventListener("click", logout);
byId("review-center-button").addEventListener("click", openReviewCenter);
byId("close-review-center").addEventListener("click", closeReviewCenter);
byId("refresh-review-center").addEventListener("click", loadReviewCenter);
byId("review-approvals-tab").addEventListener("click", () => switchReviewView("approvals"));
byId("review-activity-tab").addEventListener("click", () => switchReviewView("activity"));
document.querySelectorAll("[data-activity-filter]").forEach((button) => button.addEventListener("click", () => filterReviewActivity(button.dataset.activityFilter)));
byId("review-center").addEventListener("close", () => { if (state.reviewOpener instanceof HTMLElement) state.reviewOpener.focus(); });
byId("review-center").addEventListener("click", (event) => { if (event.target === byId("review-center")) closeReviewCenter(); });
byId("chat-tab").addEventListener("click", () => switchTab("chat"));
byId("studio-tab").addEventListener("click", () => switchTab("studio"));
byId("improvement-tab").addEventListener("click", () => switchTab("improvement"));
document.querySelectorAll("[data-assessment-scope]").forEach((button) => button.addEventListener("click", () => refreshSelfImprovement(button.dataset.assessmentScope)));
byId("preview-improvement-proposals").addEventListener("click", previewImprovementProposals);
byId("improvement-proposal-confirmation").addEventListener("input", () => { byId("execute-improvement-proposals").disabled = !state.improvementProposalPreview || byId("improvement-proposal-confirmation").value !== state.improvementProposalPreview.confirmation_phrase; });
byId("execute-improvement-proposals").addEventListener("click", executeImprovementProposals);
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
byId("message-input").addEventListener("keydown", (event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); byId("composer").requestSubmit(); } });
initializeAuthentication();
