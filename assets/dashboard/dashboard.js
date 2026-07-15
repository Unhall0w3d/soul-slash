"use strict";

const csrf = document.querySelector('meta[name="soul-csrf"]').content;
const state = { chats: [], activeChat: null, busy: false, clearPreview: null, forgetPreview: null, studioLoaded: false, proposals: [], betas: [], selectedProposal: null, selectedBeta: null, proposalApproval: null, betaRunPreview: null, betaPromotionPreview: null };
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
  if (!chat && !state.studioLoaded) loadSkillStudio();
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
  byId("clear-mode").value = "title";
  byId("clear-title").value = state.activeChat?.title || "";
  byId("clear-title-field").hidden = false;
  byId("clear-preview").hidden = true;
  byId("clear-confirmation").value = "";
  byId("forget-preview").hidden = true;
  byId("forget-confirmation").value = "";
  byId("execute-forget").disabled = true;
  byId("preview-forget").disabled = !state.activeChat;
  byId("forget-dialog-status").textContent = state.activeChat ? `Selected: ${state.activeChat.title || state.activeChat.id}` : "Select one conversation before using delete & forget.";
  byId("clear-dialog-status").textContent = "Preview is required before archival.";
  byId("clear-dialog").showModal();
}

async function previewForget() {
  const status = byId("forget-dialog-status");
  if (!state.activeChat) { status.textContent = "Select one conversation first."; return; }
  state.forgetPreview = null; byId("forget-preview").hidden = true; status.textContent = "Inventorying conversation-owned data…";
  try {
    const envelope = await callSoul("chats.forget.preview", { chat_id: state.activeChat.id }); lifecycle(envelope);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Delete-and-forget preview blocked."; return; }
    const data = dataOf(envelope); state.forgetPreview = { chatId: state.activeChat.id, digest: data.inventory_digest };
    byId("forget-preview-summary").textContent = `${data.message_count} message${data.message_count === 1 ? "" : "s"}, ${data.memory_ids.length} linked memor${data.memory_ids.length === 1 ? "y" : "ies"}, and ${data.artifact_ids.length} artifact attachment${data.artifact_ids.length === 1 ? "" : "s"} identified.`;
    const list = byId("forget-preview-list"); list.replaceChildren();
    [
      `Delete permanently: ${(data.owned_files || []).filter((file) => file.exists).map((file) => file.kind).join(", ") || "no owned files"}`,
      `Forget logically: ${data.memory_ids.length} shared memory record(s)`,
      `Detach only: ${data.artifact_ids.length} artifact(s); artifact files remain`,
      `Retain: ${(data.retained || []).join("; ")}`
    ].forEach((copy) => { const item = document.createElement("div"); item.className = "clear-preview-item"; const text = document.createElement("strong"); text.textContent = copy; item.append(text); list.append(item); });
    byId("forget-confirmation").value = ""; byId("execute-forget").disabled = true; byId("forget-preview").hidden = false; status.textContent = `Review the scope for ${state.activeChat.id}, then type the exact confirmation.`;
  } catch (error) { status.textContent = error.message || "Delete-and-forget preview failed safely."; }
}

async function executeForget() {
  if (!state.forgetPreview || byId("forget-confirmation").value !== "DELETE_AND_FORGET_CONVERSATION") return;
  const status = byId("forget-dialog-status"); byId("execute-forget").disabled = true; status.textContent = "Deleting the verified conversation and forgetting linked memory…";
  try {
    const envelope = await callSoul("chats.forget.execute", { chat_id: state.forgetPreview.chatId, confirmation: "DELETE_AND_FORGET_CONVERSATION", expected_digest: state.forgetPreview.digest }); lifecycle(envelope);
    if (envelope.lifecycle_state !== "complete") { status.textContent = envelope.errors?.[0]?.message || "Delete-and-forget blocked for human review."; state.forgetPreview = null; return; }
    state.activeChat = null; state.forgetPreview = null; byId("clear-dialog").close(); await loadChats(true); announce("Conversation permanently deleted and linked memories forgotten");
  } catch (error) { status.textContent = error.message || "Delete-and-forget failed safely."; }
}

function clearParameters() {
  const mode = byId("clear-mode").value;
  return mode === "all" ? { mode } : { mode, title: byId("clear-title").value.trim() };
}

