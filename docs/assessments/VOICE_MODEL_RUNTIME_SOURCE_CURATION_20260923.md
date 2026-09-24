# Voice and model-runtime source curation — 2026-09-23

Status: candidate with completed 2026-09-24 unattended Whisper verification and Operator authorization to commit and merge. The earlier AMD Whisper
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

## Native patch inventory — 2026-09-24

The `config/whisper-require-gpu.patch` source was an untracked curation
candidate before this review. The existing ignored Vulkan runtime is already the GPU-required
build recorded in the 2026-09-06 AMD routing review: its `libwhisper.so.1.9.1`
and CLI SHA-256 values match the recorded exact pins, the loader symlinks
resolve to that library, and the library contains the explicit CPU-fallback
refusal message. The AMD and routed transcription verifiers passed again. No
new binary was built, installed, or promoted in this check. The earlier
`unrebuilt` shorthand describes this curation pass, not the existing runtime
artifact. A clean checkout of whisper.cpp tag v1.9.1 resolved to the pinned commit
`f049fff95a089aa9969deb009cdd4892b3e74916`. The seven-line patch passed
`git apply --check`, applied as the sole source change, and an isolated CMake
Vulkan `whisper-cli` build completed successfully under `/tmp` with the guard
message in the resulting library. The build used the current GCC 16.2.1 and
Vulkan 1.4.357 toolchain, so its binary hash differs from the retained GCC 14
runtime artifact; it was not installed or selected. The build emitted upstream
compiler warnings in timestamp formatting and Vulkan code. The Operator authorized commit and merge after unattended Whisper verification.
Physical Voice Presence acceptance is separate.
