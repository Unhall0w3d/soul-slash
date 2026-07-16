# Self Augmentation and Host Improvement A1–A3 Review

Status: candidate-complete; human review required
Date: 2026-07-16

## What was implemented

- A1 replaces `pacman -Qu` with `checkupdates --nocolor` and preserves fresh
  update, no-update, unavailable, and failed outcomes as distinct evidence.
- A1 limits safe-update support claims to adapters with a declared read-only
  check and adds JSON schemas for host plans and augmentation proposals.
- A2 prepares one Arch full-upgrade plan and an exact terminal handoff packet.
  Soul writes the reviewed command but never executes it or requests a password.
- A2 verifies current update state after a human terminal action and persists a
  bounded receipt containing fixed-path pacman-log evidence.
- A3 inspects bounded Git-tracked regular files, excludes private/generated
  roots, and creates a census-bound architectural proposal only after exact
  confirmation.
- The authenticated application API exposes the new operations. Self Assessment
  contains Host Improvement, and Self Augmentation is a fourth product tab.
  Experiment and Review are visibly locked.

## Files changed

- `lib/soul_core/package_manager_assessor.rb`
- `lib/soul_core/host_improvement_plan_service.rb`
- `lib/soul_core/self_augmentation_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `docs/soul/SELF_AUGMENTATION_HOST_IMPROVEMENT_A1_A3_BRIEF.md`
- `docs/soul/schemas/host_improvement_plan.schema.json`
- `docs/soul/schemas/self_augmentation_proposal.schema.json`
- `scripts/verify-self-augmentation-host-improvement-a1-a3.rb`
- Historical dashboard/API verifiers, milestone, changelog, ignore rules, and
  generated-root sentinels were updated to recognize the approved fourth tab.

## Commands run

```text
ruby -c lib/soul_core/package_manager_assessor.rb
ruby -c lib/soul_core/host_improvement_plan_service.rb
ruby -c lib/soul_core/self_augmentation_service.rb
ruby -c lib/soul_core/application_facade.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-environment-assessment-phase11.rb
ruby scripts/verify-self-augmentation-host-improvement-a1-a3.rb
ruby scripts/verify-phase12d3-self-improvement-dashboard.rb
ruby scripts/verify-phase12e-unified-review-center.rb
ruby -Ilib -rjson -e '<run live PackageManagerAssessor update projection>'
ruby -Ilib -rjson -e '<run live SelfAugmentationService census projection>'
git diff --check
```

## Deterministic test results

All commands above passed. The A1–A3 verifier covers:

- `checkupdates` success, exit 2, and failure distinctions;
- absence of `pacman -Qu`;
- write-free previews, wrong-confirmation rejection, and exact digest gates;
- terminal handoff packet content and proof that Soul ran no host command;
- bounded typed postcondition receipt persistence;
- tracked-only census, `.env` exclusion, and verifier inventory;
- proposal creation without implementation;
- application-facade allowlisting and projection;
- four-tab dashboard structure, locked deferred stages, and no polling.

The live tracked-code census completed at `b344544524fe` across 747 tracked
paths, inspected 733 text files / 3,520,626 bytes, excluded 8 paths, found no
tracked symlinks, and did not reach its content limit. The live sandboxed
`checkupdates` call returned exit 1 (`Cannot fetch updates`); the projection
correctly reported `failed`, `fresh: false`, and zero candidates without
claiming that the system had no updates. This validates failure honesty, not
current host update state.

## Local LLM eval results

Not run. These slices are deterministic assessment, packet, and interface
contracts. A local model cannot approve their safety, filesystem boundaries,
confirmation gates, host commands, or merge readiness.

## Known weaknesses

- Only the Arch full-system-upgrade adapter exists. AUR, Flatpak, Snap, Nix,
  package removal, orphan cleanup, services, runtimes, and model mutation remain
  assessment-only or unavailable.
- The postcondition proves current repository update state and imports bounded
  pacman-log lines; it cannot prove that every unrelated side effect of a manual
  package transaction was desirable.
- The census is structural and hash-based. It does not semantically understand
  architecture, and the operator must justify why a request is not a skill.
- Files over 256 KiB and binary files are counted but not inspected. Text reading
  stops at the 4 MiB aggregate boundary.
- Experiment preparation, compatibility evaluation, rollback execution,
  worktrees, Codex handoff, candidate review, and integration are deferred to
  A4–A5 under a new brief.

## Memory keys added or used

None. Plans, receipts, and augmentation proposals are review artifacts, not
durable personal context, and no skill-private memory store was introduced.

## Task lifecycle states touched

- `complete` — assessments, census, inventory, preview, and receipt verification.
- `awaiting_input` — missing input, invalid text, unknown plan, or no Arch updates.
- `failed` — bounded dependency or census failure.
- `blocked_for_human_review` — host handoff and augmentation proposal packet
  creation, including wrong/stale confirmation paths.

Every operation terminates in the foreground. There is no background process,
watcher, scheduler, or polling loop.

## Risk classification

- A1 assessment and census: Class 1 read-only local inspection.
- Packet and receipt writes: Class 2 bounded local state writes.
- Displayed Arch command: Class 5 if the human independently runs it. Soul has no
  Class 5 executor in this candidate.
- Future augmentation implementation/integration: Class 4 or higher and not
  authorized here.

## Human review checklist

- [ ] Confirm `checkupdates` status and freshness language is honest.
- [ ] Confirm the dashboard never executes or submits `sudo pacman -Syu`.
- [ ] Inspect a generated terminal handoff and verification receipt.
- [ ] Confirm the census excludes `.env`, runtime, memory, model, secret, and
      generated packet roots.
- [ ] Confirm proposal creation changes only the ignored augmentation root.
- [ ] Confirm Experiment and Review remain locked and no Codex/worktree action is
      available.
- [ ] Visually inspect both tabs at desktop and phone widths.
- [ ] Approve, request changes, or reject before merge/release.
