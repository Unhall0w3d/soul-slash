# Maintenance authority contract

## Authority classes

- `read_only`: inspect current evidence without confirmation.
- `routine_mutation`: require one explicit request, an exact target, a
  server-authored preview, and one short-lived authenticated conversational
  confirmation.
- `protected_action`: prepare and explain the operation, then stop for an
  Operator gesture in the owning Dashboard, terminal, or Noctalia surface.

## Availability operations

A reboot of one exact non-workstation managed device may use
`routine_mutation` only when the fixed controller provides a digest-bound
preview, one short-lived authenticated confirmation, one reboot request,
bounded reconnect attempts, boot-identity change evidence, and reviewed
readiness checks. No conversational fleet-wide reboot exists.

## Protected operations

Atelier maintenance or reboot, permanent deletion, backup-snapshot deletion,
credential or permission changes, and external publication cannot use
conversational affirmation as execution authority.

## Lifecycle

Terminate every invocation as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. Never wait indefinitely for a reply
or keep a private worker alive after returning.

## Failure behavior

Stale or changed previews execute nothing. Missing, ambiguous, expired, or
unsupported targets execute nothing. Report only bounded evidence and retained
receipt identifiers; never expose credentials or raw command output.
