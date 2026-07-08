# Workflow Handler Contract Checklist

## Registry

- [ ] Workflow intent is listed in `lib/soul_core/workflow_registry.rb`.
- [ ] Handler class is registered in `lib/soul_core/workflow_handler_registry.rb`.
- [ ] Handler appears in `ruby bin/soul workflows --json` if intended for public workflow listing.

## Handler class

- [ ] Handler lives under `lib/soul_core/workflows/`.
- [ ] Handler inherits from `SoulCore::Workflows::BaseHandler`.
- [ ] Handler implements `run(parameters:, original_text:)`.
- [ ] Handler implements `match_intent(text, result_class:)` if natural-language routing is needed.
- [ ] Handler implements `responds_to_status?(status)` if it owns follow-up response states.
- [ ] Handler implements `respond(state:, text:)` if it owns follow-up response states.

## State

- [ ] State includes `workflow`.
- [ ] State includes `status`.
- [ ] State includes `generated_at`.
- [ ] State includes `updated_at`.
- [ ] State includes `original_text`.
- [ ] State includes `parameters`.
- [ ] State includes `skill_runs`.
- [ ] State includes `next_expected`.
- [ ] State includes `verification`.
- [ ] State includes `workflow_path`.

## Safety

- [ ] Initial `run` does not perform a write action without confirmation.
- [ ] Confirmation states are clear and specific.
- [ ] Cancellation path is supported for waiting states.
- [ ] `verification` records deterministic evidence.
- [ ] User-facing message does not claim more than evidence proves.
- [ ] Write boundaries are documented.

## Metadata

- [ ] `handler_execution` is written during run.
- [ ] `registry_execution` is present after registry execution.
- [ ] `handler_response` is written during response handling.
- [ ] `verification.complete` reflects actual completion.

## Tests

- [ ] Handler has a focused verifier under `scripts/`.
- [ ] `ruby scripts/verify-workflow-handler-contract.rb` passes.
- [ ] Manual `ruby bin/soul intent "..."` check passes.
- [ ] Manual `ruby bin/soul do "..."` check passes.
- [ ] Manual `ruby bin/soul respond "cancel"` check passes.
