# Conversation and Trash verifier source curation — 2026-09-23

Status: isolated candidate for human safety and merge review. No live voice,
model, file restoration, memory projection, or service operation occurred in
this curation pass.

The shared conversation context warns against inventing overrides to a
mandatory skill refusal and gives explicit user corrections precedence over
an earlier mistaken interpretation. Voice Presence receives a short spoken
response instruction that preserves the relevant refusal and permits requested
detail. These are probabilistic model instructions; deterministic tool and
approval gates remain the enforcement boundary.

The Downloads move-to-Trash verifier now has an explicit `--functional-only`
mode to test its fixture and confirmation contracts while repository curation
is unfinished. Its normal invocation still runs the strict curation check.
The mode reports that curation was not checked and cannot be used as a merge
or approval signal. The existing Trash documentation explains this distinction.

Checks in the isolated branch: conversational safeguard verifier, all 35 chat
intent and interaction checks, the Voice Presence local latency verifier, the
Trash functional-only verifier, and `git diff --check` passed. A prior owner
review retained a two-turn bridge replay; it also left correction replay,
unknown-fact abstention, and physical Voice Presence acceptance open. Those
human and live gates remain pending here.
