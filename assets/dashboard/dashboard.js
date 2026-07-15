"use strict";

const csrf = document.querySelector('meta[name="soul-csrf"]').content;
const state = { chats: [], activeChat: null, busy: false };
const byId = (id) => document.getElementById(id);

function requestId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") return `dash-${globalThis.crypto.randomUUID()}`;
  return `dash-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
}

async function callSoul(operation, parameters = {}, context = {}) {
  const response = await fetch("/api/v1/call", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Soul-CSRF": csrf },
    body: JSON.stringify({ schema_version: "soul.application.v1", request_id: requestId(), operation, parameters, context: { interface: "dashboard", ...context } })
  });
  const envelope = await response.json();
  if (!response.ok) throw new Error(envelope.error?.reason || "Dashboard transport failed");
  return envelope;
}

function announce(message) { byId("live-status").textContent = message; }
function dataOf(envelope) { return envelope.data || {}; }
function lifecycle(envelope) {
  const value = envelope.lifecycle_state || "failed";
  byId("lifecycle-state").textContent = value.replaceAll("_", " ");
  document.querySelector(".state-ribbon").dataset.lifecycle = value;
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
  byId("chat-panel").hidden = !chat;
  byId("studio-panel").hidden = chat;
  byId("chat-tab").classList.toggle("is-active", chat);
  byId("studio-tab").classList.toggle("is-active", !chat);
  byId("chat-tab").setAttribute("aria-selected", String(chat));
  byId("studio-tab").setAttribute("aria-selected", String(!chat));
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

function renderMessages(records) {
  const area = byId("messages"); area.replaceChildren();
  if (!records.length) { const empty = document.createElement("div"); empty.className = "empty-state"; const copy = document.createElement("div"); const eyebrow = document.createElement("p"); eyebrow.className = "eyebrow"; eyebrow.textContent = "Fresh context"; const heading = document.createElement("h2"); heading.textContent = "This conversation is ready."; const note = document.createElement("p"); note.textContent = "Your first message will use Soul’s configured provider and shared context boundary."; copy.append(eyebrow, heading, note); empty.append(copy); area.append(empty); return; }
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

async function sendMessage(event) {
  event.preventDefault(); const input = byId("message-input"); const message = input.value.trim(); if (!message || !state.activeChat || state.busy) return;
  setBusy(true, "Soul is responding"); byId("lifecycle-state").textContent = "pending";
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
async function refreshStatus() {
  const button = byId("refresh-status"); button.disabled = true; announce("Collecting bounded host status");
  try { const envelope = await callSoul("system_status.refresh"); lifecycle(envelope); const data = dataOf(envelope); const host = data.collected?.host?.hostname || data.hostname || data.host || "Unavailable"; const details = byId("system-details"); details.replaceChildren(detailRow("Host", host), detailRow("Collected", data.collected_at ? formatTime(data.collected_at) : "Completed"), detailRow("Scope", data.scope || "Bounded host"), detailRow("State", envelope.lifecycle_state || "unknown")); announce("System status refreshed manually"); } catch (error) { showError(error); } finally { button.disabled = false; }
}

function showError(error) { byId("lifecycle-state").textContent = "failed"; document.querySelector(".state-ribbon").dataset.lifecycle = "failed"; announce(error.message || "Request failed safely"); }

async function bootstrap() {
  try {
    const envelope = await callSoul("application.bootstrap"); lifecycle(envelope); const data = dataOf(envelope); const providers = data.providers?.providers || [];
    const active = providers.find((provider) => provider.available || provider.configured) || providers[0]; byId("provider-label").textContent = active ? `Provider ${active.id || active.name || "ready"}` : "Provider local";
    byId("config-label").textContent = data.configuration?.ok ? "Config valid" : "Config attention"; await loadChats(true);
  } catch (error) { byId("connection-label").textContent = "Disconnected"; showError(error); }
}

byId("chat-tab").addEventListener("click", () => switchTab("chat"));
byId("studio-tab").addEventListener("click", () => switchTab("studio"));
byId("new-chat").addEventListener("click", createChat);
byId("pin-chat").addEventListener("click", togglePin);
byId("refresh-status").addEventListener("click", refreshStatus);
byId("composer").addEventListener("submit", sendMessage);
byId("message-input").addEventListener("keydown", (event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); byId("composer").requestSubmit(); } });
bootstrap();
