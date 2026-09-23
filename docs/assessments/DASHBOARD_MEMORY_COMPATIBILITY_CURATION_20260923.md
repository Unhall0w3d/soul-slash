# Dashboard and memory compatibility source curation — 2026-09-23

Status: isolated source candidate for human merge review. No service was
stopped, started, installed, or modified during this pass; no memory projection
or persistent memory mutation was run.

The dashboard proxy unit now wants the backend on startup without requiring the
backend for its own continued lifecycle. The retained September 17 owner record
reports a bounded live stop/start acceptance with HTTPS 502 while the backend
was stopped and HTTPS 200 after restart. That observation is historical; the
curation check exercised only the rendered unit contract.

The automatic projection reconciliation predicate was reformatted for Ruby
parser compatibility without changing the intended Boolean conditions. Its
prior owner record says human review is still required before merge or timer
reconstruction. The A33 deterministic verifier passed 15 checks here. No
private recovery receipts or host addresses are included in this packet.

Checks: `ruby scripts/verify-dashboard-proxy-lifecycle.rb`,
`ruby scripts/verify-memory-automatic-projection-reconciliation-a33.rb`,
and `git diff --check` passed in this worktree.
