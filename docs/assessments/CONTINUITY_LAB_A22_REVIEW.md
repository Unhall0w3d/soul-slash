# Continuity Lab A22 — LibreChat connection readiness

Date: 2026-10-12. **Candidate ready for a controlled connection trial; not yet
connected or deployed.** Owner authorized continuation through readiness and
delegated non-human-required implementation decisions. See the
[A22 brief](../soul/CONTINUITY_LAB_A22_BRIEF.md) and
[connection handoff](../guides/CONTINUITY_LIBRECHAT_HANDOFF.md).

## Implementation and decisions

- Pure authenticated [chat application](../../lib/soul_core/continuity_lab/chat_application.rb):
  fixed model, strict text-only JSON, origin rejection, safe errors, standard
  JSON and buffered SSE. No tools, paths, credentials or system roles in input.
- [Journal gateway](../../lib/soul_core/continuity_lab/chat_gateway.rb): private
  fd-anchored directories, immutable source/config/corpus binding, serialized
  writers, staged creation, per-conversation lineages, full-history validation,
  stable completion identity and durable retry recovery. Existing Runtime
  handles uncertainty; no second inference is authorized by a transport retry.
- [Executor](../../lib/soul_core/continuity_lab/chat_executor.rb) and
  [foreground CLI](../../scripts/continuity-lab-chat.rb): existing admission and
  fresh bubblewrap worker, fixed installed model/build, quiet-window preflight,
  finite duration/call ceilings and cancellation. No unit, scheduler, automatic
  model load/switch, dashboard route or production-memory service was added.
- [Staged LibreChat config](../examples/continuity-lab-librechat-a22.yaml) uses the
  installed client contract. One local operator credential and new linear chats
  only; multi-user access, arbitrary prompts, branches and uploads are excluded.

Deliberate changes to the earlier plan:

| Decision | Consequence |
| --- | --- |
| LibreChat-first narrow adapter instead of dashboard-first | Reaches the requested interaction surface without building another UI; UI acceptance still pending |
| Keep A19 chronological answer-only profile, not A20 guidance | Preserves the better-understood baseline; existing factual/selection mistakes remain possible |
| Keep complete transport evidence but bounded model context | At most three recent exchanges and bounded sources reach Qwen; no promise of whole-chat recall |
| Keep A21 verified selection an explicit separate CLI | No unqualified natural-language-to-calculation routing; ordinary chat prose is unverified |
| Buffer SSE until the reply is journaled | Retry-safe delivery, but no visible token streaming |
| Foreground single-operator trial before persistent deployment | Requires a quiet window and manual start; no unattended availability claim |

This is a useful conversation surface over retained evidence, not a finding of
process identity, subjective continuity, autonomous learning or full notebook
usability. Minimal experimental context remains separate from ordinary Soul
memory and any future Soul-identity condition.

## Deterministic evidence

Pinned interpreter: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.
Run commands and final counts are retained in `validation.json` alongside the
live evidence. Primary suites:

- `scripts/verify-continuity-lab-chat-http-a22.rb` (47 passed): authentication, origin,
  malformed/duplicate JSON, binary HTTP body decoding, bounds, roles, errors,
  parameter policy, JSON/SSE serialization.
- `scripts/verify-continuity-lab-chat-gateway-a22.rb` (25 passed): actual Store/Runtime with
  scripted inference; retry/reopen/history/isolation, failure and concurrency,
  quotas, source/config changes, hostile paths and initialization recovery.
- `scripts/verify-continuity-lab-chat-integration-a22.rb` (11 passed): actual HTTP parser on
  `UNIXSocket.pair`, durable commit before disconnect, JSON/SSE retry, CLI checks,
  invalid corpus/options and unsafe key refusal before host preparation.
- `scripts/verify-continuity-lab-librechat-client-a22.cjs`: five checks with the
  installed ChatOpenAI serializer/SSE parser and local Ruby application fixture;
  fake fetch only, no external network or model. The managed sandbox stalled a
  nested Node→Ruby process even in a minimal echo control; authorized host
  fixture execution passed. This is not evidence of a live LibreChat UI turn.
- `scripts/verify-continuity-lab-chat-lifecycle-a22.rb` (11 passed on authorized
  host): actual ephemeral loopback listener and isolated `timeout_probe` worker;
  explicit stop and deadline-style stop reap the child before request return,
  then close the listener and clear request threads. No model calls. Sandbox
  binding was denied; the test used the supported host route, not weaker isolation.