function resetClearPreview() {
  state.clearPreview = null;
  byId("clear-preview").hidden = true;
  byId("clear-confirmation").value = "";
  byId("execute-clear").disabled = true;
  byId("clear-dialog-status").textContent = "Scope changed; preview again.";
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
async function refreshStatus({ automatic = false } = {}) {
  const button = byId("refresh-status"); button.disabled = true; announce("Collecting bounded host status");
  try { const envelope = await callSoul("system_status.refresh"); lifecycle(envelope); const data = dataOf(envelope); const host = data.collected?.host?.hostname || data.hostname || data.host || "Unavailable"; const details = byId("system-details"); details.replaceChildren(detailRow("Host", host), detailRow("Collected", data.collected_at ? formatTime(data.collected_at) : "Completed"), detailRow("Scope", data.scope || "Bounded host"), detailRow("State", envelope.lifecycle_state || "unknown")); announce(automatic ? "Initial system status collected" : "System status refreshed manually"); } catch (error) { const details = byId("system-details"); details.replaceChildren(detailRow("Host", "Unavailable"), detailRow("Collected", "Initial collection failed"), detailRow("Scope", "Bounded host"), detailRow("State", "failed")); if (!automatic) showError(error); } finally { button.disabled = false; }
}

function showError(error) { byId("lifecycle-state").textContent = "failed"; document.querySelector(".state-ribbon").dataset.lifecycle = "failed"; announce(error.message || "Request failed safely"); }

function studioItem(titleText, metaText, active, onClick) {
  const button = document.createElement("button"); button.type = "button"; button.className = "studio-item"; button.classList.toggle("is-active", active);
  const title = document.createElement("strong"); title.textContent = titleText;
  const meta = document.createElement("small"); meta.textContent = metaText;
  button.append(title, meta); button.addEventListener("click", onClick); return button;
}

function renderStudioLists(production = null) {
  const proposals = byId("proposal-list"); proposals.replaceChildren(); byId("proposal-count").textContent = String(state.proposals.length);
  if (!state.proposals.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No proposal packets found."; proposals.append(empty); }
  state.proposals.forEach((record) => { const source = record.intake ? `gap intake · ${record.occurrence_count || 1} occurrence${record.occurrence_count === 1 ? "" : "s"}` : (record.provider || "local"); proposals.append(studioItem(record.title || record.proposal_id, `${record.proposal_gate?.replaceAll("_", " ")} · ${source}`, state.selectedProposal?.proposal_id === record.proposal_id, () => selectProposal(record.proposal_id))); });

  const betas = byId("beta-list"); betas.replaceChildren(); byId("beta-count").textContent = String(state.betas.length);
  if (!state.betas.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No implemented Beta packages yet."; betas.append(empty); }
  state.betas.forEach((record) => betas.append(studioItem(record.beta_id, `${record.maturity?.replaceAll("_", " ")} · ${record.runnable ? "runnable" : "not runnable"}`, state.selectedBeta?.beta_id === record.beta_id, () => selectBeta(record.beta_id))));

  if (production) {
    const skills = byId("production-skill-list"); skills.replaceChildren(); const records = production.records || []; byId("production-skill-count").textContent = String(records.length);
    records.forEach((record) => skills.append(studioItem(record.skill_id, `${record.risk || "unknown"} · ${record.available ? "available" : "unavailable"}`, false, () => {})));
    if (!records.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "No registered production skills."; skills.append(empty); }
  }
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
    state.selectedProposal = record; state.selectedBeta = null; state.proposalApproval = null; showStudioDetail("proposal"); renderStudioLists();
    byId("proposal-title").textContent = record.title || proposalId; byId("proposal-description").textContent = record.description || "No proposal description.";
    byId("proposal-gate-state").textContent = record.proposal_gate?.replaceAll("_", " ") || "awaiting review";
    const proposalMeta = [["Proposal ID", record.proposal_id], ["Created", record.created_at], ["Beta package", record.beta_present ? "present" : "not built"], ["Beta gate", record.beta_gate?.replaceAll("_", " ")]];
    if (record.intake) proposalMeta.push(["Origin chat", record.origin_chat_id], ["Gap class", record.gap_classification?.replaceAll("_", " ")], ["Occurrences", record.occurrence_count], ["Intake state", record.intake_status?.replaceAll("_", " ")]);
    renderDefinitionList(byId("proposal-meta"), proposalMeta);
    byId("proposal-cloud").textContent = record.intake ? "Created locally from an unsatisfied chat request. No cloud provider was invoked. Optional Mistral development remains a separate disclosed human action." : (record.cloud_assisted ? `${record.provider} / ${record.model || "configured model"}; data class ${record.cloud_data_class || "unspecified"}. This output is advisory and cannot approve itself.` : "No cloud provider is recorded for this proposal.");
    byId("proposal-markdown").textContent = record.proposal_markdown || "No proposal text available."; renderChecklist(byId("proposal-checklist"), record.review_checklist || [], "No checklist file was supplied.");
    const approved = record.proposal_gate === "approved"; byId("preview-proposal-approval").disabled = approved; byId("proposal-approval-confirm").hidden = true; byId("proposal-confirmation").value = ""; byId("proposal-approval-status").textContent = approved ? "This exact proposal revision is approved for Beta implementation." : "Review the brief and checklist before opening Gate 1.";
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

async function selectBeta(betaId) {
  try {
    const envelope = await callSoul("skill_studio.betas.get", { beta_id: betaId }); const record = dataOf(envelope).record; if (!record) return;
    state.selectedBeta = record; state.selectedProposal = null; state.betaRunPreview = null; state.betaPromotionPreview = null; showStudioDetail("beta"); renderStudioLists();
    byId("beta-title").textContent = record.beta_id; byId("beta-description").textContent = record.description || "No Beta description."; byId("beta-maturity").textContent = record.maturity?.replaceAll("_", " ") || "beta";
    renderDefinitionList(byId("beta-meta"), [["Proposal", record.proposal_id], ["Risk", record.risk], ["Runnable", record.runnable ? "human-confirmed only" : "no"], ["Tests", `${record.test_summary?.passed || 0}/${record.test_summary?.declared || 0} passing`], ["Current revision", record.test_summary?.tested_current_revision ? "tested" : "not tested"], ["Promotion", record.promotion_state?.replaceAll("_", " ")]]);
    renderChecklist(byId("beta-tests"), record.required_tests || [], "No required tests are declared; promotion is blocked."); renderChecklist(byId("beta-weaknesses"), (record.known_weaknesses || []).map((text) => ({ text })), "No known weaknesses were declared.");
    byId("preview-beta-run").disabled = !record.runnable; byId("beta-run-confirm").hidden = true; byId("beta-run-output").hidden = true; byId("beta-run-status").textContent = record.maturity === "legacy_alpha_scaffold" ? "Legacy alpha scaffold: visible for migration, never runnable." : (record.runnable ? "A preview and exact human confirmation are required." : "Beta package is incomplete or has an invalid entrypoint.");
    byId("beta-promotion-confirm").hidden = true; byId("beta-promotion-status").textContent = "Gate 2 checks Gate 1, implementation, test evidence, and revision integrity.";
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

async function bootstrap() {
  try {
    const envelope = await callSoul("application.bootstrap"); lifecycle(envelope); const data = dataOf(envelope); const providers = data.providers?.providers || [];
    const active = providers.find((provider) => provider.available || provider.configured) || providers[0]; byId("provider-label").textContent = active ? `Provider ${active.id || active.name || "ready"}` : "Provider local";
    byId("config-label").textContent = data.configuration?.ok ? "Config valid" : "Config attention"; await loadChats(true); await refreshStatus({ automatic: true });
  } catch (error) { byId("connection-label").textContent = "Disconnected"; showError(error); }
}

byId("chat-tab").addEventListener("click", () => switchTab("chat"));
byId("studio-tab").addEventListener("click", () => switchTab("studio"));
byId("preview-proposal-approval").addEventListener("click", previewProposalApproval);
byId("proposal-confirmation").addEventListener("input", () => { byId("execute-proposal-approval").disabled = !state.proposalApproval || byId("proposal-confirmation").value !== "APPROVE_PROPOSAL_FOR_BETA_BUILD"; });
byId("execute-proposal-approval").addEventListener("click", executeProposalApproval);
byId("preview-beta-run").addEventListener("click", previewBetaRun);
byId("beta-run-confirmation").addEventListener("input", () => { byId("execute-beta-run").disabled = !state.betaRunPreview || byId("beta-run-confirmation").value !== state.betaRunPreview.confirmation_phrase; });
byId("execute-beta-run").addEventListener("click", executeBetaRun);
byId("preview-beta-promotion").addEventListener("click", previewBetaPromotion);
byId("beta-promotion-confirmation").addEventListener("input", () => { byId("execute-beta-promotion").disabled = !state.betaPromotionPreview?.ready || byId("beta-promotion-confirmation").value !== "APPROVE_BETA_FOR_PROMOTION"; });
byId("execute-beta-promotion").addEventListener("click", executeBetaPromotion);
byId("new-chat").addEventListener("click", createChat);
byId("clear-chats").addEventListener("click", openClearDialog);
byId("close-clear-dialog").addEventListener("click", () => byId("clear-dialog").close());
byId("clear-mode").addEventListener("change", () => { byId("clear-title-field").hidden = byId("clear-mode").value === "all"; resetClearPreview(); });
byId("clear-title").addEventListener("input", resetClearPreview);
byId("preview-clear").addEventListener("click", previewClear);
byId("clear-confirmation").addEventListener("input", () => { byId("execute-clear").disabled = !state.clearPreview || byId("clear-confirmation").value !== "CLEAR_CONVERSATIONS"; });
byId("execute-clear").addEventListener("click", executeClear);
byId("preview-forget").addEventListener("click", previewForget);
byId("forget-confirmation").addEventListener("input", () => { byId("execute-forget").disabled = !state.forgetPreview || byId("forget-confirmation").value !== "DELETE_AND_FORGET_CONVERSATION"; });
byId("execute-forget").addEventListener("click", executeForget);
byId("pin-chat").addEventListener("click", togglePin);
byId("refresh-status").addEventListener("click", refreshStatus);
byId("composer").addEventListener("submit", sendMessage);
byId("message-input").addEventListener("keydown", (event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); byId("composer").requestSubmit(); } });
bootstrap();
