# Voice and model-runtime source curation — 2026-09-23

Status: isolated candidate for human merge review. The earlier AMD Whisper
handoff packet records supervised runtime acceptance; later restoration notes
record the Operator's physical Voice Presence acceptance for that restoration
scope. Free Core startup behavior and the Soul-Lite creative path retain their
separate review and listening gates. This curation did not capture audio,
change the selected Core, stop or start a model, rebuild memory, or alter a
service.

## Source scope

The dashboard, Voice Presence bridge and standalone transcription command now
use one routed transcription service. AMD and CUDA adapters require pinned
local assets, bounded normalization and recognition, and explicit recovery
before returning a transcript. The AMD lane refuses uncertain allocations and
retains a pending recovery receipt after failure. No CPU fallback or silent
chat submission follows an unsuccessful handoff. Exact digital silence is
rejected before recognition; nonzero quiet speech is not amplitude-filtered.

The model runtime's temporary release observes pre- and post-recovery GPU
placement and bounds recovery attempts. Free Core startup declines to start a
chat model and refuses to stop an unexpectedly active one automatically. The
shared command runner reaps owned child processes on cancellation. Creative
music use under Soul-Lite remains a separate exact foreground action.

## Verification

Ruby 4.0.7 with Prism: 13 targeted verifiers passed, covering command bounds
and cancellation, local/AMD/CUDA/routed transcription, GPU identification and
allocation, both handoff coordinators, temporary model release, Free startup,
Core orchestration and conversational creative routing. `git diff --check`
passed after curation. The GPU-required upstream patch remains in the owner's
private build-review material; no new native binary was compiled in this pass.

## Remaining gates

Review the source cohort as one integration boundary. Reconcile which later
Operator acceptance covers the exact browser and wake-word path before calling
those gates closed. Assistant-name recognition and conversational safeguard
fidelity are separate candidates. A later installation or GPU qualification
needs fresh resource and service observations; deterministic fixtures do not
reserve hardware or certify another machine.
