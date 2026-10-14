# Continuity A24/A25 — LibreChat trial and controlled comparison

**2026-10-14 migration hold:** the operator paused further experimental work
pending migration and restoration. Preserve the implementation, successful A24
trial and failed A25 window. Do not rerun calibration, resume inference, or
interpret source checkpointing as deployment/acceptance. The earlier calibration
budget question is deferred with the experiment, not an outstanding action to
execute during migration preparation.

2026-10-13. Scope is the current user's approved
[A24 trial](../soul/CONTINUITY_LAB_A24_BRIEF.md) followed by the separate
[A25 experiment](../soul/CONTINUITY_LAB_A25_BRIEF.md). Updated October 14:
**A24 activation and the exercised synthetic UI flows passed; A25 stopped at
an unscored harness gate. No scored model-comparison result is available.**

## Activation repair — October 14

The operator's attempted activation returned `Errno::ENOENT`, `backup:null`,
`mutation_started:false`. This supersedes the preceding "completed successfully"
selection: activation did not complete. Exact host path inspection established
that `/var/backups` is absent; both configuration files, Node, the package, staged
endpoint file and private token parent exist. The original helper's unconditional
`File.realpath('/var/backups')` therefore fails before backup/token/configuration
writes. LibreChat remains active with the same October 9 service start.

The repaired helper validates `/var` and securely creates only the exact missing
`/var/backups` child, mode 0700. It accepts a safe existing directory but refuses
symlinks, noncanonical paths, wrong ownership, group/world-write access, files
and missing ancestors; it does not recursively create paths or chmod unsafe
pre-existing directories. Failure output now includes a fixed stage label, never
raw exception text, configuration or credentials.

The host's installed `/usr/lib/librechat/package.json` is owned by `librechat`,
so the schema check now uses `runuser -u librechat -- /usr/bin/node` rather than
loading service-owned JavaScript as root. It receives serialized configuration
on stdin, uses a minimal environment and `/` working directory, and is bounded
by a 20-second timeout with five-second forced-termination grace. It does not
change the service account, package ownership or sudo policy.

Pinned Ruby 4.0.7 syntax passes; activation verification now passes 24 checks,
including the previous ten merge/credential checks, missing-directory regression,
unsafe path refusals, privilege-drop argv and sanitized stage reporting. The
unprivileged owner-mismatch fixture exercises refusal without changing host
ownership; it is not a privileged execution test. Sol added bounded temporary
fixtures only; primary diagnosed and changed the privileged path. No actual
activation, configuration write or restart has occurred in this repair turn.
At that point the operator command was ready for retry; A24 UI and A25 inference
remained pending. The follow-up results below supersede that activation status.

### Read-back repair and successful activation — October 14

The next operator attempt returned `RuntimeError` at `replace_configuration`,
`mutation_started:true`, `restored:true`, retaining originals at
`/var/backups/soul-continuity-a24-20261014-3144004-mbwuzk`.
The exact write path reproduced a Ruby encoding mismatch: `YAML.dump` yields
UTF-8, `File.binread` yields ASCII-8BIT, and non-ASCII labels make string equality
false even when every byte matches. The staged endpoint contains an em dash.
The helper now compares binary bytes, verifies original ownership/mode, and uses
separate configuration/environment read-back stages. Rollback also verifies bytes
and metadata before claiming restoration. All 30 activation checks pass, including
actual temporary-file writes, Unicode/ASCII, one-byte corruption, metadata mismatch,
and binary rollback. Primary retained privileged implementation; Sol added fixtures.

The user authorized a dedicated Kitty remote-control window. It uses a private
0700 temporary socket directory and socket-only control, with no permanent terminal
configuration changes. The user entered sudo authentication locally. Activation
completed with protected originals and receipt at
`/var/backups/soul-continuity-a24-20261014-3190483-8fjqg1`.
Independent sanitized root read-back confirmed exact scoped YAML/environment
merges, before/after hashes, root:librechat 0640 configuration, operator 0600 token,
and equality of this run's originals with the preceding failed run's backups
(confirming that rollback). LibreChat is active, PID 3190582, started at
2026-10-14 10:45:56 EDT. The merged YAML contains non-ASCII text, and the corrected
byte verification succeeded. No secret values were printed.

### Bounded LibreChat trial — October 14

