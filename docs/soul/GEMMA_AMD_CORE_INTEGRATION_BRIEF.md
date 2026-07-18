# Gemma AMD Core Integration Brief

```text
date: 2026-07-18
human_authorization: approved in the active development conversation
implementation_authorized: yes
persistent_unit_candidate_authorized: yes
automatic_cutover_authorized: no
default_core_change_authorized: no
risk: Class 3 — manually controlled local runtime mutation
```

## Objective

Integrate the reviewed `gemma4:12b-it-q4_K_M` Ollama/Vulkan candidate as a
third, manually selected Daily Core chat profile. Keep the current AMD
Ministral profile and NVIDIA Qwen profile intact as rollback paths. Accurately
report runtime type, declared and observed model identity, residency,
accelerator, endpoint health, and Core role in Model Runtime and System Status.

## Authorized vertical slice

- Extend the ignored project-local runtime profile format to distinguish
  llama.cpp OpenAI endpoints from Ollama OpenAI endpoints.
- Preserve compatibility with the existing v1/v2 profile documents.
- Add runtime-specific bounded health and idle observations for Ollama without
  weakening active-lease checks or exact preview/digest confirmation.
- Select Ollama's no-reasoning request dialect from the reviewed selected
  profile; do not rely on a machine-specific hard-coded environment value.
- Add an installable, static, disabled, inactive systemd user-unit candidate
  for the installed Ollama binary. Installation itself requires the exact
  deployment confirmation and must not start, enable, or select the unit.
- Add the reviewed Gemma profile to the private host inventory only after the
  unit and model alias are present and identity checks pass.
- Update Model Runtime and System Status to render Daily Core, Chat Engine,
  runtime, model, accelerator, residency, and health accurately.
- Calibrate the shared Soul persona for Gemma without introducing a second
  personality or weakening operational truth boundaries.
- Run deterministic tests and representative local acceptance checks.

## Hard boundaries

- No automatic failover, startup selection change, default-Core change, LAN
  listener, CPU offload, parallel AMD model residency, or unattended polling.
- No active request may be interrupted. Runtime switching remains blocked
  unless Soul's lease store is empty and the active runtime's bounded health
  observation is available.
- Model output cannot approve a switch, deployment, persistence, or identity
  mutation.
- The Ollama unit binds only `127.0.0.1`, is not enabled, has no `[Install]`
  section, and may be started or stopped only through the existing authenticated
  exact-confirmation runtime gate or direct human administration.
- Gemma does not become the default Daily Core in this slice. The current
  selected profile is restored after live acceptance.

## Lifecycle

```text
validate_environment
-> implement_candidate
-> deterministic_verification
-> optional_exact_confirmed_inactive_unit_install
-> representative_live_acceptance
-> restore_current_profile
-> blocked_for_human_review
```

Every foreground operation terminates as `complete`, `failed`,
`awaiting_input`, `canceled`, or `blocked_for_human_review`.

## Required evidence

- v1/v2 compatibility and strict v3 rejection cases;
- llama.cpp and Ollama runtime observation fixtures;
- active lease and unavailable observation switch blockers;
- explicit Ollama dialect selection from the selected profile;
- dashboard/System Status Core and engine identity rendering;
- inactive, disabled, loopback-only unit deployment behavior;
- Gemma conversation/persona and representative Music Studio structured output;
- cleanup proving no temporary listener or candidate model remains resident;
- a human review artifact following `docs/soul/HUMAN_REVIEW_GATE.md`.
