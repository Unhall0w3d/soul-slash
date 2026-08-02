# Wazuh and ClamAV Security A0 Brief

## Brief status

```text
architecture_candidate: yes
implementation_authorized_in_principle: yes
central_runtime_installation_review_required: yes
endpoint_agent_installation_review_required: yes
clamav_policy_review_required: yes
automatic_remediation_authorized: no
human_merge_review_required: yes
```

## Purpose

Add a reproducible, local-first security observability layer to Soul without
turning the language model into a security authority. Wazuh provides the
central manager, indexer, vulnerability and inventory evidence, and its own
full investigation dashboard. ClamAV provides selective malware scanning at
file-ingress boundaries. Soul presents a smaller read-only operational view,
explains retained evidence, and may invoke only separately reviewed bounded
operations.

This brief is deliberately portable. Hostnames, addresses, credentials,
certificates, enrollment keys, private alert data, exclusions derived from an
owner's files, and live fleet state remain ignored owner-local configuration.

## Architectural decision

### Central Wazuh node

Use one dedicated Linux virtual machine rather than installing the Wazuh
indexer on the Operator workstation, a hypervisor, a DNS appliance, or the
backup target. The initial single-node deployment should use:

- Ubuntu Server 24.04 LTS;
- 4 virtual CPU cores;
- 8 GiB RAM;
- a 60 GiB thin-provisioned system disk;
- a fixed private-LAN identity assigned outside tracked source;
- the Wazuh manager, indexer, and dashboard at one matched version.

The sizing is appropriate for the initial small Linux fleet and leaves room to
measure real index growth. It is not a promise that 60 GiB will remain adequate
after agent count, rules, or retention expand.

The selected hypervisor and guest identity are owner-local deployment choices.
The public setup flow must accept overrides rather than encode them.

### Network boundary

Only the private LAN may reach the central node. The first deployment permits:

| Port | Protocol | Purpose | Exposure |
| --- | --- | --- | --- |
| 443 | TCP | Wazuh web dashboard | reviewed private LAN |
| 1514 | TCP | enrolled agent events | reviewed private LAN |
| 1515 | TCP | agent enrollment | temporary/reviewed private LAN |
| 55000 | TCP | Wazuh server API | central node and exact Soul host only |

The indexer API on TCP 9200 remains local to the central node. Cluster ports,
Syslog collection, UDP agent transport, public router forwarding, wildcard
Internet exposure, and a second network listener in Soul are excluded.

TLS is required for the dashboard and API. Generated passwords, API secrets,
private keys, and enrollment material must be stored owner-only outside Git.
Installation output containing secrets must not be copied into review
artifacts.

## Initial endpoint policy

### Wazuh agents

Start with passive Linux monitoring on explicitly enrolled systems:

- the Operator workstation;
- each Proxmox hypervisor;
- the DNS appliance guest;
- the Fedora backup and maintenance guest.

Initial agent features may include system inventory, vulnerability detection,
security event collection, rootcheck, and a deliberately small file-integrity
scope. A detected package manager, SSH connection, or fleet enrollment is not
authorization to install a Wazuh agent. Each endpoint receives a reviewed
installation plan and a terminal receipt.

File integrity monitoring must not recursively watch model stores, generated
media libraries, VM disk images, encrypted Restic repositories, build caches,
or other high-churn/binary-heavy paths. Public defaults remain conservative;
owner-specific additions and exclusions stay private.

### ClamAV

ClamAV is selective defense-in-depth, not an indiscriminate full-disk scanner.
Initial placement is:

- Operator workstation: Downloads and explicit external/import staging;
- backup guest: only plaintext ingress or restore-staging paths, if present;
- hypervisors: no recursive scan of VM/LXC storage;
- DNS appliance: no ClamAV unless a later evidence-backed use case exists;
- encrypted Restic repositories: never scan repository blobs.

`freshclam` maintains signatures. A bounded manual scan terminates with a
receipt and a separately reviewed on-access mode may be considered only after
performance testing. Detection initially records and alerts. Automatic delete,
quarantine, process kill, firewall mutation, package removal, or Wazuh Active
Response is not authorized.

ClamAV findings are collected by Wazuh through reviewed local log collection.
Scan targets, exclusions, limits, timeouts, result paths, and retention must be
explicit. Large model and media files require size-aware exclusions so a scan
cannot silently monopolize the workstation.

## Retention and backup

Begin with 30 days of searchable Wazuh alert history. Measure actual index
growth and revisit retention rather than assuming vendor sizing is permanent.
Wazuh configuration, certificates required for recovery, agent enrollment
state, custom rules, and role definitions require an encrypted recovery plan.
Raw searchable indices are not automatically added to the existing DRS scope;
their backup value, size, consistency method, and restore test require a later
review.

ClamAV transient scan inputs remain owned by their source workflow. Scan
receipts and detection evidence may be retained for 30 days unless an active
incident or human review explicitly preserves them. This policy never deletes
the source file automatically.

