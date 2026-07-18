# Core shared-profile transition repair brief

Status: owner-approved and live-verified (2026-07-18)

## Objective

Allow direct AMD-Free ↔ Music Core transitions when both operating intents use
the already-active NVIDIA Qwen chat profile. Remove the unnecessary Daily Core
bridge without introducing automatic switching or weakening activity gates.

## Contract

- Preview revalidates exactly one active profile, zero active work, no active
  lease, and a certain idle observation.
- The digest binds source Core, target Core, shared profile/service, profile
  states, leases, work count, and the fact that no service mutation is needed.
- Execution requires `ACTIVATE_MUSIC_CORE` or `ACTIVATE_AMD_FREE_CORE` and the
  unchanged digest.
- Execution atomically changes only `core_selection.json`; it does not invoke
  systemd, start ACE-Step, stop Qwen, touch Gemma, or reboot.
- The final observation, lease/work recheck, digest validation, and selection
  write occur under the existing bounded model-runtime control lock.
- Daily ↔ either NVIDIA-backed Core continues using the existing stop/start
  runtime controller and all its gates.
- No background work, polling, persistence mechanism, or model-driven authority
  is added.

## Lifecycle

The bounded operation terminates as `complete`, `awaiting_input`,
`blocked_for_human_review`, or the existing runtime failure envelope. Passing
tests does not approve merge or a live Core transition.
