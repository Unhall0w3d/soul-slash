# Wazuh and ClamAV Security A0 Review

## Status

Architecture candidate ready for human review. No Wazuh VM, package, service,
agent, API user, firewall rule, certificate, ClamAV process, scan, or schedule
was created by A0.

## What this candidate decides

- Wazuh supplies the authoritative central security console.
- A dedicated small Linux VM hosts the manager, indexer, and dashboard.
- Endpoint enrollment begins passive and expands one reviewed system at a time.
- ClamAV is limited to explicit file-ingress paths and does not scan encrypted
  backups, model stores, generated media, or VM disks by default.
- Soul receives a separate read-only Administration surface and bounded
  conversational access, not Wazuh administrator authority.
- Automatic response, quarantine, deletion, and remediation are excluded.

## Files changed

- `docs/soul/WAZUH_CLAMAV_SECURITY_A0_BRIEF.md`
- `docs/assessments/WAZUH_CLAMAV_SECURITY_A0_REVIEW.md`
- `docs/ROADMAP.md`
- `config/project_tracker_seed.json`

## Commands run

```text
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
ruby scripts/verify-docs-cleanup.rb
git diff --check
```

## Deterministic results

The project tracker parses successfully, documentation cleanup verification
passes, and `git diff --check` reports no whitespace errors.

## Local-model evaluation

None. A language model cannot approve security topology, privileges,
persistence, destructive behavior, or remediation authority.

## Known weaknesses and open decisions

- The exact central VM identity remains owner-local and unselected in tracked
  source.
- Real index growth and resource use are unknown until a passive pilot runs.
- A 30-day initial retention is proposed but not yet approved.
- Exact Wazuh version, package integrity evidence, firewall syntax, certificate
  flow, and secrets mechanism belong to the A1 deployment plan.
- Arch-family agent packaging and upgrade behavior requires qualification on
  the Operator workstation before fleet expansion.
- ClamAV on-access mode is not part of this candidate.
- Wazuh raw-index backup and isolated restore are not designed yet.

## Memory keys added or used

None.

## Lifecycle states touched

Planning only: `blocked_for_human_review` before A1 installation.

## Risk classification

Architecture planning: `network_read`, future persistent privileged services,
and future endpoint security telemetry. No runtime mutation occurred.

## Human review checklist

- [ ] The Wazuh VM placement and 4 vCPU / 8 GiB / 60 GiB allocation are acceptable.
- [ ] Private-LAN-only ports and the unexposed indexer API are acceptable.
- [ ] Passive-first agent collection is appropriately narrow.
- [ ] ClamAV exclusions protect backups, VM storage, models, and generated media.
- [ ] Thirty-day initial alert retention is acceptable.
- [ ] Soul remains read-only and Wazuh remains the investigation console.
- [ ] Automatic response and remediation remain out of scope.
- [ ] Proceed to an exact A1 deployment plan and supervised installation.
