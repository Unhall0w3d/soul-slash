# Maintenance source curation — 2026-09-23

Status: isolated candidate for human merge review. No timer, desktop handler,
maintenance authority, update, or reboot was installed or run during curation.

The candidate groups the fifteen-minute read-only fleet status timer, platform
adapter registry for Omarchy and other Linux families, fixed desktop terminal
handoff through the installed `/usr/bin/xdg-terminal-exec`, and the previously
Operator-approved seven-character managed-switch SNMP community boundary. The
registry reports adapter identities but grants no mutation authority. The
switch credential is read from standard input by its installer and remains
outside this source branch.

The guided maintenance document now describes the 15-minute collection
cadence consistently. The old `ANNEX_FLEET_STATUS_15MIN_BRIEF.md` filename was corrected to
`SOUL_FLEET_STATUS_15MIN_BRIEF.md`; its subject and systemd unit are Soul
maintenance. The original host-specific reviews and private configuration
remain in the owner checkout and are not promoted by this branch. Existing
review records identify the platform registry as candidate-complete with its
human outcome pending. Previously accepted device-control and switch recovery
evidence is historical, not fresh host qualification from this pass.

Focused deterministic checks: platform adapters A12, fleet status B1, device
control C1, desktop handoff A2B, foreground execution A2, and managed-switch
SNMP A1. The systemd calendar parser and `git diff --check` were also run.
These checks verify source contracts and fixtures; they do not prove a live
terminal launch or timer deployment. Human merge readiness and any exact live
installation remain at the repository review and deployment gates.
