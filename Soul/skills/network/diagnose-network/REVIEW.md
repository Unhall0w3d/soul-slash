# Human Review — `network.diagnose`

Candidate: Fundamental Skill Cohort A1, slice 2

Branch/checkpoint: `codex/fundamental-network-diagnose-a1`

Date: 2026-08-02

## Candidate status

```text
candidate_complete
human_review_required
```

## What was implemented

- one `NetworkDiagnosticService` owns target validation, bounded local address
  and Linux-route evidence, DNS resolution, one-packet reachability, one TCP
  connect, timeouts, result normalization, lifecycle, and non-mutation metadata;
- deterministic Chat controls provide the same path to Chat and Voice Presence;
- four application operations expose the service without adding a second
  implementation;
- a modern skill package, production registry entry, invocation entry,
  capability mapping, user guide, current-state record, and tracker record agree;
- tests inject resolver, ping, socket, interface, and route evidence and perform
  no live network request.

## Files changed

- `lib/soul_core/network_diagnostic_service.rb`
- `lib/soul_core/network_diagnostic_chat_controls.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/chat_responder.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `Soul/skills/network/diagnose-network/`
- `Soul/skills/registry.yaml`
- `config/invocation_catalog.yaml`
- `config/operator_capability_catalog.yaml`
- `config/project_tracker_seed.json`
- `scripts/verify-fundamental-network-diagnose-a1.rb`
- `Makefile`
- `docs/soul/FUNDAMENTAL_NETWORK_DIAGNOSE_A1_BRIEF.md`
- `docs/skills/NETWORK_DIAGNOSE.md`
- `docs/assessments/FUNDAMENTAL_NETWORK_DIAGNOSE_A1_REVIEW.md`
- current-state, skill, invocation, and generated registry/catalog documentation

## Commands and deterministic results

```text
make verify-fundamental-network-diagnose
19 checks passed

python "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" Soul/skills/network/diagnose-network
Skill is valid

make verify-invocation-catalog
15 checks passed

make verify-operator-capability-catalog
passed

ruby scripts/verify-phase12b-in-process-application-api.rb
candidate-ready

ruby scripts/verify-chat-intent-and-interaction-boundary.rb
35 checks passed

ruby scripts/verify-documentation-registry-refresh-phase38.rb
passed

ruby scripts/verify-assistant-skill-catalog-phase43.rb
passed

make test-soul
passed

local host smoke: snapshot + localhost resolve + 127.0.0.1 ping + 127.0.0.1:4567 TCP
all four lifecycle states: complete; TCP payload bytes: 0
```

## Local LLM eval

Not used. Target validation, command construction, timeouts, socket behavior,
authority, and lifecycle are deterministic boundaries that model output cannot
approve. Natural-language coverage uses exact tested request grammar.

## Memory

Memory keys added or used: none.

No skill-private state, cache, index, history, or durable memory was added.
Network evidence may appear in the requesting local conversation transcript
through the existing Chat store; the skill adds no separate retention path.

## Lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `blocked_for_human_review`

`canceled` remains part of the contract but no operation waits for user input or
continues after return. Every path reports `mutation: none`.

## Risk classification

`read_only_network` — low mutation risk, bounded outbound-contact and local
network-metadata privacy considerations.

```text
Shell interpolation: no
Broad scan or enumeration: no
Application payload: 0 bytes
Automatic retries: 0
Background continuation: no
Privilege or configuration mutation: no
```

## Known weaknesses

- route evidence is Linux `/proc/net/route` IPv4 evidence; IPv6 routes and
  non-Linux route tables report unavailable rather than being inferred;
- ICMP may be unavailable or filtered, so no reply is not a global failure
  claim;
- single-label hostnames may use the host resolver's configured search policy;
- exact Chat grammar is intentionally narrower than general networking speech;
- a requested local snapshot places private IP evidence in the local Chat
  transcript; and
- `ping` must exist at one reviewed absolute path.

## Human review checklist

```text
[ ] Only one explicit operation runs per request
[ ] URL, CIDR, range, wildcard, option, multiple-target, and invalid-port inputs fail closed
[ ] Ping uses one fixed argv-only command with one packet and no shell
[ ] TCP sends zero application payload bytes and closes immediately
[ ] Timeouts and automatic-retry count are bounded
[ ] Ordinary networking conversation does not invoke diagnosis
[ ] Chat, Voice Presence, API, registry, invocation, capability, docs, and tracker agree
[ ] No mutation, service, watcher, schedule, memory, cache, or background process was added
```

## Human review outcome

```text
Outcome: pending
Reviewer: human owner
Date:
Decision summary:
Required changes:
```
