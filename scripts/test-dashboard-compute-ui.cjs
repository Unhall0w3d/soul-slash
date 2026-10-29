"use strict";
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = readFileSync(path.join(__dirname, "../assets/dashboard/dashboard.js"), "utf8");
const html = readFileSync(path.join(__dirname, "../assets/dashboard/index.html"), "utf8");
const start = source.indexOf("const COMPUTE_POLICIES =");
const end = source.indexOf("\nfunction showError(", start);
assert(start >= 0 && end > start);
assert.match(html, /id="runtime-heading">Compute availability/);
assert.match(html, /id="core-label">Compute —/);
assert.match(source, /await refreshCompute\(\{ automatic: true \}\); await refreshStatus/);
assert.match(source, /addEventListener\("click", executeCompute\)/);
const actionsStart = source.indexOf("function renderMessageActions(");
const actionsEnd = source.indexOf("\nfunction renderMessages(", actionsStart);
assert(actionsStart >= 0 && actionsEnd > actionsStart);

function fixture() {
  const elements = new Map();
  const node = id => {
    if (!elements.has(id)) elements.set(id, {
      id, textContent: "", value: "", disabled: false, hidden: false, dataset: {}, children: [],
      replaceChildren(...children) { this.children = children; },
      append(child) { this.children.push(child); },
      addEventListener() {}, showModal() { this.open = true; }, close() { this.open = false; }
    });
    return elements.get(id);
  };
  const calls = [];
  const queue = [];
  const context = vm.createContext({
    state: { busy: false, computeStatus: null, computePreview: null },
    byId: node,
    document: { querySelector: () => node("runtime-card"), createElement: () => node(`element-${elements.size}`) },
    detailRow: (name, value) => ({ name, value }),
    dataOf: envelope => envelope.data,
    setBusy() {}, setCoreMenu() {}, prefillApprovalGate: () => { node("model-runtime-confirmation").value = ""; node("execute-model-runtime").disabled = true; },
    announce() {},
    callSoul: async (operation, params) => { calls.push([operation, params]); return queue.shift(); }
  });
  vm.runInContext(source.slice(start, end), context);
  return { context, node, calls, queue, run: expression => vm.runInContext(expression, context) };
}
const status = (policy = "available") => ({ policy, state: "resident", model: "member model", available: policy === "available", revision: 2, handoff: null });
const complete = data => ({ lifecycle_state: "complete", data });

(async () => {
  const f = fixture();
  f.queue.push(complete(status()));
  await f.run("refreshCompute()");
  assert.equal(f.calls[0][0], "compute.status");
  assert.equal(f.node("core-label").textContent, "Compute available");
  assert.equal(f.node("load-model-runtime").disabled, true);
  assert.equal(f.node("unload-model-runtime").disabled, false);

  const digest = "a".repeat(64);
  f.queue.push(complete({ ...status(), target_policy: "reserved", expected_digest: digest, confirmation_phrase: "SET_COMPUTE_POLICY" }));
  await f.run('previewCompute("reserved")');
  assert.equal(f.calls[1][0], "compute.preview");
  assert.equal(f.calls[1][1].policy, "reserved");
  assert.equal(f.node("model-runtime-dialog").open, true);
  assert.equal(f.context.state.computePreview.digest, digest);
  await f.run("executeCompute()");
  assert.equal(f.calls.length, 2, "confirmation is required before execute");

  f.node("model-runtime-confirmation").value = "SET_COMPUTE_POLICY";
  f.queue.push({ lifecycle_state: "blocked_for_human_review", errors: [{ message: "Active work is running" }], data: {} });
  await f.run("executeCompute()");
  assert.equal(f.calls[2][0], "compute.execute");
  assert.equal(f.calls[2][1].expected_digest, digest);
  assert.equal(f.context.state.computePreview, null);
  assert.equal(f.node("core-label").textContent, "Compute unavailable");
  assert.match(f.node("runtime-card-status").textContent, /Active work is running/);
  assert.equal(f.calls.length, 3, "a blocked reserve must not retry");

  f.queue.push(complete(status("reserved")));
  await f.run("refreshCompute()");
  assert.equal(f.node("core-label").textContent, "Compute reserved");
  f.queue.push({ lifecycle_state: "failed", errors: [{ message: "Status unavailable" }], data: status() });
  await f.run("refreshCompute()");
  assert.equal(f.node("core-label").textContent, "Compute unavailable");
  assert.match(f.node("runtime-card-status").textContent, /Status unavailable/);
  assert.equal(f.node("load-model-runtime").disabled, true);
  assert.equal(f.node("unload-model-runtime").disabled, true);

  const held = {...status(), handoff: {state: "running", provider_id: "amd-visual", member: "studio"}};
  f.queue.push(complete(held));
  await f.run("refreshCompute()");
  assert.equal(f.node("load-model-runtime").disabled, true);
  assert.equal(f.node("unload-model-runtime").disabled, true);
  assert.match(f.node("runtime-card-status").textContent, /running.*amd-visual.*studio/);
  const blockersStart = source.indexOf("function visualReadinessBlockers(");
  const blockersEnd = source.indexOf("async function refreshVisualResources(", blockersStart);
  vm.runInContext(source.slice(blockersStart, blockersEnd), f.context);
  assert.match(f.run('visualReadinessBlockers({runtime_ready:false, models_ready:false, missing_roles:["vae"], core:{allowed:true, reason:"Compute allowed"}})'), /renderer.*Missing or unverified model files: vae/);

  const rendered = [];
  const actionContext = vm.createContext({
    CORE_ACTIVATABLE_IDS: new Set(["daily"]), normalizeCoreId: value => value,
    document: { createElement: tag => ({ tag, children: [], append(...children) { this.children.push(...children); }, addEventListener() { throw new Error("legacy action must not bind execution"); } }) }
  });
  vm.runInContext(source.slice(actionsStart, actionsEnd), actionContext);
  const article = { append(element) { rendered.push(element); } };
  const legacyDigest = "b".repeat(64);
  actionContext.renderMessageActions(article, [
    { operation: "core.activate.execute", core_id: "daily", target_profile_id: "legacy", expected_digest: legacyDigest },
    { operation: "chats.creative.execute", flow_id: `creative_${"a".repeat(16)}`, chat_id: "chat_fixture", expected_digest: legacyDigest }
  ]);
  assert.equal(rendered.length, 1);
  assert.equal(rendered[0].children.length, 4);
  assert.equal(rendered[0].children[0].disabled, true);
  assert.equal(rendered[0].children[2].disabled, true);
  assert.match(rendered[0].children[1].textContent, /shared-compute handoff is pending/);
  console.log("Dashboard compute UI: status, preview, confirmation, blocked reserve, and failed status passed");
})().catch(error => { console.error(error); process.exitCode = 1; });
