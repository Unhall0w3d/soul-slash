# Memory Projection Deployment A19 Brief

Status: Candidate deployment architecture and exact-plan boundary. Persistent
installation remains unauthorized until this brief and a fresh plan digest are
explicitly adopted by the Operator.

## Decision

Use one dedicated unprivileged Debian 13 LXC on the secondary Proxmox host. Run
Qdrant and FalkorDB natively; do not enable nested Docker or Podman.

This is feasible because Debian 13 provides Redis 8, FalkorDB's current module
requires Redis 8 or newer, Qdrant publishes a signed-release checksum-addressed
Debian package, and FalkorDB publishes a checksum-addressed Linux module. The
native layout removes an unnecessary nested-runtime failure and security layer.

## Reviewed baseline

- 2 virtual CPUs;
- 2,048 MiB RAM and 512 MiB swap;
- 24 GiB local block-backed root storage;
- unprivileged Debian 13 LXC with autostart;
- no nested container runtime;
- owner-private guest identity, address, SSH key, CA, service certificates, and
  database credentials.

The live host inventory on 2026-08-24 showed 16 GiB physical RAM and about 7.3
GiB available while the existing 3 GiB observability LXC and 6 GiB security VM
were running. The A19 allocation is intentionally small because the current
projection ceiling is only 5,000 records and 1,024 dimensions. Capacity must be
rechecked immediately before creation; stale capacity evidence blocks install.

## Pinned components and provenance

- Qdrant 1.19.0 official amd64 Debian release asset, SHA-256 pinned in the
  public manifest. Qdrant uses Apache-2.0.
- Redis Server 8.0 or newer from the signed Debian 13 repository. The installed
  package version and origin become retained deployment evidence.
- FalkorDB 4.20.4 official `falkordb-x64.so` release asset, SHA-256 pinned in the
  public manifest. FalkorDB uses SSPL-1.0; private self-hosted use is accepted,
  but its license is recorded rather than silently treated as permissive.

The deployment must download artifacts inside a bounded staging directory,
verify every fixed digest before installation, and remove staging residue.
`latest` tags, unsigned alternate repositories, source builds, and unreviewed
binary substitution are prohibited.

## Network and authentication

- The guest has no public ingress.
- SSH uses the dedicated key-only non-root management identity plus narrowly
  reviewed elevation for installation and service lifecycle.
- Qdrant exposes only TLS REST port 6333 to the exact Operator workstation
  address. Its gRPC and cluster ports are blocked.
- FalkorDB disables its plaintext Redis port and exposes only TLS port 6379 to
  the exact Operator workstation address.
- Both databases require independent high-entropy credentials.
- Certificates are signed by the owner-private local CA. Private keys,
  credentials, addresses, hostnames, and SSH identities remain outside Git.
- No database browser UI is installed or exposed.

## Service and storage behavior

Qdrant and Redis/FalkorDB may run as hardened systemd services inside the guest
after the exact deployment gate. They bind only the reviewed private interface,
use local POSIX block storage, restart on failure with bounded systemd policy,
and start with the guest. Qdrant and Redis resource ceilings must fit inside the
2 GiB guest rather than relying on host OOM behavior.

FalkorDB uses append-only persistence. Qdrant uses its native local storage.
These data are disposable projections and are not included in owner backups.
The deployment manifest, installed-version receipt, CA certificate, service
certificates, and credentials are owner-private backup inputs. Canonical memory
and the local approved-memory index remain protected by the existing backup
flow.

## Rebuild and reconciliation

One rebuild creates a new generation in both services, verifies schema, source
digests, dimensions, counts, point/node/edge membership, and sample local joins,
then atomically selects that exact generation. A partially written or divergent
generation is never queried. The previous verified generation remains available
for bounded rollback until the next successful reconciliation.

Projection drift can only cause a rebuild from canonical state. Qdrant or
FalkorDB output cannot create, approve, supersede, demote, tombstone, rewrite,
or delete canonical memory. Failure or unavailability visibly falls back to the
existing local authoritative retrieval path.

## Exact installation gate

The next implementation step may add the bounded installer and execute it only
after:

1. fresh target-hypervisor capacity and guest-ID/address collision checks;
2. exact owner-private identity, address, client address, certificate digests,
   and credential-file digests;
3. deterministic rendering of the complete creation/install/firewall/rollback
   plan;
4. human adoption of this brief; and
5. exact confirmation `INSTALL_SOUL_MEMORY_PROJECTION` with the fresh plan
   digest.

No current approval authorizes guest creation or service installation before
that gate.

## Acceptance

- Public configuration contains no owner-private identity, address, path,
  credential, certificate, or memory content.
- Official versions, artifact names, URLs, digests, licenses, and installation
  sources are closed and verified.
- Owner-private inputs are validated without returning secret values or paths.
- Public receipt contains only identity/address, resource plan, certificate and
  credential digests, phase names, expected digest, and authority labels.
- Public or multicast addresses, wildcard clients, reused credentials, missing
  TLS evidence, nesting, browser UI, plaintext databases, raw remote content,
  reverse synchronization, and canonical mutation fail closed.
- Deterministic tests perform no SSH, network, package installation, service
  creation, persistence, or live private-memory access.
