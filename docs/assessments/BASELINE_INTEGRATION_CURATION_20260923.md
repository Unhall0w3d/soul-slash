# Soul baseline integration candidate — 2026-09-23

Status: local integration candidate for human review. This branch combines the
Ruby 4.0.7/Prism baseline, complete untracked curation reporting, agent
controls, accepted-source repairs, fleet observability, routed voice and model
runtime, creative Vulkan profiles, maintenance adaptation, and conversational
safeguards. It was assembled in `/tmp/soul-integrated-curation`; it has not
been merged, pushed, installed, deployed, or used to change live services.

The original checkout remains dirty by design. Its 237 individual paths are
accounted for in the owner-private curation manifest: 111 modified and 126
untracked files, which Git's default status groups into 230 entries. Of the
237, 161 are represented in isolated source candidate branches and 76 remain
held. The held set includes historical host/recovery evidence, the permissive
`.codex/config.toml`, an unrebuilt native Whisper patch, site-specific Crucible
syslog deployment with a conflicting human outcome record, privileged
configuration capture pending backup acceptance, incident tooling, and
unresolved name-recognition design. No held item was deleted or broadly staged.

One Makefile cherry-pick overlap was resolved by preserving both the existing
agent verifier recipes and the new maintenance-platform verifier. The
Operator-approved seven-character switch SNMP community boundary is preserved
with a six-character refusal check. The Annex-named fleet timer brief is
represented by a Soul-named candidate document; no timer was disabled.

Verification in the combined branch:

- `make test-soul` exited 0 as a workflow/CLI smoke check. Its read-only
  `system.status` returned a warning because the sandbox could not reach the
  user bus or local model loopback; this is not live endpoint qualification.
- 32 focused deterministic verifiers passed across repo curation, agent
  controls, backup/command bounds, Wazuh, dashboard/memory, observability,
  voice/Core, creative, maintenance/SNMP, conversation, and Trash.
- `git diff --check` passed and the integration worktree was clean before this
  packet was added.

Each cohort's packet records its own tests and remaining human or live gate.
The integrated branch is reviewable source, not merge readiness, machine
qualification, protected-policy approval, GPU/render quality acceptance, or
backup/restore promotion. The repository's human review gate still reserves
those decisions for the Operator.
