# Chat Progress Summaries A1 Human Review

status: candidate_complete
risk: Class 1 - owner-local operational state and read-only projection

## What was implemented

- Immediate provisional rendering of the submitted Operator message before the
  response stream starts.
- Server-acceptance transition after the canonical user message is recorded.
- One concise working card updated from real Chat runtime lifecycle events.
- Bounded progress persistence in the existing application request receipt
  ledger.
- Read-only `chats.progress` recovery when conversations load or the Dashboard
  reloads.
- Conversation-scoped final reconciliation and one post-disconnect status
  reconciliation.
- Active-state indicators in the conversation rail, including reduced-motion
  behavior.

## Files changed

- `lib/soul_core/application_request_receipt_store.rb`
- `lib/soul_core/application_chat_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-chat-progress-summaries-a1.rb`
- `Makefile`
- current-state, API, roadmap, timeline, brief, and review documentation

## Deterministic verification

- `make verify-chat-progress-summaries` — PASS, 13 checks.
- `ruby scripts/verify-responsive-chat-and-web-research.rb` — PASS.
- `ruby scripts/verify-project-timeline-a1.rb` — PASS.
- `ruby scripts/verify-phase12b-in-process-application-api.rb` — PASS.
- `ruby scripts/verify-phase12c-foreground-dashboard.rb` — PASS through
  deterministic verification; its standing human visual-review gate remains.
- `ruby scripts/verify-persona-fidelity-a1.rb` — PASS.
- Ruby syntax checks for the touched service, receipt store, and facade — PASS.
- `node --check assets/dashboard/dashboard.js` — PASS.
- JSON parsing and staged whitespace checks — PASS.

## Local LLM evaluation

Not used. This slice changes deterministic lifecycle reporting and Dashboard
recovery, not model routing or response content.

## Known weaknesses

- Reload or conversation selection refreshes progress; the browser does not
  automatically reattach to a disconnected response stream.
- Chat remains intentionally single-send while any accepted Chat exchange is
  active.
- Picture understanding retains its existing stream-only progress behavior.
- Music, Visual, Backup, and maintenance progress are not made durable by this
  slice.
- Four-hour-stale incomplete receipts stop appearing active but remain in the
  bounded receipt history for diagnosis.

## Memory and lifecycle

- Memory keys: none.
- Durable operational state: bounded progress fields in the existing private
  application receipt ledger.
- Lifecycle observed: `reserved`, event-derived working states, `complete`, and
  `failed`.
- New mutation authority: none. `chats.progress` is read-only.

## Human review checklist

- [ ] Submit a message and confirm it appears before Soul's response.
- [ ] Confirm `sending` changes to accepted only after the server accepts it.
- [ ] Confirm one working summary updates in place rather than accumulating.
- [ ] Navigate to another conversation and back during a longer exchange.
- [ ] Reload during an accepted exchange and confirm active progress recovers.
- [ ] Confirm the terminal assistant message replaces the working card.
- [ ] Confirm the conversation rail active marker is readable and unobtrusive.
- [ ] Confirm ordinary drafting remains possible while sending is disabled.
- [ ] Confirm no private prompt or model-response text appears in the receipt
  progress projection.
