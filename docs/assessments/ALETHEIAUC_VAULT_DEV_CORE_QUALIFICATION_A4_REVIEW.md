# AletheiaUC Vault to Dev Core Qualification A4 Review

Status: accepted qualification evidence

## Outcome

The bounded local qualification passed. Three independently scoped requests used
three reviewed AletheiaUC vault notes apiece and produced useful, structured
candidate analysis through the GPT-OSS 20B Dev Worker. The receipts confirm that
Dev Core was already selected and remained selected for every execution.

This result justifies designing a reviewed automatic context-assembly slice. It
does not justify applying Dev Worker output directly, treating retrieved notes as
authority, or skipping primary review of proposed paths and validation.

## Scope and authority

- Operation: foreground, read-only Dev Worker analysis or critique
- Provider: `local.dev`
- Model: `gpt-oss:20b`, MXFP4
- Context limit: 16,384 tokens
- Mutation: none
- Repository, shell, network, Git, test, approval, and merge authority: none
- Context source: three explicitly selected, local AletheiaUC vault notes per
  request
- Output: the existing bounded structured candidate schema

No customer evidence, credentials, private assessment output, or cloud provider
was used.

## Core-state correction

The first sandboxed execution reported that an eligible Core was not selected.
That diagnosis was false. The selected-Core ledger already identified Dev Core,
but the sandbox could not connect to the host user-systemd runtime and therefore
observed no active model service.

Executing through the host runtime preserved the normal digest and confirmation
gates and produced receipts with:

- `starting_core_id: dev`
- `selected_dev_core: true`
- no chat-Core transition
- no restoration step

This is a usability defect in the failure message, not a Dev Core selection or
runtime failure. A later bounded correction should distinguish “host runtime is
not visible from this execution context” from “no eligible Core is selected.”

## Qualification cases

### Collector-change planning

- Request: `aletheia_vault_a4_collector`
- Context SHA-256:
  `fc1301541a0a8844ec1cc5d57b7fa75e41951ac0dbdfd34e2ae4f2cf96e002cc`
- Request digest:
  `c17ef6d19f7e6a53a78a991c9d1ff18116a7e7e01fffb0716677b1c86df41807`
- Runtime: 7.842 seconds in the retained result

The candidate correctly selected serviceability collection, fact models,
coverage, and deterministic collector/report tests as the primary surfaces. It
also preserved bounded collection, provenance, privacy, and the distinction
between inventory and runtime health.

The result remained a candidate because it generalized some validation from
nearby examples and could not know the exact new fact fields or whether rule
logic was required. That is appropriate uncertainty. The suggested paths must
still be checked against the current repository before implementation.

### Evidence-to-report truth critique

- Request: `aletheia_vault_a4_report_truth`
- Context SHA-256:
  `c518f57de66575f3111156f80167c96f08c5f39fc90bbabace986631356ec467`
- Request digest:
  `827da5e7078e128cdce5dd13ae539d8841043e3db43471a60d1138cc9b1db622`
- Runtime: 9.94 seconds

The candidate correctly rejected the claim that successful CER authentication
proves emergency calling or PSAP delivery health. It accurately limited the fact
to reviewed endpoint reachability and accepted authentication, identified the
missing ERL, discovery, routing, callback, and service-health evidence, and
recommended explicit unavailable or not-collected treatment.

This was the strongest result. It stayed within the supplied truth contract and
identified the exact unsupported inference without manufacturing evidence.

### Packaging-validation planning

- Request: `aletheia_vault_a4_packaging`
- Context SHA-256:
  `cdaa1bf5bc753cd31d2b88f0449e3fca6ff3948e29354d68d477d6f64ee81619`
- Request digest:
  `3a1f940442d2048ba32fdce974295f1241543024f5b23c01beac06f2bda1f7a9`
- Runtime: 14.192 seconds

The candidate correctly separated routine Ruff, mypy, unittest, and build checks
from proportionate wheel smoke and Playwright/Chromium validation. It also
preserved the rule that passing checks do not authorize merge or release.

The candidate over-specified several likely test filenames and asserted details
such as a Python-version matrix and strict-mode configuration that were not all
present in its supplied notes. These are plausible guesses, not grounded facts.
Automatic context assembly must label retrieved context as untrusted evidence and
require current-repository verification before paths or commands become a plan.

## Acceptance evaluation

| Criterion | Result |
| --- | --- |
| Local-only execution | Pass |
| Dev Core selected and retained | Pass |
| Exact request/context digesting | Pass |
| Bounded foreground lifecycle | Pass |
| Structured output | Pass |
| No mutation or execution authority | Pass |
| Curated note set appropriate | Pass for all three cases |
| Useful project-specific reasoning | Pass |
| Honest unknown handling | Pass, with some plausible overreach |
| Safe to apply without primary review | No |

## Subsequent implementation outcome

A5 subsequently implemented automatic, local-only context assembly for bounded
Dev Worker requests through PR #205. Its accepted contract:

1. Retrieve by project and task intent before invoking the worker.
2. Prefer router/index notes, then select at most three full notes within a
   48-KiB aggregate context ceiling.
3. Include canonical vault-relative paths and content SHA-256 values in the
   request receipt.
4. Treat note contents as untrusted evidence, never as instructions or
   authorization.
5. Reject secrets, private evidence paths, customer artifacts, symlinks, and
   content outside the approved vault root.
6. Keep the Dev Worker tool-less and retain its existing foreground timeout,
   output schema, confirmation, and digest gates.
7. Require current-repository inspection before accepting recommended paths,
   commands, tests, or implementation details.
8. Fall back to an explicit insufficient-context result rather than broadening
   retrieval or silently researching online.

Online research remains a separate, explicitly scoped primary-agent action when
local notes conflict, are stale, or are insufficient.

A6 then routed the Codex-facing Soul Dev Worker skill through the reviewed A5
path for qualified AletheiaUC work while retaining manual evidence assembly as
a deliberate fallback. That procedural integration merged through PR #206.

## Human review checklist

- [x] Confirm all executions used Dev Core.
- [x] Confirm no cloud provider or private customer evidence was used.
- [x] Review all three candidate outputs for grounding and useful uncertainty.
- [x] Identify unsupported path, test, or environment assumptions.
- [x] Preserve Dev Worker non-authority and foreground lifecycle.
- [x] Approve and implement the A5 automatic context-assembly brief.
- [x] Approve and merge the A6 Codex-facing skill integration.
