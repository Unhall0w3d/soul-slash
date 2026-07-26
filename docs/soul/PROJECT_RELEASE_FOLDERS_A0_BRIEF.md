# Project Release Folders A0 Brief

## Objective

Let the Operator remove finished Music Studio and Visual Studio projects from
the primary working lists while keeping them accessible in a Released folder.

## Boundary

- Release is a reversible organizational state, not deletion or filesystem
  relocation.
- Project IDs, project directories, candidates, reviews, exports, generated
  artifacts, and cross-studio binding records remain unchanged.
- Each project may be marked `active` or `released`.
- New projects begin active.
- The dashboard defaults to Active and exposes Active and Released views
  independently in both studios.
- A single deliberate click may release or restore a project because the action
  is local, reversible, non-destructive, and unprivileged.
- No model, generation, publication, service, watcher, or background task is
  introduced.

## Persistence

Release state is stored in a bounded regular JSON marker inside the existing
project directory. The marker records only project kind, project ID, and release
time. Removing the marker restores the project to Active.

## Acceptance

- Active views omit released projects.
- Released views retain full project inspection and all existing actions.
- Restore returns the same project ID to Active.
- Candidate and binding bytes remain unchanged across release and restore.
- Invalid IDs, symlinks, unknown project kinds, and missing projects fail
  safely.

## Risk

Low. The feature adds reversible local classification metadata only.
