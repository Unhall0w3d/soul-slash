# Maintenance AUR Review Gate A11 Brief

```text
date: 2026-08-02
human_authorization: approved in the active development conversation
implementation_authorized: yes
installation_authorized: no; exact root-owned helper replacement requires later review
live_execution_authorized: no; deterministic verification and human review first
risk: Class 5
```

## Objective

Restore the trust boundary between signed distribution repositories and
community-supplied AUR build instructions. Routine workstation maintenance may
remain zero-prompt for trusted pacman repositories and system Flatpak updates.
It must not download, build, or install an AUR update without a separate visible
human review.

## Required flow

```text
fresh read-only package evidence
→ routine Maintain: pacman repositories + Flatpak only
→ pending AUR set remains visible
→ Review pending AUR
→ fresh digest-bound package-set check
→ one visible interactive terminal
→ review clean-build choice, diffs, PKGBUILD/install scripts, sources/checksums
→ Operator accepts, declines, cancels, or closes
→ bounded redacted receipt
```

The AUR stage is never part of the root-owned passwordless helper. The helper
accepts only `repository-update`, `flatpak-system-update`, or `reboot` with one
opaque transaction ID. `repository-update` runs only target-free `pacman -Syu`
or the explicitly selected `pacman -Syyu` with `--noconfirm`.

## Interactive AUR boundary

The review terminal runs `yay --aur -Sua` with clean, diff, and edit menus
enabled. It explicitly unsets all configured predetermined answers. It disables
the sudo keepalive loop and receives no package target, shell string, generated
answer, or automatic retry. A single native `sudo -v` may authenticate the
bounded terminal; `sudo -k` closes the ticket on every terminal outcome.

This A11 candidate qualifies `yay` only. Read-only discovery may identify
`paru`, but attempting to start mutation through an unqualified helper fails
closed until a separate exact interactive adapter is reviewed.

The reservation is owner-private, expires after ten minutes, is bound to the
fresh read-only AUR package list by SHA-256, and is single-use. A changed package
set fails before `yay` starts and requires fresh evidence and review.

## Lifecycle

The foreground AUR operation terminates as `complete`, `failed`, or `canceled`.
Reservation or integrity failures terminate as `blocked_for_human_review` or
`failed`. Closing the terminal does not create a background task.

## Explicit exclusions

- no unattended AUR build or installation;
- no model-generated package decision;
- no implicit approval from the routine Maintain button;
- no AUR code in a root-owned helper;
- no package target, alternate root, arbitrary executable, or shell;
- no automatic retry or continuation after the foreground terminal returns.
