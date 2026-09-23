# Fleet observability source curation — 2026-09-23

Status: A1.1 map adaptation was previously accepted on the reference host.
The expanded A2 Linux-host SNMP source is a candidate for human merge review;
the larger A2/A3 review packet still calls for Operator workflow acceptance.
This curation performed no network, service, SNMP-community or dashboard
promotion action.

The candidate adds a separate Linux-host SNMP target lane alongside existing
switch and Alloy evidence. Public configuration contains a generic module and
file-discovery locations; target addresses and communities stay owner-private.
The dashboard uses generic labels and no private site coordinates. The
renderer refuses to erase configured host targets on a switch-only rerender.
The Operator-approved seven-character switch community boundary is retained,
with deterministic acceptance at seven characters and refusal at six.

The A1.1 and A2 verifiers, shell syntax for changed deployment scripts, and
`git diff --check` passed in the isolated worktree. Prior host observations
are historical evidence rather than a fresh deployment qualification. Before
source promotion, the Operator should confirm panel readability, missing-data
presentation, and whether the deployed generic renderer names should be
converged with the working owner-private configuration. No remediation or
notification authority is added by this source candidate.