Private immutable adapter root:
`Soul/runtime/continuity-lab/librechat-a24-20261014T144842Z`.
Two foreground windows, each capped at 1500 seconds and six HTTP requests/six
generations; five generations actually completed across two isolated journals.
No real chat history or corpus was imported, and neither journal has notes.

Rendered UI checks:

- Chat `741e199d-9471-409e-a062-ea59b85a7aab` acknowledged teal, accepted the
  correction to amber, and replied `amber` after page reload on the same chat.
- New chat `8b02cbd6-c614-42ee-a58b-f4e36c3b03b5` did not reveal either color.
  Its exact answer was `You do not know.`: isolation held for this example,
  but the pronoun is awkward and this is not broad conversational-quality proof.
- Editing that second chat's first message produced a visible HTTP 409 history
  conflict, leaving its one-event journal unchanged.
- A visible-messages UI fork, `dc6105c2-7e28-42a3-83df-b5e230f33aed`, likewise
  produced HTTP 409 when asked to continue. No adapter lineage was created for it.
- The first window exited `canceled` before a proposed transport check, which
  received connection refused. The initiating cancellation source is unconfirmed;
  it was not a failed generation or a demonstrated request-limit exit. Worker and
  listener absence plus both journal integrity checks were verified before the
  explicitly planned resume window. No in-flight inference was silently retried.
- After resume, the original chat continued with `You settled on amber, replacing
  teal.`. This tests adapter restart, not model-server restart.
- Separate authenticated loopback checks replayed the third completed turn twice:
  identical completion `chatcmpl-42510f82d64b1893facc6b2c1f4b9898`, same reply,
  `replayed:true`, all 16 then-existing commits unchanged. A further transport
  check discarded the fourth turn's replay body after receiving HTTP 200 and
  retried: completion `chatcmpl-e3e7c3c89687717fa28e052a27d5fbb1`, same reply,
  `replayed:true`, all 20 commits unchanged. This is response-loss/replay evidence
  for already committed turns, not a browser disconnect during fresh inference.

Final journal checks: original lineage `0797a6292cc4decdfcd4ff5dc1d0efdb`, four
complete events/16 transactions; isolated lineage `4b3eaae93cdedccc585dc8cb7c0edb12`,
one complete event/four transactions. Both validate, zero notes. Second window
exited `complete`; ports 8094/8096 absent and Qwen PID 1079343 remains active.
Screenshots captured correction/recall and visible rejection in the browser
tool. One browser console warning reported token refresh after the LibreChat
restart; subsequent requests and reload succeeded. Human usefulness acceptance
remains distinct. No permanent adapter service was installed.

## Current state

- Shared AMD foreign-client admission cutoff changed from 512 MiB to 1 GiB.
  The cutoff is per foreign DRM client; at or above 1 GiB is refused. An idle
  allocation below the cutoff is not alone a refusal. Active compute, VRAM/RAM
  availability, ownership reconciliation, lease and thermal checks remain.
  This source change also affects the next Whisper handoff using this module;
  no resident service was restarted just to load it.
- LibreChat is running and signed in. The synthetic trial established the
  specific inference/UI/recovery behaviors above; the bounded adapter is now off.
- Activation completed and independent file/service read-back passed as recorded
  above. The configured trial model is visible in LibreChat's rendered picker;
  the bounded synthetic conversation/recovery checks above now pass. Human
  usefulness acceptance and wider conversation quality remain separate.
- The first frozen A25 series stopped after two unscored Qwen feasibility
  generations and zero scored cells, at a native-template assertion. The AMD
  candidate was loaded but did not generate. All owned process/lease/listener
  cleanup and preservation checks passed. The repair and budget gate are below.
- Existing Qwen service, working model/Core, prior evidence, ordinary memory,
  LACT settings and unrelated dirty work are preserved. No model is adopted.

## Activation handoff

Completed procedure, retained for audit; do not rerun activation merely because
the bounded adapter is stopped. The operator command was:

```bash
sudo /home/bhones/.rbenv/versions/4.0.7/bin/ruby /home/bhones/Projects/soul/scripts/activate-continuity-librechat-a24.rb --apply
```

