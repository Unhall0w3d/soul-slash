# Continuity → LibreChat: controlled connection handoff

Current update, 2026-10-14: **LibreChat activation and the bounded synthetic UI
trial completed. The foreground adapter is now stopped, so the configured trial
endpoint is not currently serving new messages.** See the
[A24/A25 execution receipt](../assessments/CONTINUITY_LAB_A24_A25_REVIEW.md)
for actual roots, rollback material, results and remaining gates. No persistent
adapter was installed. The procedure below is the historical A22 handoff, not
an instruction to repeat the completed activation.

Historical handoff, 2026-10-12: adapter implemented and qualified for a bounded,
single-operator connection trial. LibreChat was not connected yet. No service,
credential, firewall, ordinary Soul memory or model/Core default was changed.

2026-10-13 model-comparison update: [A23](../assessments/CONTINUITY_LAB_A23_REVIEW.md)
tested three larger offloaded candidates and alternate MoE placement. Keep the
existing Qwen8 for this trial: none demonstrated a decisive quality/latency
improvement. The original service was restored after both bounded windows and
is healthy/idle; no LibreChat configuration was activated. The A22 executor
discovers the fresh service PID during preparation. This host restart observation
does not substitute for journal/retry acceptance across a restart.

See the [A22 review](../assessments/CONTINUITY_LAB_A22_REVIEW.md),
[brief](../soul/CONTINUITY_LAB_A22_BRIEF.md) and
[staged YAML](../examples/continuity-lab-librechat-a22.yaml).

## What the first connection will provide

An explicitly selected `Soul Continuity (A22 trial)` LibreChat model, using the
existing Qwen3 8B Q4_K_M on the GTX 1070 through Soul's bounded foreground worker.
It supports new, text-only, linear conversations, durable replies and exact retry
recovery. It does not provide tool execution, attachments, cross-chat memory,
automatic note-taking, arbitrary system prompts or verified calculations.

The whole transport history is checked against the journal, but Qwen sees only
the current question, the selected corpus, and at most three recent complete
exchanges. The recent-history byte ceiling is 4,096; token packing can reduce
it further. Model input/output ceilings remain 3,072/768 in a 4,096-token window.
A complete journal is not complete model recall. The YAML's 65,536-token client
budget prevents premature client truncation; it does not enlarge Qwen's window.

