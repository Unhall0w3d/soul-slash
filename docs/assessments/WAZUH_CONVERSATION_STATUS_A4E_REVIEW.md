# Wazuh Conversational Status A4e Review

## Candidate status

Implementation and live source qualification are complete. Merge remains the
final human gate before the overall Wazuh/ClamAV rollout enters the validated
archive.

## Implemented

- `security.status` is a production-registered internal skill with one
  read-only Chat/Voice invocation and no approval requirement.
- Explicit natural questions route to one deterministic foreground operation;
  topical security statements remain conversation.
- The service reuses the accepted A4a manager/agent collector, A4b alert
  collector, and A4d owner-reviewed posture projection.
- Only manager, agent, query-scope, severity-count, truncation, freshness, and
  posture aggregates enter conversation evidence.
- Raw and normalized event details, private addresses, paths, users,
  credentials, alert descriptions, rule IDs, and event IDs are discarded
  before the Chat evidence record is built.
- Current ClamAV signature and latest-scan state are explicitly uncollected
  because A3 does not centralize those receipts.
- Voice Presence uses the same `chats.send` route and tool metadata as the
  authenticated Dashboard. It has no separate security execution path.

## Files changed

- `lib/soul_core/conversation_security_status_service.rb`
- `lib/soul_core/conversation_tool_catalog.rb`
- `lib/soul_core/conversation_runtime.rb`
- `lib/soul_core/application_facade.rb`
- `Soul/skills/registry.yaml`
- `config/invocation_catalog.yaml`
- `config/operator_capability_catalog.yaml`
- `scripts/verify-conversation-security-status-a4e.rb`
- `Makefile`
- associated briefs, guides, state, roadmap, and tracker records

## Deterministic verification

```text
make verify-wazuh-conversation-status
make verify-wazuh-security-status verify-wazuh-alert-evidence
make verify-wazuh-alert-notifications verify-wazuh-alert-notification-deployment
make verify-wazuh-compliance-posture
ruby scripts/verify-invocation-catalog-a1.rb
ruby scripts/verify-dashboard-capability-guide-a1.rb
ruby scripts/verify-chat-intent-and-interaction-boundary.rb
ruby scripts/verify-conversation-weather-routing.rb
```

The A4e verifier covers fresh, attention, partial, and unavailable evidence;
raw-detail exclusion; deterministic Chat routing; evidence retention;
production registry and invocation discoverability; and the shared Voice
Presence route. All existing Wazuh and conversational regressions pass.

## Live evidence

On 2026-08-03 the exact production configuration was exercised through a
temporary Chat store. The invocation returned `skill_only` with tool
`security.status`, manager `healthy` with 10/10 required daemons, 2/2 agents
active, and a bounded 24-hour level-7+ alert projection. It reported 132
matching alerts, disclosed that the newest 100 were returned and truncated,
and contained zero raw event details. The owner-reviewed posture remained
explicitly separate at raw Wazuh score 45% with 11 genuine remaining
decisions. No production transmission or conversation evidence was retained.

## Lifecycle, memory, and risk

- Lifecycle: one foreground invocation terminates `complete`, including honest
  partial or unavailable evidence.
- Retry: none.
- Memory keys: none added or used.
- Local writes: only the existing owner-private A4a/A4b status caches.
- Risk: `read_only_network`; remote mutation and remediation authority remain
  false.

## Known limitations

- Severity counts describe the bounded returned alert set while the separate
  match count and truncation flag disclose broader query volume.
- A3 ClamAV receipts remain endpoint-local and are not summarized.
- Investigation, alert disposition, host action, and remediation remain in the
  Wazuh console or future separately reviewed workflows.

## Human checklist

- [x] A4b authenticated Dashboard presentation approved by the Operator.
- [x] Explicit security questions use one deterministic read-only invocation.
- [x] Ordinary security discussion does not invoke the skill.
- [x] Raw event material is absent from the response and retained evidence.
- [x] Partial and unavailable states do not become health claims.
- [x] Voice Presence uses the same Chat route.
- [x] No acknowledgement, suppression, quarantine, scan, or remediation
  authority exists.
