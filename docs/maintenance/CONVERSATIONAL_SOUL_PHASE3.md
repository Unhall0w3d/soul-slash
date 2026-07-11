# Conversational Soul Phase 3

Milestone:

```text
Conversational Soul
```

Phase:

```text
3
```

## Purpose

Add the first provider-backed multi-turn conversation runtime while preserving deterministic skill and approval routes.

## Added

```text
lib/soul_core/conversation_context_builder.rb
lib/soul_core/conversation_state_store.rb
lib/soul_core/conversation_provider_client.rb
lib/soul_core/conversation_runtime.rb
lib/soul_core/multiturn_conversation_runtime_assessor.rb
docs/MULTITURN_CONVERSATION_RUNTIME.md
scripts/verify-multiturn-conversation-runtime-phase3.rb
```

## Updated

```text
lib/soul_core/chat_command.rb
lib/soul_core/app.rb
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/MILESTONES.md
CHANGELOG.md
```

## New assessment

```zsh
ruby bin/soul assess multiturn-conversation-runtime
ruby bin/soul assess multiturn-conversation-runtime --json
```

## Behavioral change

Ordinary chat messages may now use a configured local conversation provider.

Known deterministic skills, approval commands, and Downloads actions continue to use the existing deterministic responder.

If no provider is configured or a provider fails, Soul preserves the chat session and reports the fallback honestly.

## Assessment isolation

The verifier uses an injected fake provider and temporary runtime directory. It does not require or contact an actual model server.
