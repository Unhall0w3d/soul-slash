# Generic Debian APT Maintenance A1 Brief

## Approved scope

Enroll an owner-selected Debian endpoint as a fully managed SSH fleet member without granting broad remote root access.

The endpoint uses an existing, non-root, key-only SSH identity. A root-owned helper accepts exactly `self-check`, `apt-upgrade`, or `reboot`; digest-bound sudoers grants that account passwordless authority only for those exact vectors. Owner-local aliases and addresses remain outside Git.

## Boundaries

- Operations are foreground, one-device, bounded transactions.
- Maintenance and reboot remain separate Dashboard actions with exact preview evidence.
- No arbitrary arguments, shell forwarding, password storage, root login, scheduler, listener, or background worker is introduced.
- An endpoint becomes manageable only when its private enrollment, explicit owner-local alias allowlist, and helper self-check all agree.
- SSH TCP 22 is an approved management-plane exception to an application surface otherwise limited to HTTPS TCP 443.

## Lifecycle

The existing device control lifecycle remains `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`.
