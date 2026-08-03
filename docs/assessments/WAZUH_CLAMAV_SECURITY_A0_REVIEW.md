# Wazuh and ClamAV Security A0 Review

## Status

Validated rollout. A0 itself made no runtime change; its separately reviewed
A1–A4e gates are now deployed, qualified, and accepted. Wazuh remains the
authoritative investigation console and all Soul integrations remain
read-only.

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

## Retained limitations and separate future decisions

- Exact deployment identity, credentials, certificates, mappings, and live
  security evidence remain owner-local.
- Index growth and the accepted 30-day retention require ordinary operational
  observation rather than unattended policy changes.
- The community Arch agent remains an explicitly reviewed packaging exception
  and can trail the manager release.
- ClamAV on-access mode is not part of this candidate.
- Wazuh raw-index backup and isolated restore are not designed yet.
- Current ClamAV signatures and scan receipts are not centralized into the
  conversational status invocation.

## Memory keys added or used

None.

## Lifecycle states touched

All accepted stages terminate explicitly. The final A4e foreground read returns
`complete` with fresh, partial, or unavailable evidence and no automatic retry.

## Risk classification

Deployed central and endpoint services remain separately reviewed persistent
infrastructure. Soul's final operational surface is `read_only_network`; it has
no response or remediation authority.

## Human review checklist

- [x] The Wazuh VM placement and 4 vCPU / 8 GiB / 60 GiB allocation are acceptable.
- [x] Private-LAN-only ports and the unexposed indexer API are acceptable.
- [x] Passive-first agent collection is appropriately narrow.
- [x] ClamAV exclusions protect backups, VM storage, models, and generated media.
- [x] Thirty-day initial alert retention is accepted.
- [x] Soul remains read-only and Wazuh remains the investigation console.
- [x] Automatic response and remediation remain out of scope.
- [x] A1–A4e completed through separate supervised review gates.
