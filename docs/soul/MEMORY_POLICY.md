# Soul Memory Policy

Soul memory exists to make repeated use more useful without making behavior mysterious.

Memory should be shared, attributable, inspectable, and recoverable. Ordinary
memory lifecycle work may be autonomous when it is local, policy-bounded,
reversible, and fully audited; protected authority and irreversible loss remain
human decisions.

## Memory classes

### Session memory

Temporary context for the current conversation or invocation. It should not be treated as durable user knowledge.

### Task state

Saved progress for an incomplete multi-turn task. Task state enables clean exits and later resumption without keeping a process alive.

### Durable memory

Reusable facts, preferences, defaults, locations, providers, paths, or other
context admitted by an approved deterministic policy or explicit human action.

### Reflection

Post-task notes describing what happened, what worked, what failed, and what should improve.

### Source observations

Exact locally retained conversation messages and later approved evidence
sources. Capture does not imply truth, agreement, importance, or eligibility
for ordinary retrieval. Observations remain immutable provenance from which
candidate memory may later be derived.

## Shared infrastructure rule

Memory is shared infrastructure, not skill-private storage.

Skills may request, read, update, or forget approved memory keys through the shared memory/context layer.

Skills must not create isolated private memory files or formats unless a human-authored brief explicitly approves it.

## Durable memory rules

Durable memory keys should be:

- Named clearly
- Scoped appropriately
- Documented in the skill review artifact
- Backed by attributable observations or reviewed deterministic derivation
- Forgettable or replaceable where appropriate
- Reused by other skills when semantically appropriate

## Example memory keys

```text
user.default_location
weather.default_location
calendar.default_timezone
local_search.default_area
downloads.default_directory
utility.default_provider
```

Prefer general keys when the context is useful across skills. Prefer skill-specific keys only when the context is truly skill-specific.

Example:

```text
Correct:
user.default_location = "Syracuse, NY"
weather.default_location uses user.default_location unless overridden
```

```text
Wrong:
skills/weather/weather_location.json
```

## First-use behavior

When a skill requires durable context that does not exist, it should ask for the missing information and enter `awaiting_input`.

It should not promote unsupported guesses. Ambiguous ordinary claims may remain
as conflicting candidates until later evidence resolves them.

It should not keep a process alive while waiting.

## Update and forget behavior

When practical, users should be able to say things like:

```text
Use Buffalo for weather instead.
Forget my weather location.
Use Syracuse as my default location.
```

The memory layer should apply ordinary corrections promptly and make every
change inspectable and reversible through its audit history.

## Standing autonomous authority

Soul may autonomously capture local conversation observations and create,
classify, consolidate, promote, demote, supersede, reactivate, or logically
tombstone ordinary memory when a reviewed deterministic policy authorizes the
operation. Autonomous changes must record their actor, trigger, evidence,
reason, policy version, before/after digests, and rollback reference.

Soul must retain source observations and use compensating lifecycle events
instead of rewriting historical evidence. Routine uncertainty should produce a
candidate or conflict, not an item-by-item human approval queue.

Successful conversation turns are captured automatically in the shared
owner-private observation ledger. Operational chat deletion does not silently
rewrite that immutable evidence. Physical purge remains a separate protected
operation.

The following remain protected and require an explicit human decision:

- credentials, secrets, and authentication material;
- permission or authority grants;
- destructive-operation authorization;
- safety and security policy;
- operator identity and protected persona rules;
- physical purge of irreplaceable source observations;
- export beyond the approved local or private-infrastructure boundary;
- broad retention-policy changes and irreversible bulk operations.

## LLM limits

LLMs may identify, summarize, relate, or propose lifecycle changes for ordinary
memory. Admission and mutation authority belongs to the reviewed deterministic
policy, not to the model or agreement among several models.

LLMs must not authorize risky behavior based on remembered context alone.
