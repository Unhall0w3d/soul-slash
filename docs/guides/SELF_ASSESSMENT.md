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

## Recommendations and proposals

Assessment findings may produce recommendations. **Generate proposal packets** previews the exact current capability-derived set, binds it to a digest, and writes advisory packets only after confirmation.

Those packets do not implement a skill, alter the host, download a model, or promote anything. Skill-shaped proposals continue through [Skill Studio](SKILL_STUDIO.md).

## Arch host handoff

On the supported Arch/CachyOS host path, Self Assessment can prepare a fresh, digest-bound full-upgrade handoff. Soul never runs `pacman`, invokes `sudo`, or collects a password. The Operator executes the terminal command and may return afterward to verify postconditions.

## Guided maintenance rehearsal

The approved A1 maintenance slice adds a separate read-only preview and
rehearsal for a future end-to-end transaction:

```text
yay full upgrade
→ Flatpak update
→ privacy-filtered Hyprland window snapshot
→ conditional reboot
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

Actual authentication and updates require a separately reviewed A2 gate.
Conditional reboot and the one-shot post-login restorer require A3.

## Storage and retention

The Storage view classifies data before any cleanup system is considered. Production models, private memory, projects, accepted pilots, and finished exports are protected categories. Current cleanup manifests are preview-only; this surface has no general deletion executor.

## What Self Assessment cannot do

It cannot:

- install, update, downgrade, or remove packages;
- reboot, schedule a reboot, or change services;
- download or delete models;
- delete project data or memory;
- implement or promote skills;
- apply a recommendation merely because an assessment found it useful.

## Choosing the next surface

- A missing bounded capability belongs in [Skill Studio](SKILL_STUDIO.md).
- A shared architectural limitation belongs in [Self Augmentation](SELF_AUGMENTATION.md).
- A host mutation remains a separately reviewed executor or a human-run terminal operation.

## Related engineering references

- [`docs/BOUNDED_HOST_SYSTEM_STATUS.md`](../BOUNDED_HOST_SYSTEM_STATUS.md)
- [`docs/soul/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_ARCHITECTURE.md`](../soul/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_ARCHITECTURE.md)
- [`docs/soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md`](../soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md)
- [`docs/assessments/STORAGE_AND_RETENTION_A1_REVIEW.md`](../assessments/STORAGE_AND_RETENTION_A1_REVIEW.md)