## Wazuh dashboard and Soul integration

Wazuh includes a complete HTTPS web interface for agent management, inventory,
vulnerabilities, alerts, dashboards, and investigation. It remains the
authoritative security console.

Soul A4 should add an Administration **Security** surface rather than embedding
the Wazuh interface. Its read-only summary may show:

- central service reachability and last successful refresh;
- enrolled, active, disconnected, pending, and never-connected agent counts;
- critical/high alert counts over a declared interval;
- vulnerable package summaries by severity;
- ClamAV engine and signature freshness per applicable endpoint;
- recent bounded scan outcomes and unresolved detections;
- exact deep links into the private Wazuh dashboard.

Soul uses a dedicated least-privilege Wazuh API identity, never the Wazuh admin
account or indexer administrator. Credentials stay in owner-only runtime
storage. Responses are allowlisted, size-bounded, timeout-bounded, redacted,
and cached only in the existing private application-state conventions.
Indexer API access is excluded from the first Soul integration.

Chat and Voice may answer read-only questions such as agent health, recent
high-severity findings, or signature freshness from fresh evidence. They may
offer a bounded refresh or manual scan only after that operation has its own
reviewed skill contract. Model output cannot acknowledge, suppress, quarantine,
remediate, or close an alert.

## Staged rollout and gates

### A0 — architecture and prerequisites

- adopt this topology and trust boundary;
- verify central-host capacity and private-LAN identity;
- define private configuration and secret storage;
- prepare exact install, rollback, and evidence commands;
- make no service or endpoint change.

### A1 — central Wazuh deployment

- create the reviewed VM;
- install one matched Wazuh release using an integrity-checked official method;
- restrict firewall exposure;
- replace/bootstrap TLS as reviewed;
- rotate generated administrator credentials into owner-only storage;
- verify dashboard, API, indexer health, resource use, reboot survival, and
  rollback before enrolling endpoints.

### A2 — passive agent cohort

- enroll one low-risk pilot endpoint first;
- verify event flow, inventory, vulnerability evidence, CPU/disk/network cost,
  and false-positive volume;
- expand one endpoint at a time with exact receipts;
- keep Active Response disabled.

### A3 — selective ClamAV

- install engine and signature updater only on approved endpoints;
- qualify one bounded manual scan and Wazuh log ingestion;
- measure resource impact and tune public-safe plus owner-private exclusions;
- consider on-access scanning only in a separate reviewed sub-gate.

### A4 — Soul security surface

- implement read-only API configuration and a bounded client;
- add Administration → Security and deep links to Wazuh;
- add read-only Chat/Voice invocation metadata;
- test stale, unreachable, malformed, unauthorized, and partial-data states;
- add no remediation authority.

### Later — response and recovery

Quarantine, Active Response, firewall changes, process termination, endpoint
isolation, package remediation, alert acknowledgement, unattended scans, and
index backups each require their own human-authored brief and exact gates.

## Failure and rollback behavior

- Failure to install or verify the central node leaves existing Soul and fleet
  maintenance untouched.
- An unreachable Wazuh server never blocks normal endpoint boot, DNS, backup,
  maintenance, or Soul operation.
- Agent rollout stops after the first unexplained resource, connectivity, or
  evidence-integrity failure.
- ClamAV failures report `failed` or `blocked_for_human_review`; they never
  delete or move a source file.
- Soul renders security data stale or unavailable rather than healthy when the
  API cannot be freshly verified.
- Removal plans must uninstall only the exact reviewed agent or central
  components and preserve evidence selected for incident review.

## Required deterministic verification

- Public configuration contains no owner hostname, address, credential,
  certificate, enrollment token, or live alert.
- Network allowlists reject non-private and undeclared endpoints.
- Wazuh versions are matched and exact identity is reported.
- The indexer API is not exposed to Soul or the LAN in A0–A4.
- Read-only API credentials cannot perform administrative mutations.
- Dashboard summaries distinguish fresh, stale, unavailable, and partial data.
- Manual ClamAV targets and exclusions are normalized and bounded.
- Detection cannot delete, quarantine, or remediate.
- Agent and scan operations reach explicit terminal states.
- Existing maintenance, backup, Core, Chat, and creative verification remains
  unchanged.

## Human review checklist

- [ ] Approve the dedicated-VM topology and initial resource allocation.
- [ ] Select the owner-local hostname/address and confirm it is reserved.
- [ ] Approve 30-day initial alert retention.
- [ ] Review exact A1 services, firewall rules, TLS, secret storage, and rollback.
- [ ] Review the first passive-agent endpoint and collected modules.
- [ ] Review ClamAV targets and exclusions before any scan.
- [ ] Confirm Active Response and automatic quarantine remain disabled.
- [ ] Review Soul's proposed API role and Security surface before credentials are created.
