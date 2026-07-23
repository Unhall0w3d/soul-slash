# Visual Studio Resource Responsiveness Brief

Status: Operator-reported corrective slice

## Problem

Opening Visual Studio automatically performs full SHA-256 verification of
approximately 4.9 GB of pinned model files. Every resource or generation
preview repeats that work. The dashboard presents no immediate working state,
so repeated clicks can start duplicate checks and make update, inspection, and
preview controls appear inert.

## Approved correction

- Preserve full SHA-256 verification before a model file is considered ready.
- Cache a verification result only inside the running Visual Studio service and
  only for the exact expected digest plus file device, inode, size, mtime, and
  ctime identity.
- Re-stat after hashing; a file changed during verification fails closed.
- Serialize duplicate verification of the same singleton service so concurrent
  resource requests do not hash the same multi-gigabyte files repeatedly.
- Invalidate and re-hash after any observed file identity change.
- Show an immediate status and disable/re-enable the initiating Visual Studio
  button while save, inspection, or generation preview is in flight.

## Boundaries

- No digest, size, model, Core, generation, approval, or review requirement is
  weakened.
- No persistent cache, service, worker, queue, polling loop, watcher, or
  background continuation is introduced.
- No generation is started by resource inspection or preview.

## Acceptance

- First inspection performs the full digest pass.
- Repeated inspection of unchanged files reuses the in-process result.
- Any file identity change forces another digest pass and corrupt content is
  rejected.
- The three reported controls immediately expose a visible working state and
  always restore their enabled state at a terminal outcome.
- Visual Studio A1/A2, conversational visual revision, and dashboard syntax
  regressions remain green.
