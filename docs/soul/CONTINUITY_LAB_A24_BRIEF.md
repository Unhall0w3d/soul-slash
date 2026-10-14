# Continuity A24: bounded LibreChat usability trial

Date: 2026-10-13. Current user authorizes proceeding through the staged LibreChat
trial and raising the foreign AMD allocation threshold from 512 MiB to 1 GiB.
This is exact trial activation authority, not persistent service promotion.

## Scope and limits

- Change the shared `AmdWhisperDevice` foreign-client resident-allocation cutoff
  to 1 GiB (refuse at or above it). This also affects Whisper handoff and external
  AMD workload admission. Preserve compute-activity detection, desktop/managed
  ownership handling, telemetry reconciliation, caller free-memory requirements,
  leases, thermal/resource aborts, and no-eviction behavior.
- Preserve the working Qwen model, Core, model service, ordinary Soul memory,
  existing conversations, Mongo, and unrelated LibreChat endpoints/settings.
- Activate only the previously staged SoulContinuity endpoint/model through an
  exact backed-up merge of `/etc/librechat/librechat.yaml` and its environment.
  Generate/enroll a local operator bearer token privately, never in outputs,
  argv, model input, screenshots, or repository. Use supported host escalation;
  if sudo requires authentication, have the operator enter it in a local terminal.
- Use a new immutable private root under `Soul/runtime/continuity-lab/`; record
  its exact name in the assessment. Retain synthetic trial inputs/replies locally
  until an authorized cleanup. Existing backups may include them. Do not import
  real chat history. Browser sign-in uses the operator's existing account.
- Restart only LibreChat for the authorized configuration activation. The adapter
  stays a bounded foreground process: at most 3600 seconds, 64 HTTP requests,
  12 new model generations total across initial and resumed invocations. Stop
  and verify listener/worker cleanup before beginning the model comparison.
- Activation repair (October 14): if `/var/backups` is absent, create only that
  exact root-owned 0700 child after verifying the existing root-owned safe `/var`
  parent. Reject unsafe existing paths rather than changing their permissions.
  Validate with the installed schema under the existing `librechat` account,
  not root; no new standing privileged route is introduced.
- Do not install a unit/timer or leave a process awaiting further user input
  after the task returns. Keep exact protected rollback copies; if activation
  fails, restore only the two changed files and restart only LibreChat.

## Acceptance and ownership

Primary owns admission, credentials, privileged configuration, foreground runtime,
browser interaction, and independent read-back. Read-only delegation may map
client contracts and later experiment design, but cannot grant activation.

Deterministic checks: exact 1 GiB allocation boundary and below/above cases;
active compute still denied; existing device, external-workload, and Whisper
handoff suites; changed Ruby syntax. Validate the merged LibreChat config with
its installed schema and preserve unrelated settings. Run affected adapter
checks only for changed contracts or observed integration defects.

Browser checks use synthetic content: first reply; preference correction/callback;
reload and stable conversation mapping; independent chat without leakage;
refused changed history/fork; stop/resume with same journal. Verify exact retry
after durable commit without another generation, using a coordinated transport
check if the UI cannot expose that operation; label it separately from UI proof.
Record visible outcomes, errors, resource/admission refusals, generation counts,
journal evidence, and operator-acceptance gaps. No model quality claim follows
from HTTP or fixture success alone.

## Follow-on experiment

The same user authorizes a separate bounded primary-model comparison after this
trial: baseline Qwen8 versus one AMD candidate, reasoning/output-contract/task-
difficulty variation, independent repeats, self-reconsideration control, and
equalized compute budget. Its protocol, fresh fixtures, budget, and acceptance
criteria must be frozen separately before inference. No new model adoption or
working configuration change is part of that comparison.
