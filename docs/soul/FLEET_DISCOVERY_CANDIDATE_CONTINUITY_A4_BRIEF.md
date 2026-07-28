# Fleet Discovery Candidate Continuity A4 Brief

```text
date: 2026-07-28
human_authorization: approved in the active development conversation
risk: Class 1 Dashboard session-state correction
```

## Objective

Preserve the unacted-on results of one explicit subnet scan while the Operator
reviews and acts on candidates sequentially.

## Required behavior

- Successful enrollment removes only the enrolled address from the current
  page-session candidate list.
- Successful ignore removes only the ignored address from the current
  page-session candidate list.
- Restoring an ignored identity preserves the current candidate list.
- Removing an enrolled registry record preserves the current candidate list;
  a new scan remains necessary only to rediscover that removed device.
- Candidate counts and empty-state copy update immediately.

## Boundaries

- Scan results remain ephemeral and are not persisted.
- No automatic rescan, discovery command, background process, or polling is
  introduced.
- Each enrollment and ignore operation retains its existing exact preview,
  digest, confirmation, and backend revalidation.
- This UI correction grants no trust or device-mutation authority.

## Acceptance

- Given three visible candidates, enrolling one leaves the other two visible.
- Ignoring either remaining candidate leaves the final candidate visible.
- The candidate count matches the preserved list after each action.
- Restore and registry removal do not erase unrelated candidates.
- A fresh explicit scan still replaces the candidate list with fresh evidence.