- Installed LibreChat `configSchema` accepts the staged YAML. No current secret
  environment values were read or changed.

Affected existing suites passed once: core A0 (21), context A1 (30), admission
A9 (39), recovery A0 (149), recovery A1 (94), helper A21 (17 groups), and chat
A19 (10): 360 checks/groups. Required actual isolated-worker A2 (40) and streamed
isolation/socket A7 (17) also passed with synthetic backends: 417 existing checks
in total, plus 99 new A22 checks. Nine new Ruby syntax checks, the JavaScript
syntax check, scoped whitespace/Markdown-link checks and `git diff --check`
passed. New tests did not change existing prompt/runtime
profiles, historical formats or ordinary Soul behavior. Check counts are coverage
evidence, not performance/reliability estimates.

## Bounded live result

Evidence root:
`Soul/runtime/qualification/continuity-lab-a22-20261012T214917Z/`.
Baseline freezes host/config/profile/corpus/source hashes and the six cases.
All six application→gateway→fresh worker→resident Qwen requests reached durable
replies; each exact retry returned the saved reply without a model call.

| Case | Time | Primary semantic assessment |
| --- | ---: | --- |
| Rainy-afternoon conversation | 4.006 s | Two appropriate indoor ideas |
| Tea → coffee correction | 3.469 s | Used coffee and selected one indoor activity |
| Callback after gateway reopen | 2.870 s | Correctly recalled coffee |
| Explicit synthetic source lookup | 2.183 s | Correct exact day: Tuesday |
| Unsupported signer | 2.188 s | Did not invent a signer; awkward “you don't know” wording |
| Separate-conversation query | 2.392 s | Did not import the other chat's preference |

Times cover individual requests, not initial hashing/preflight. This small smoke
test does not erase the A19/A20 errors or establish everyday reliability. The
model server remained resident; only workers were fresh and the gateway reopened.
No production adapter listener or LibreChat route was activated in this trial.

### Failure disclosure and reconciliation

After the six requests/retries, the harness exited 1: a `gateway` variable scoped
inside the timeout block was unavailable in `ensure`, preventing final summary
output. Its closeout variables are now initialized in outer scope for future runs. Do not
rewrite the exit as a clean harness pass or rerun inference to hide the failure.

Independent, zero-generation read-back retained in `reconciled-closeout.json`
confirmed three integral stores (3, 1 and 2 events), zero notebook writes, all
six durable results/retries, no worker processes, fresh model-idle observation,
and 4,382 prior evidence files unchanged. Implementation hashes matched at that
read-back. That closes the live outcome without treating a reporting failure as
a model failure or concealing it.

Subsequent deterministic review hardened private-parent creation, then added
staged root initialization under a parent lock. These path/setup changes and
the reporting repair occurred **after** the live trial, without prompt/profile
changes or more inference. The historical adapter root stays bound to its older
implementation hashes; it is evidence, not a root to reopen with the new adapter.
Its underlying stores remain independently replayable. New candidate validation
uses fresh fixtures rather than modifying that manifest.

## Boundaries and remaining gate

- No credentials enrolled/transferred, private history imported, existing files
  deleted, configuration promoted, services restarted or network rules changed.
- Runtime evidence only in the dedicated synthetic qualification namespace;
  no ordinary-memory keys added, no autonomous notes or policy promotion.
- Lifecycle results: complete reply/replay; explicit validation/conflict/busy/
  unavailable failure; canceled/deadline foreground stop. Uncertain model intent
  stays retained for review. A transport retry never grants another generation.
- Root hashes are compatibility/provenance checks, not protection against a
  malicious same-user process. A bearer token is single-operator authority, not
  per-user access control. The foreground admission gate cannot exclude arbitrary
  programs calling the model server directly.
- Stop is bounded, not necessarily instant while a broker request is in flight.
  Do not claim GPU cancellation or model idle from a worker-probe test alone.
- Actual LibreChat UI, first real conversation, owner acceptance and model-server
  restart comparison remain unperformed. Automatic helper routing, full notebook
  use, arbitrary long-history recall and persistent operation are not delivered
  by this adapter milestone.

The next action is the exact local credential/configuration/foreground connection
window in the handoff, not another architecture choice. Preserve a rollback copy,
validate the merged configuration, restart only LibreChat, then perform the short
UI checklist. Human review is still required for protected activation/release;
candidate completion is not merge approval.
