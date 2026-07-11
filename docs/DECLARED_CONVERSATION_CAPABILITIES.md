# Declared Conversation Capabilities

Conversational Soul distinguishes three different things:

1. a deterministic capability that is available now;
2. a capability that is conditionally available when its bounded source is readable;
3. a capability that is explicitly unavailable until a separate collector or workflow is declared.

This distinction prevents the model from turning a nearby fact into an unsupported operational claim.

## Runtime contract

`ConversationCapabilityRegistry` owns capability identity, conversational matching, status, risk class, tool association, scope, and limitations.

The conversation orchestrator consults the registry after persisted-evidence follow-up routing and before general intent or model routing.

The ordering matters:

```text
recent evidence follow-up
-> declared capability catalog, information, or gap
-> registered deterministic tool
-> model-backed conversation
-> deterministic fallback
```

A question about SMART health immediately after a host assessment can still be answered from the assessment's explicit `not_collected` evidence. Without recent evidence, the same request resolves to the declared `host.smart_health` boundary.

## Resolution kinds

- `catalog`: list declared capabilities and their statuses;
- `capability_info`: explain an available or conditional capability without executing it;
- `capability_gap`: explain a specifically unavailable capability;
- `available_action`: allow the ordinary tool catalog to decide whether to execute the registered capability;
- `unmatched`: continue normal orchestration.

## Initial host capability set

Available:

- `host.system_status`

Conditional:

- `host.linux_mdraid`

Explicitly unavailable:

- `host.smart_health`
- `host.storage_temperature`
- `host.hardware_raid`
- `host.zfs_pool_health`
- `host.firewall_policy`
- `host.authentication_logs`
- `host.scheduled_jobs`
- `host.package_updates`
- `host.external_network_reachability`
- `host.application_process_health`

The registry is an inspectable conversation boundary, not an execution adapter. It does not run commands, call providers, mutate state, or manufacture evidence.

## Extension rule

A future capability should declare:

- a stable capability ID;
- a human-readable label;
- domain and status;
- risk class;
- tool ID when executable;
- bounded scope;
- a truthful summary;
- explicit limitations;
- conversational matching patterns.

Moving a capability from `unavailable` to `conditional` or `available` requires a separately tested deterministic collector or workflow. Changing only the registry status is not sufficient.