Keep [A21's explicit verified-selection CLI](../../scripts/continuity-lab-select.rb)
separate. The chat answer has not become a source-verified computation merely
because that helper exists. General model reliability is still limited by the
A19/A20 results.

## Installed integration target (observed, not historical Annex topology)

| Component | Current observation |
| --- | --- |
| LibreChat | Native system `librechat.service`, active during inspection; v0.8.7 |
| Installation | `/usr/lib/librechat` |
| Config and environment | `/etc/librechat/librechat.yaml`, `/etc/librechat/librechat.env` |
| Unit | `/usr/lib/systemd/system/librechat.service` |
| Mongo | Existing `librechat-mongo`, image `mongo:8.0.20`, loopback port 27019 |
| Installed OpenAI-compatible client | `@langchain/openai` 1.4.5 |
| Proposed adapter route | `http://127.0.0.1:8094/v1`, not a public endpoint |

Only paths, package metadata and relevant installed source were inspected; no
existing environment secrets were printed. Do not resurrect the former Annex.
The native LibreChat process can reach the host loopback address; a future
container migration would require a different reviewed network arrangement.

The installed request controller creates a UUID for a first chat before custom
endpoint initialization. Its template resolver supports
`{{LIBRECHAT_BODY_CONVERSATIONID}}`. An ordinary custom endpoint with no prompt
prefix/tools can send only user/assistant messages. The staged configuration
passes the installed configuration schema, and the actual installed client
serializer/SSE parser passes a local fixture. This is not browser acceptance.

Reference: [LibreChat custom endpoint configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/custom_endpoint).
Recheck the installed contract after a LibreChat update.

## Historical activation procedure — superseded by completed A24 activation

1. Confirm an exclusive foreground inference window. The launcher requires the
   already resident qualified Qwen server and an eligible Core; it never starts,
   unloads or switches a model. No gaming, voice inference, swarm or other model
   clients during the trial. Cooperative leases cannot fence direct clients.
2. Use a dedicated owner-private parent and a new immutable root. Proposed root:
   `/home/bhones/Projects/soul/Soul/runtime/continuity-lab/librechat-a22`.
   Retain submitted messages/replies and the explicit corpus locally until an
   approved cleanup; no automatic expiry or deletion. Existing backups may
   include it. This must be understood before submitting private conversation.
3. Create a new random local bearer credential, in an owner-only file outside
   the repository, and enroll that same value locally as
   `SOUL_CONTINUITY_API_KEY` in LibreChat's environment. Do not paste it into
   chat, command arguments, screenshots, logs, source control or the model's
   prompt. The launcher expects an owned, canonical, non-symlink, single-link
   `0600` file containing 32–256 printable ASCII characters, optionally followed
   by a newline. This one credential is operator authorization, not multi-user
   isolation; conversation IDs are namespaces only.
4. Back up the exact two existing LibreChat configuration files locally with
   permissions preserved. Merge the staged endpoint/model specification into
   the existing YAML; do not overwrite unrelated endpoints, authentication or
   data settings. Validate the merged document with the installed schema.
   Inspect existing configuration privately at activation, not via broad dumps.
5. Initialize and check the root, then launch the adapter in an attended terminal
   using the commands below. No systemd unit, daemon or boot enablement is needed.
   Verify authenticated models/health locally without exposing the token.
6. Restart only `librechat.service` after its exact configuration/credential
   activation is approved. Do not restart Mongo or the resident model server.
   Open a **new empty chat**, choose `Soul Continuity (A22 trial)`, leave system
   prompts/tools/attachments disabled, and run the acceptance checks below.

Commands for the future connection window (not run by this handoff):

```bash
cd /home/bhones/Projects/soul
install -d -m 700 Soul/runtime/continuity-lab
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/continuity-lab-chat.rb \
  --init /home/bhones/Projects/soul/Soul/runtime/continuity-lab/librechat-a22
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/continuity-lab-chat.rb \
  --check /home/bhones/Projects/soul/Soul/runtime/continuity-lab/librechat-a22
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/continuity-lab-chat.rb \
  --serve /home/bhones/Projects/soul/Soul/runtime/continuity-lab/librechat-a22 \
  --key-file /home/bhones/.config/soul/continuity-a22.key \
  --approved-quiet-window --seconds 1800 --max-requests 32
```

The credential path is proposed, not enrolled. `--init` accepts an optional
`--corpus` JSON array of `{ "id": "...", "content": "..." }` records, selected
explicitly by the operator. Omitting it creates an empty corpus. Corpus, profile,
configuration and implementation hashes are immutable for that root.
`--check` validates the adapter root/binding, not every conversation or backend
readiness. Actual requests validate their own journal and admission state.

## Limits, shutdown and recovery

- Maximum 16 conversations per root and 32 turns per conversation. Abandoned
  conversation staging consumes quota. HTTP request ceiling defaults to 32
  (maximum 128); it includes requests other than successful chat completions.
- Foreground duration defaults to 30 minutes (maximum one hour). Ctrl+C, TERM,
  deadline or request ceiling ends the session. No process is intentionally left
  waiting after the foreground invocation returns. Stop cancels workers and
  joins requests; a currently blocked broker call may take its bounded timeout
  to unwind. This is not a promise of instantaneous cancellation of GPU work.
- Backend/Core/model mismatch, occupied admission or an incompatible request
  refuses rather than switching resources or silently degrading to a different
  model. Inspect the failure; don't repeatedly click regenerate.
- Identical completed requests recover the same saved reply without inference.
  Changed prior messages, imports, regeneration with changed history and forks
  are rejected. A client timeout can occur after commit; retry the exact request.
- An uncertain generation or failed terminal is retained and blocks automatic
  re-generation. Inspect the journal and confirm backend idle before resuming
  other inference work. A forced process kill cannot prove server-side idle.
- Failed initialization leaves `stage-<hex>` under the private parent, not a
  half-created final root. Retry can create a fresh final root; retain the stage
  for inspection. Existing destinations are never intentionally replaced.
- A code/config/corpus change refuses to reopen an old bound root. Do not edit
  hashes to bypass this check: use a fresh named root or a separately reviewed
  migration. No migration, cleanup or cross-root history import is provided.
- Rollback exposure: stop the foreground launcher, restore the exact prior
  LibreChat config/environment from the protected local copies, restart only
  LibreChat, and retain experimental evidence. Do not delete the Mongo database.

## First UI acceptance checklist

1. New chat sends a simple question and displays one complete answer. Buffered
   SSE deliberately appears after commit rather than token-by-token.
2. Correct a preference, then ask for the corrected value. Compare the visible
   history with the journal; do not infer all-history recall from this short test.
3. Reload the page and continue the same chat; verify stable conversation mapping.
4. A new chat must not receive a private preference from the previous chat.
5. During a coordinated test, disconnect after commit and retry unchanged; verify
   the same completion ID and no second inference. Edits/forks must visibly fail,
   not overwrite or blend lineages.
6. Stop the launcher, verify no adapter listener/worker remains, and confirm other
   LibreChat endpoints are unchanged. Resume the same root manually and test one
   continuation. This is adapter restart, not a model-server restart experiment.

Browser rendering, actual LibreChat history behavior and operator usefulness
remain acceptance gates. Model-server restart and controlled notebook/identity
comparisons remain separate research work, not prerequisites that block this
bounded connection trial.
