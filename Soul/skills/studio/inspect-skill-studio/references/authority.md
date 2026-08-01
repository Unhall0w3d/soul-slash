# Skill Studio inspection authority

## Read boundary

Inspection may read the proposal projection, Beta projection, and production
registry. It may report stages, test state, maturity, and registered status. It
must not expose proposal digests as reusable authorization or turn examples
into actions.

## Protected actions

Proposal approval, Beta workspace creation, Dev drafting, Beta execution, Gate
2 approval, production promotion, proposal closeout, rejection, and deletion
remain exact Operator-controlled Skill Studio actions. Spoken or typed model
output is never authority for those actions.

## Lifecycle

Return `complete`, `failed`, `awaiting_input`, `canceled`, or
`blocked_for_human_review`. Do not wait for the Operator, poll Studio state, or
continue in the background.

## Failure behavior

Missing or ambiguous identifiers produce no mutation. An unavailable or
invalid Studio projection fails visibly and must not be replaced with model
memory, cached conversation claims, or invented state.
