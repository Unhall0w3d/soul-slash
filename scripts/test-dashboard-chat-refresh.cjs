"use strict";
const { readFileSync } = require("node:fs");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const source = readFileSync(require("node:path").join(__dirname, "../assets/dashboard/dashboard.js"), "utf8");
const start = source.indexOf("async function loadChats(");
const end = source.indexOf("\nfunction resetConversationView", start);
assert(start >= 0 && end > start);
(async () => {
  for (const terminal of ["canceled", "blocked_for_human_review", "complete", "awaiting_input"]) {
    let status = terminal, rendered = false;
    const context = vm.createContext({
      state: { activeChat: { id: "fixture" } },
      callSoul: async () => ({ lifecycle_state: "complete", data: { records: [{ id: "fixture" }] } }),
      lifecycle: envelope => { status = envelope.lifecycle_state; },
      dataOf: envelope => envelope.data,
      replaceChatProgress: () => {}, renderChatList: () => { rendered = true; },
      selectChat: async () => {}, resetConversationView: () => {}
    });
    await vm.runInContext(`${source.slice(start, end)}\nloadChats(false)`, context);
    assert.equal(status, terminal, "list success must not overwrite request outcome");
    assert.equal(rendered, true);
  }
  console.log("Dashboard refresh: four terminal states preserved");
})().catch(error => { console.error(error); process.exitCode = 1; });
