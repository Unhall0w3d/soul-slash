# Incident Narrator A0 Review

Status: repair verified; owner approved commit and merge; post-repair live report awaits Operator review

## Candidate intent

Incident Narrator A0 composes one deterministic, source-attributed explanation
from five retained security, maintenance, and backup sources. It performs no
source collection, remote query, diagnosis, remediation, or action. The separate
Fleet Observability operation remains available and is outside A0's source set.

## Repair and evidence

The September 27 read-only audit held A0 after finding a live Fleet query in
facade wiring, free-form receipt diagnostics in output, early alert truncation,
a quiet state despite partial evidence, and silent acceptance of malformed
source shapes. This repair:

- removes the Fleet query and its sixth source from A0;
- constructs receipt statements from bounded, known operation, mode, and state
  values; source failures and exceptions return fixed text;
- validates retained source and nested record shapes, including the Wazuh
  256-alert input bound, and marks malformed evidence unavailable;
- groups all retained alerts and selects urgent events before the 64-event
  output bound, then presents the selected events newest first; and
- marks partial, truncated, stale, unavailable, and unknown source evidence as
  gaps that prevent a quiet state. A DRS state other than complete also needs
  attention.

The repair changes lib/soul_core/incident_narrator_service.rb,
lib/soul_core/application_facade.rb, scripts/verify-incident-narrator-a0.rb,
this review, the human-review index, and the skill review template. It does not
change the application contract, Dashboard controls, Fleet Observability
implementation, or retained evidence.

## Deterministic qualification

    make verify-incident-narrator                    PASS (26 assertions)
    make verify-host-stewardship-file-steward       PASS
    make verify-software-storage-steward             PASS
    make verify-maintenance-foreground-execution     PASS
    make verify-maintenance-device-control           PASS
    make verify-backup-administration                PASS
    make verify-fleet-observability-a3               PASS
    node --check assets/dashboard/dashboard.js       PASS
    ruby -c changed Ruby files                       PASS
    git diff --check                                 PASS

The A0 verifier exercises the real facade wiring with injected retained
readers and fails if it calls Fleet Observability. It also covers older critical
alerts behind 64 routine alerts, distinct event overflow, malformed and
oversized inputs, partial and truncated sources, and credential-like strings in
receipt text, source reasons, exceptions, and enum-shaped fields. These are
deterministic component and integration checks; they do not qualify the
resident Dashboard process.

## Live qualification and remaining gate

A pre-repair owner-local composition produced 39 events, three observations,
zero temporal inferences, and two gaps. That run describes the earlier code
and does not qualify this repair. No post-repair live compose, service restart,
or authenticated Dashboard review is claimed here.

The Operator must review one post-deployment live report before A0 is promoted
or extended. Check the headline, selected chronology, source gaps, privacy,
and distinction between observations and cautious inference. A merged commit
is separate from resident-service deployment and human acceptance.

## Local LLM evaluation

None. A0 is deterministic and model-free.

## Memory and lifecycle

No memory key is added or used. Each request terminates as complete or failed.
No service, watcher, listener, timer, scheduled task, background continuation,
or automatic refresh is introduced.

## Risk classification

Read-only synthesis of already-normalized owner-local evidence. Disclosure,
silent source incompleteness, and hidden urgent evidence are the material
risks addressed by this repair. A0 does not claim root cause or recommend
remediation.

## Known weaknesses

- A0 explains only the retained evidence available at invocation time.
- Temporal correlation is cautious and does not establish causality.
- Raw Wazuh descriptions are omitted; the authoritative Wazuh console is
  needed for detailed investigation.
- The selected 64 events favor severity before recency. The displayed
  selection is newest first; less urgent events may be omitted.

## Human review checklist

- [ ] The headline and summary accurately reflect the displayed evidence.
- [ ] Newest-first chronology is useful and understandable.
- [ ] Observations, inferences, and evidence gaps are visually distinct.
- [ ] Every inference cites supporting evidence and remains cautious.
- [ ] Missing, stale, partial, or truncated sources do not read as healthy.
- [ ] No raw alert text, path, command line, credential, or private
      configuration is exposed.
- [ ] The card runs only on explicit request and offers no remediation action.
