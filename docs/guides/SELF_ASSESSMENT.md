# Self Assessment

Self Assessment is Soul's read-only view of the machine and runtime it inhabits. It gathers evidence, explains gaps, and can prepare advisory proposals or terminal handoffs. It is not an autonomous package manager or host administrator.

Open it from **Self Improvement → Self Assessment**.

## Intended flow

```text
inspect
→ assess evidence
→ identify a gap or maintenance need
→ prepare a bounded recommendation, proposal, or terminal handoff
→ human reviews and acts separately
→ verify the resulting state
```

## Assessment scopes

A lightweight environment snapshot loads once when the page opens. Deeper checks run only when selected:

- **Environment** — host and runtime identity visible to Soul.
- **Update checks** — package evidence, update candidates, orphan candidates, and reboot recommendation evidence where supported.
- **Model runtime** — configured local endpoints and bounded model/runtime inventory.
- **Capabilities** — available, partial, and missing Soul capabilities.
- **Storage** — point-in-time classification of protected data, durable outputs, logs, and narrowly defined cleanup candidates.

Results are snapshots, not continuous monitoring. Refresh or run the relevant scope again after the machine changes.

**Dev synthesis** is a separately invoked, review-only pass over the latest
successful evidence for the currently selected scope. Preview shows the exact
evidence timestamp and SHA-256. Confirming the pre-filled gate permits one
bounded local GPT-OSS review; normal Core restoration remains the Dev runtime's
responsibility.

The confirmed review runs through the Dashboard's persisted bounded-job lane.
Navigating away does not cancel it, and reopening or refreshing Self Assessment
reconnects to the active job. A Dashboard-process restart fails an interrupted
job visibly and never retries it automatically; collect fresh evidence and
preview again before a deliberate retry.

The result is an owner-private, immutable review containing only a summary,
evidence-linked observations, explicit unknowns, and navigation hints. It does
not replace deterministic collection, classify safety, alter findings or
severity, generate a plan, authorize host mutation, or invoke the suggested
surface. Re-run the assessment when evidence changes, then preview again. A
Dashboard restart intentionally clears eligible evidence, so the source scope
must be collected again before another synthesis.

## Recommendations and proposals

Assessment findings may produce recommendations. **Generate proposal packets** previews the exact current capability-derived set, binds it to a digest, and writes advisory packets only after confirmation.

Those packets do not implement a skill, alter the host, download a model, or promote anything. Skill-shaped proposals continue through [Skill Studio](SKILL_STUDIO.md).

## Arch host handoff

On the supported Arch/CachyOS host path, Self Assessment can prepare a fresh, digest-bound full-upgrade handoff. Soul never runs `pacman`, invokes `sudo`, or collects a password. The Operator executes the terminal command and may return afterward to verify postconditions.

## Guided maintenance evidence

Self Assessment supplies the read-only package and host evidence consumed by
the current **Administration → Guided Maintenance** surface. The read-only A1
path previews and rehearses package maintenance and a privacy-filtered
restoration map. Package maintenance and reboot are separate reviewed
transactions:

```text
read-only evidence
→ separately authorized A2 package transaction:
  yay full upgrade
→ Flatpak update
→ stop before reboot
→ separately authorized A3 reboot-only transaction:
  empty package-command vectors
→ privacy-filtered Hyprland window snapshot
→ one exact reboot request
→ one-shot workspace restoration after SDDM auto-login
```

Choose normal `yay -Syu` behavior or explicitly request the forced
package-database refresh used on the primary host (`yay -Syyu`). The preview
shows exact inert argument arrays, detected Flatpak installation scopes, and
which open application identities are safely mapped by the restore registry.
It also checks allowlisted process names for tray-only applications that have
no compositor window. Those use `launch_if_absent`, so a later restorer must
first honor normal desktop autostart and avoid duplicates.
Unknown applications, games, transient dialogs, excess duplicate windows, and
missing executables remain visible as unsupported.

The snapshot deliberately excludes window titles, browser URLs, raw process
commands, terminal contents, environment values, and credentials. The
process view stores only matched allowlisted names—not raw arguments or an
inventory of unrelated background services. The
rehearsal simulates the declared lifecycle and reports blockers. It requests no
password, writes no operational state, launches nothing, and cannot reboot.

See [Guided Maintenance](GUIDED_MAINTENANCE.md) for its controls and boundaries.
Actual authentication and updates require the separately reviewed A2 gate.
Reboot and the one-shot post-login restorer require a distinct A3 gate, whose
empty package vectors prevent maintenance replay.

## Storage and retention

The Storage view classifies data before cleanup. Production models, private
memory, chats, projects, accepted candidates and pilots, finished exports,
credentials, backup evidence, and the Knowledge Vault are protected.

Storage Cleanup A3 implements three deliberately narrow categories as a
candidate behind an exact preview, digest, and destructive review gate. Its
implementation and deterministic evidence do not grant production approval:

- known Soul review residue in the system temporary directory older than
  24 hours;
- regular project log files older than 30 days;
- failed `.candidate_*.partial` Music quarantine directories older than
  24 hours when no Music lease is active.

Select a category, preview every exact entry, then use the separate destructive
button if the scope is correct. Execution repeats discovery and requires the
same digest, ownership, age, path, type, inode, and symlink-free tree. Changed
or oversized scopes fail closed. Cleanup is foreground-only and never runs on
a timer, at startup, or as part of an assessment refresh.

## What Self Assessment cannot do

It cannot:

- install, update, downgrade, or remove packages;
- reboot, schedule a reboot, or change services;
- download or delete models;
- delete protected project data or memory;
- implement or promote skills;
- apply a recommendation merely because an assessment found it useful.
- let a Dev synthesis review invoke its own navigation hint or follow-on work.

## Choosing the next surface

- A missing bounded capability belongs in [Skill Studio](SKILL_STUDIO.md).
- A shared architectural limitation belongs in [Self Augmentation](SELF_AUGMENTATION.md).
- A host mutation remains a separately reviewed executor or a human-run terminal operation.

## Related engineering references

- [`docs/BOUNDED_HOST_SYSTEM_STATUS.md`](../BOUNDED_HOST_SYSTEM_STATUS.md)
- [`docs/soul/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_ARCHITECTURE.md`](../soul/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_ARCHITECTURE.md)
- [`docs/soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md`](../soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md)
- [`docs/assessments/STORAGE_AND_RETENTION_A1_REVIEW.md`](../assessments/STORAGE_AND_RETENTION_A1_REVIEW.md)