The one-shot helper merges the staged endpoint and model specification without
removing existing entries, validates the installed LibreChat schema, preserves
other environment lines, refuses conflicting credentials, creates a private
operator-owned token, backs up both root-owned files under a fresh private
`/var/backups/soul-continuity-a24-*` directory (securely creating the parent if
absent), atomically replaces each file,
and restarts only `librechat.service`. Failure or a handled interruption after
mutation attempts restoration from the exact originals and a LibreChat restart.
There is no cross-file filesystem transaction or guarantee against SIGKILL/power
loss; protected backups are retained for recovery. It does not install sudoers,
a privileged account, unit, timer or daemon. No credentials are printed.

After activation, independently verify the endpoint/UI and service status, create
a fresh private adapter root, and start a bounded foreground adapter. Use at
most 12 generations across initial/resumed windows. Verify first reply,
preference correction and callback, reload with stable history, isolated second
conversation, changed-history refusal, and durable stop/resume. Where exact
transport retry is not exposed by the UI, label its separate transport check.
Close/reap the adapter before any AMD comparison. Do not weaken login or invent
credentials to bypass this attended step.

## A25 experimental design

The chosen comparison is resident Qwen3-8B Q4_K_M on NVIDIA versus the already
cached Qwen3.5-9B Q4_K_M on AMD. Previous qualification established the candidate's
GPU fit; the new native thinking/grammar combinations remain unqualified.
Nine billion versus eight billion parameters is a modest size difference and
also a family/runtime/hardware difference. Results cannot isolate parameter-count
causation or establish a broad frontier-capability conclusion.

Six fresh held-out tasks form three easy/hard pairs: eligibility/cost comparison,
multi-step arithmetic and time, and current-revision evidence joins with missing
values. These are narrow synthetic reasoning tasks, not the full Soul workload.
Their answers are independently recomputed from the supplied evidence. No old
task answers or reviewer outputs enter the model-facing packets.

The design crosses model, native thinking on/off and strict final JSON/relaxed
prose. Each initial answer has its own source-only reconsideration, including
bounded malformed answers so protocol repair remains measurable. Three fixed
independent seeds provide 144 initial and 144 reconsideration slots. Eighteen
extra hard-task calls compare a single 1536-token/90-second thinking call with
two 768-token/45-second non-thinking calls. This equalizes practical allowance,
not actual consumed compute or FLOPs; prompt costs and tokenizer differences
remain observable confounds. Total: at most 306 scored generations plus eight
separate native feasibility calls, in three foreground windows of at most one
hour each. Prerequisite skips remain in the accounting.

The series manifest freezes all tasks, plans and source hashes before scored
inference. Each seed directory is exclusive: failed windows cannot be silently
resumed or overwritten. Runtime hashes and preservation snapshots must also
match across seeds. The runner records native actual prompts separately from
preview rendering, numeric sampler read-back, effective grammar, native usage,
limits, latency, final answer and raw private evidence. Reasoning-token counts
are unavailable unless the backend actually supplies them; character counts are
not token counts. Explanations in the final report summarize behavior, not raw
internal deliberation.

Semantic correctness and output compliance are separate. Exact-field checks
are retained as mechanical results. Identity-masked review of final answers
against frozen oracles is still required; it must not turn a keyword match into
semantic correctness. Invalid output, output exhaustion, final-size limits,
transport failures and skipped prerequisites have distinct labels. A strict/
prose comparison probes this answer contract, not all retrieval, review-envelope,
or long-conversation constraints in Soul. Six tasks/three seeds is exploratory;
ceiling performance would be inconclusive, not proof that all limitations are
gone. Reproducible per-task advantage is preregistered as candidate 3/3 versus
baseline at most 1/3 at the same condition/budget, without loss of contract validity.

## Implemented paths and verification

- `lib/soul_core/amd_whisper_device.rb` and its verifier: exact 1 GiB boundary;
  512 MiB and just-below admitted when otherwise idle, at/above refused, active
  compute still refused. Device 19 checks, external gate 14, and Whisper handoff
  90 plus its fixed-clock admission check passed.
- `scripts/activate-continuity-librechat-a24.rb` and verifier: initially ten pure
  merge, idempotence and credential-preservation checks passed; the October 14
  repairs expand this to 30 checks as documented above. Privileged activation
  and independent read-back are separate evidence, not inferred from fixtures.
