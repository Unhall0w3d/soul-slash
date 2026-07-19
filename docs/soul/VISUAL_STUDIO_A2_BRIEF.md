# Visual Studio A2 Brief

Status: owner-authorized implementation candidate

Authorization date: 2026-07-18

## Outcome

Complete the human-controlled still-image lifecycle introduced in A1. An
operator can revise a project brief without rewriting existing candidate
inputs, record listening-style visual evidence, create an image-guided revision
from one exact candidate, permanently delete an exact candidate or project, and
bind one selected still to one selected Music Studio composition candidate.

## Authority and lifecycle

Each costly, destructive, or cross-studio operation remains bounded:

```text
project update -> complete (prior project record archived)
candidate review -> complete (prior review archived)
image edit preview -> blocked_for_human_review
  -> exact click approval -> one foreground render -> blocked_for_human_review
candidate/project deletion preview -> blocked_for_human_review
  -> exact click approval -> complete
Music binding preview -> blocked_for_human_review
  -> exact click approval -> base_bound in Music Studio
```

The approval click sends the displayed phrase and digest. There is no redundant
typing requirement. A stale digest, changed project/candidate, wrong phrase, or
missing source fails without mutation.

## Immutable lineage

- Updating a brief archives the prior `project.json` under the private project
  `revisions/` directory.
- Every candidate retains its own `input.json`, source image digest, effective
  prompt, effective seed, model profile, output digest, elapsed time, and log.
- An image-guided candidate identifies its exact parent candidate and source
  image digest.
- Re-recording a review archives the prior review rather than overwriting its
  evidence without history.

## Image-guided editing

FLUX.2 Klein uses the same pinned, bounded `sd-cli` executable as A1. The chosen
private candidate is supplied with `-r`; the operator provides a focused edit
instruction and seed. One CLI process starts for the request and exits at a
terminal result. No resident image server, queue, or watcher is introduced.

## Music Studio promotion

Promotion is an exact cross-studio binding, not publication. The selected PNG
is copied into the selected Music project/candidate as the ordinary
`base_bound` visual-companion stage. Existing loop review and final companion
rendering remain the next Music Studio gates. A later deletion of the Visual
Studio source does not silently delete the already-bound Music copy.

## Deletion

Candidate and project deletion previews inventory identity, content digest,
count, and bytes. Execution requires the matching phrase and digest and reaches
a terminal state. Project deletion removes only its private Visual Studio
archive. It does not delete previously promoted Music Studio companions.

## Exclusions

- no automatic promotion, publication, or YouTube integration;
- no motion generation or LTX activation;
- no persistent service, listener, model process, scheduled task, or watcher;
- no background continuation after a Visual Studio operation returns;
- no editing of an already-generated candidate in place.
