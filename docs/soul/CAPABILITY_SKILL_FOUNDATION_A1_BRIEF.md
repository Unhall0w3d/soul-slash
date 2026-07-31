# Capability and Skill Foundation A1

## Purpose

Give Soul one machine-readable account of its Operator-facing surfaces and
prove the first administrative conversational workflow by routing device
maintenance through the existing fixed fleet controller.

This slice is a foundation, not a claim that every Dashboard control is
already available through Chat.

## Capability contract

`config/operator_capability_catalog.yaml` is the current source for:

- surface identity and aliases;
- required input guidance;
- registered skills and invocation entries;
- existing application operations and supported targets;
- Dashboard, Chat, and Voice Presence coverage;
- routine conversational confirmation versus protected Operator gesture; and
- progress and receipt behavior.

The Dashboard capability guide must read this catalog. It must not keep a
second hard-coded surface inventory.

## First vertical slice: device maintenance

An explicit request to maintain one exact managed non-workstation device may:

1. resolve the target from fresh persisted fleet evidence;
2. call the existing device-control preview;
3. repeat the exact device, address, adapter, and no-reboot boundary;
4. retain the digest-bound plan for at most ten minutes;
5. accept a short affirmative or negative follow-up;
6. execute only the retained fixed maintenance plan; and
7. return progress, receipt, refreshed status, remaining updates, reboot
   state, and bounded issues.

Ordinary discussion, status questions, and missing or ambiguous targets must
not invoke maintenance.

## Protected boundary

The conversational workflow must not execute:

- reboot;
- workstation maintenance;
- permanent deletion;
- backup snapshot or retention deletion;
- credential or permission changes; or
- external publication.

Soul may explain or prepare these actions, but only an Operator-controlled
Dashboard click, reviewed terminal action, or Noctalia gesture is authority.
Model output and typed or spoken affirmation are never authority for protected
actions.

## Bounded lifecycle

The workflow terminates as `complete`, `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`. It creates no service, watcher, scheduler,
listener, polling loop, automatic retry, or private memory layer.

## Acceptance

- deterministic routing distinguishes conversation from an explicit request;
- confirmation is target- and digest-bound and expires;
- voice and text share the same Chat runtime path;
- the existing maintenance controller remains the only execution engine;
- protected actions cannot cross the conversational boundary;
- self-recognition comes from the capability catalog; and
- the skill package, invocation entry, guide, tests, and review artifact agree.
