# Memory Projection Installer A20 Review

Status: deployed candidate; deterministic and live acceptance passed. Human
approval to merge remains separate.

## Implemented

- A digest-bound, four-phase installer for the A19 projection architecture.
- Owner-private preflight, certificates, credentials, SSH identity, and pinned
  release inputs; none are committed or returned in public receipts.
- An unprivileged, non-nesting Debian LXC with Qdrant, Redis/FalkorDB, SSH, and
  nftables services.
- TLS-only database access and an exact Operator-workstation ingress rule.
- A bounded compatibility repair operation for reviewed service configuration
  drift without guest recreation or canonical-memory mutation.

## Files changed

- `lib/soul_core/memory_projection_remote_installer.rb`
- `scripts/soul-memory-projection-bootstrap`
- `scripts/soul-memory-projection-deployment`
- `scripts/soul-memory-projection-preflight`
- `scripts/verify-memory-projection-installer-a20.rb`
- this review

## Verification

- `ruby scripts/verify-memory-projection-installer-a20.rb`
- `git diff --check`
- Live LXC configuration review: 2 vCPU, 2,048 MiB RAM, 512 MiB swap,
  24 GiB root, autostart, unprivileged, and `nesting=0`.
- Qdrant without its API key returned HTTP 401; the authenticated TLS request
  returned HTTP 200.
- Redis returned `PONG` over authenticated TLS and rejected plaintext Redis.
- Redis reported FalkorDB module `graph` version 42004 loaded from the pinned
  module path.
- nftables used a default-drop input policy and admitted ports 22, 6333, and
  6379 only from the exact Operator workstation address. A connection from the
  Foundry host was rejected while Atelier reached the intended ports.
- Qdrant, Redis, SSH, and nftables were active and enabled after repair.

## Live compatibility repairs

- Debian Redis uses `PrivateUsers=true`, which cannot start inside this
  unprivileged non-nesting LXC. The approved Redis-only drop-in sets
  `PrivateUsers=false`; no other Redis hardening setting was relaxed.
- The shared TLS private key is readable through a dedicated service group,
  while the service-specific credentials remain separately owned.
- Qdrant's configuration directory and service config path were made mutually
  consistent.
- FalkorDB requires Debian `libgomp1`; the dependency is installed explicitly.
- The FalkorDB directory is `root:redis` mode 0750 so Redis can load the module
  without granting traversal to unrelated users.
- nftables is explicitly restarted after writing its policy. Merely enabling an
  already-running unit left Debian's initial accept-all ruleset active.

## Known weaknesses

- Redis reports the usual host `vm.overcommit_memory` advisory. Changing a
  Proxmox host kernel setting is outside this deployment and was not performed.
- Postfix is installed and listens only on guest loopback TCP 25. It is not
  reachable through the default-drop firewall and is not part of the projection
  interface; retirement can be considered separately.
- Projection data remains disposable and rebuildable. Canonical memory does not
  depend on either service.

## Memory and lifecycle

- No memory keys were added or changed by the installer.
- Lifecycle states exercised: `blocked_for_human_review`, `failed`, and
  `complete`.
- Risk classification: privileged remote installation with persistent services;
  independently verified under the adopted A19 brief and exact A20 plan gate.

## Human review checklist

- [ ] Approve the A20 public installer and review artifact for merge.
- [x] Approve the narrow Redis LXC compatibility exception.
- [x] Confirm Qdrant and Redis/FalkorDB authentication behavior.
- [x] Confirm the exact-client firewall boundary.
- [x] Confirm that owner-private material remains outside Git.
