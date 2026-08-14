# Incident Narrator A0 Brief

## Objective

Turn Soul's retained host, security, maintenance, and continuity evidence into
one bounded chronological explanation for the Operator. The narrator answers
three questions without pretending to be an investigation engine:

1. What was observed?
2. What relationship can be cautiously inferred from that evidence?
3. What evidence is unavailable or still needs human investigation?

## Authority and lifecycle

`incident_narrator.compose` is a foreground, read-only operation. It reads
existing normalized snapshots and receipts, returns one deterministic report,
and terminates as `complete` or `failed`.

A0 must not:

- query Wazuh, the network, a remote host, or a package repository;
- run a shell command or start a maintenance, backup, or remediation action;
- acknowledge, suppress, quarantine, delete, or otherwise mutate evidence;
- use a language model, conversation memory, or a private narrative store;
- poll, schedule, retry in the background, or remain alive after returning.

## Evidence sources

The application supplies only already-retained, normalized evidence:

- the latest Wazuh alert snapshot;
- the latest Wazuh manager and agent-health snapshot;
- bounded device-maintenance receipts;
- bounded local foreground-maintenance receipts; and
- the latest local backup/DRS status summary.

Each source remains authoritative for its own facts. A source that is absent,
stale, malformed, or unavailable is represented as an explicit evidence gap;
it is never converted into a healthy result.

## Narrative contract

The response uses schema `soul.incident-narrator.a0.v1` and contains:

- a bounded state, headline, and deterministic summary;
- no more than 64 newest-first events with opaque evidence IDs;
- no more than 32 observations, cautious inferences, and evidence gaps;
- source availability and observation timestamps; and
- explicit declarations that automatic refresh, background polling, model use,
  and mutation authority are absent.

Observed facts cite one exact retained evidence ID. Inferences must cite their
supporting evidence IDs, use only `low` or `medium` confidence, and remain
clearly labeled. The narrator does not produce an incident root cause, a clean
bill of health, or a remediation recommendation.

## Privacy boundary

The response may expose normalized rule IDs, severity, bounded agent/device
labels, receipt IDs, operation kind, lifecycle state, and timestamps. It must
not expose raw Wazuh descriptions, raw events, command lines, credentials,
tokens, environment values, absolute paths, repository locations, private
configuration, or file contents.

## Operator surface

Administration → Host Stewardship gains one Incident Narrator card. The
Operator explicitly selects **Compose incident narrative**. The result shows a
compact state summary, newest-first evidence timeline, and separately labeled
observations, inferences, and gaps. Nothing runs automatically when the panel
opens.

## Acceptance

- deterministic fixtures prove ordering, bounds, explicit unavailable sources,
  severity and receipt-state handling, and privacy filtering;
- every inference cites retained evidence and never claims high confidence;
- the Dashboard distinguishes observed facts, inference, and missing evidence;
- no source refresh, model call, command execution, state write, or mutation is
  reachable through the operation; and
- a human reviews the live report before A0 is promoted or extended.
