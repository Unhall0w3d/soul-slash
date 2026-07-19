# Music Job Continuity A1 Brief

## Human-approved objective

Music candidate generation and revision generation must continue when the Operator navigates away from Music Studio or the initiating browser stream disconnects. Returning to the project must recover live progress or the completed candidate and its dashboard artifacts.

## Boundary

- The existing authenticated dashboard process owns one bounded music-generation thread.
- Exact preview digest and click approval remain mandatory before acceptance.
- Initial and revision generation share the existing single music resource lane; there is no pending queue.
- Progress and terminal results are atomically recorded under `Soul/music/jobs` with mode `0600`.
- A browser may detach and later follow the same candidate-bound job.
- Existing generation timeouts, cancellation, process-group ownership, artifact validation, and human listening review remain authoritative.
- A dashboard process restart does not silently resume inference. An in-flight receipt becomes `failed` with explicit interruption evidence; any candidate already published by the generation service remains discoverable through the project archive.
- At most 100 terminal receipts are retained. This slice adds no service, scheduler, watcher, network listener, automatic model load, publication, or unattended retry.

## Lifecycle

The dashboard receipt moves through `accepted`, `running`, and `terminal`. Its application lifecycle terminates as `blocked_for_human_review`, `failed`, `canceled`, or another explicit result returned by the bounded generation service.
