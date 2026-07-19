# Music Studio A3 — bounded dashboard brief

## Approved outcome

Expose the existing Music A2 project and generation core through a themed dashboard tab. The smallest complete slice includes project creation and inspection, exact generation preview, foreground progress, explicit cancellation, candidate playback, and recorded human adherence review.

## Authority and exclusions

- Generation remains one foreground request with one NVIDIA music lease.
- The dashboard never loads, unloads, or preempts a model automatically.
- There is no job queue, watcher, scheduler, or retry loop. Music Job Continuity A1 later authorizes one candidate-bound, bounded dashboard worker so an approved generation can survive browser navigation or request disconnection.
- Existing projects are immutable in A3. The form creates a new project; it does not silently rewrite a generated project's inputs.
- Every generation requires `START_MUSIC_GENERATION` plus the digest from the immediately preceding preview.
- Human cancellation continues to require its own preview, digest, and `CANCEL_MUSIC_GENERATION` confirmation.

## Request concurrency and termination

The existing loopback dashboard service may serve at most eight request-scoped threads so a cancellation request can reach a foreground generation stream. Excess connections receive `429`. Threads are tracked, sockets are closed on server shutdown, and the server joins request threads before returning. This is bounded request handling inside the already-approved dashboard service, not a background queue.

Generation output is drained through a bounded wait with a fixed deadline. Music Job Continuity A1 supersedes A3's request-lifetime coupling: client abandonment no longer terminates an accepted generation. Server shutdown, timeout, explicit cancellation, or task completion still terminates the exact owned process group, releases its lease, and leaves either a published candidate or inspectable failure evidence.

## Human review surface

Candidate review records musical quality, prompt adherence, vocal adherence, lyric adherence, disposition, rating, and notes. Reviews remain project-local evidence and do not promote, publish, train, or update shared memory.

## Lifecycle states

Operations terminate as `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`. A successfully generated candidate remains `blocked_for_human_review` until the Operator records listening evidence.
