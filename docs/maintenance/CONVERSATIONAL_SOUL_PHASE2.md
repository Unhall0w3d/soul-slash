# Conversational Soul Phase 2

Milestone:

```text
Conversational Soul
```

Phase:

```text
2
```

## Purpose

Establish the provider-neutral request, response, capability, registry, and health-check foundation needed by the future multi-turn conversation runtime.

## Added

```text
lib/soul_core/conversation_provider_contract.rb
lib/soul_core/conversation_provider_registry.rb
lib/soul_core/conversation_provider_probe.rb
lib/soul_core/conversation_provider_foundation_assessor.rb
docs/CONVERSATION_PROVIDER_CONTRACT.md
docs/CONVERSATION_PROVIDER_CONFIGURATION.md
scripts/verify-conversation-provider-foundation-phase2.rb
```

## Updated

```text
lib/soul_core/app.rb
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/MILESTONES.md
CHANGELOG.md
```

## New assessment

```zsh
ruby bin/soul assess conversation-provider-foundation
ruby bin/soul assess conversation-provider-foundation --json
```

## Behavioral change

No production chat route changes.

The assessment uses temporary local HTTP servers to verify available, unavailable, and timeout probe behavior without depending on an installed model runtime.

## Result

Soul now has a provider-neutral conversation contract suitable for local OpenAI-compatible and Ollama runtimes, plus a disabled cloud-compatible shape for later controlled use.
