# Memory Projection Deployment A19 Review

Status: Candidate-complete exact-plan boundary; no guest or service deployment.

## Outcome

A19 selects a native-service design for one dedicated unprivileged Debian 13
LXC. It avoids nested Docker/Podman while retaining fixed upstream provenance:
Qdrant ships as its official checksum-pinned Debian package, Redis 8 comes from
the signed Debian 13 repository, and FalkorDB ships as its official
checksum-pinned module.

The deterministic plan validates the owner-private target identity, VMID, FQDN,
private subnet, fixed client, CA/certificate digests, independent credential
digests, and SSH public-key digest. It returns phase names and content-free
evidence only. It cannot connect, install, write, start a service, or create a
guest.

## Files changed

- `config/memory_projection_deployment_a19.json`
- `docs/soul/MEMORY_PROJECTION_DEPLOYMENT_A19_BRIEF.md`
- `lib/soul_core/memory_projection_deployment_plan.rb`
- `scripts/verify-memory-projection-deployment-a19.rb`
- `docs/assessments/MEMORY_PROJECTION_DEPLOYMENT_A19_REVIEW.md`
- `docs/CURRENT_STATE.md`
- `Makefile`

## Research evidence

- Official Qdrant installation guidance supports local block storage, documents
  REST 6333/gRPC 6334/cluster 6335, and requires explicit security controls.
- Official Qdrant security guidance recommends authentication, private binding,
  TLS, and audit evidence. The latest official GitHub release inspected on
  2026-08-24 is 1.19.0 and publishes a Debian asset with SHA-256 metadata.
- Official FalkorDB documentation requires Redis 8 or newer, recommends the
  server-only deployment for production, and documents password authentication
  and persistence. Its latest official GitHub release inspected on 2026-08-24
  is 4.20.4 with a SHA-256-addressed Linux module.
- Debian 13 currently supplies signed Redis Server 8.0.2 or newer.
- Read-only live hypervisor evidence showed 16 GiB physical RAM and about 7.3
  GiB available with the current observability and security guests running.

## Commands and results

```text
gh api repos/qdrant/qdrant/releases/latest
gh api repos/FalkorDB/FalkorDB/releases/latest
ssh -o BatchMode=yes -o ConnectTimeout=5 <target> <read-only capacity inventory>
ruby -c lib/soul_core/memory_projection_deployment_plan.rb
ruby -c scripts/verify-memory-projection-deployment-a19.rb
make verify-memory-projection-deployment
make verify-memory-rebuildable-projection
make verify-memory-core-aware-worker
make verify-memory-retrieval-observatory
git diff --check
```

- Ruby syntax: both A19 files passed.
- A19 deployment plan: 23 checks passed.
- A18 rebuildable projection: 23 checks passed.
- A17 Core-aware worker: 18 checks passed.
- A16 autonomous lifecycle: 19 checks passed.
- Memory Observatory: A0-A1 deterministic verifier passed; facade 15 checks
  passed; Dashboard 14 checks passed.
- Private-memory separation: 12 checks passed.
- `git diff --check`: passed.

## Deterministic coverage

- exact resource profile, artifact versions, URLs, digests, licenses, and
  signed-package source;
- review-gated persistence and stable plan digest;
- private IPv4 and same-subnet client/gateway validation;
- independent credential and complete TLS/key digest evidence;
- no public ingress, plaintext database, browser UI, nested runtime, raw remote
  content, reverse synchronization, or canonical mutation;
- missing evidence, public address, out-of-subnet client, reused credentials,
  and unsafe manifest drift fail closed;
- no network, process execution, file mutation, service, or live-memory access.

## Risk and authority

- Risk: high at eventual deployment because it creates persistent remote
  services and transports private embeddings across the LAN.
- Current mutation: none.
- Canonical memory authority: unchanged.
- Model authority: none.
- Credentials/certificates/private identity: not created or inspected.

## Human review checklist

- [ ] Confirm native services are preferable to nested containers.
- [ ] Confirm the 2-vCPU/2-GiB/24-GiB guest profile.
- [ ] Confirm Qdrant 1.19.0, Redis 8 from Debian 13, and FalkorDB 4.20.4.
- [ ] Confirm fixed-client TLS and separate credentials for both databases.
- [ ] Confirm projection data remains disposable while configuration,
      credentials, and certificates enter owner-private backup scope.
- [ ] Adopt the A19 brief before installer implementation or live deployment.