- `scripts/support/continuity_cases_a25.rb` and verifier: 14 checks passed.
- `scripts/support/continuity_protocol_a25.rb` and verifier: 24 checks passed.
- `scripts/compare-continuity-a25.rb` and verifier: 62 checks passed after the
  native-template repair (48 before it), including
  actual-prompt/grammar evidence requirements, sampler drift, no-cache read-back,
  input/output/count ceilings, one-shot uncertain timeout, raw-evidence retention,
  inherited resource bounds and fake normal/failure/cancellation cleanup.
- Inherited deterministic M2/M3/M3B suites: 32/18/18 checks passed. These establish
  fixture behavior, not this experiment's actual GPU load, containment or cleanup.
- New Ruby syntax and scoped whitespace checks pass. No commit or push performed.

Sol handled bounded read-only native-protocol mapping and review, plus pure
protocol code; Luna handled the six pure fixtures. Primary retained host,
privileged activation, runtime lifecycle, integration and interpretation ownership.
Review caught the need to retain malformed finals for reconsideration, distinguish
final-size overflow, record actual rather than assumed prompts, and enforce
runtime stability across seeds. Those changes precede all new inference.

## A25 first compatibility window and repair — October 14

Frozen evidence series (retained unchanged):
`Soul/runtime/qualification/continuity-a25-20261014T150132Z-20261014-2-8ssnc6`,
seed `104729`. The AMD candidate loaded 34/34 layers on GPU; it made no generation.
The first two Qwen, thinking-off calibration calls returned the correct violet/7
values: strict JSON used 119 input/20 output tokens in 1.530 seconds; prose used
119/12 in 1.079 seconds. These are unrelated feasibility fixtures, not scored
tasks or an accuracy comparison.

The third preview failed `native thinking branch not attested` before generation.
The checker wrongly required an opening `<think>` suffix for both families.
The exact resident Qwen3 template instead ends its ON branch at the assistant
header, leaving the opening tag to generation; Qwen3.5 prefills the opening tag.
Both OFF branches close an empty reasoning segment. This is a harness failure,
not evidence that either model cannot reason. Two feasibility generations were
used; zero held-out/scored tasks were exposed.

The repair checks each pinned model's exact native branch ending, retains preview
evidence even on a failed assertion, and passes the reasoning/output-format fields
through the preview as well as the completion request. Actual response prompts
remain retained separately; preview is not assumed to establish final grammar
or reasoning separation. Four zero-generation checks against resident Qwen
passed ON/OFF × JSON/prose after the repair. No production runtime settings changed.
The 62 runner fixtures also cover both native ON forms, the shared OFF form,
cross-family/mode refusal, malformed/oversized prompts, preview payload parity,
and preservation of failed previews before generation. Protocol checks remain
24/24; runner and verifier syntax pass. No held-out case or scorer was changed.

Failure and preservation receipts report `unchanged:true`,
`runtime_unchanged:true`, `own_lease_gone:true`, `qwen_request_unsettled:false`,
and `endpoint_closed:true`; primary independently checked candidate/adapter
ports absent and Qwen PID unchanged. Final sampled temperatures were 41/55/42 C
edge/junction/memory; these are final readings, not peak values.

A fresh complete eight-call compatibility gate would bring cumulative unscored
generations to ten, two above the brief's current eight-call cap. User direction
on that explicit budget amendment is pending. No more inference or new series
has been started. A repair uses a fresh source-bound series, never overwrites
this failure, and does not expand the 306 scored-slot cap or thermal/runtime gates.

## Remaining gates

1. Completed: operator activation and primary sanitized read-back.
2. Completed: bounded synthetic LibreChat trial and cleanup as above; human
   usefulness judgment and broad conversational quality are not inferred.
3. Harness regression checks are complete; resolve the two-call calibration
   budget amendment. Then freeze a new series and qualify all eight native
   thinking/final grammar combinations without tuning scored tasks.
4. Run three seed windows with full cleanup/read-back between them. Stop on
   uncertain inference, resource failure, unsupported native contract or drift;
   retain evidence and distinguish a harness/runtime limitation from model failure.
5. Perform identity-masked semantic assessment, compare all paired cells and
   budget contrasts, and report limits/interactions rather than selecting only wins.

No conclusion yet about capability, elicitation or protocol as the primary
cause. No trained adapter, automatic reviewer dependency, ordinary-memory
promotion, persistent listener or working-model replacement is authorized by
these trial results alone.
