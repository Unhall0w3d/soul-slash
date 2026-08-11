# Blender curated asset comparison A8 — human review packet

## Candidate state

Candidate-complete and awaiting Operator visual review. This is not approval to
merge, promote the curated vocabulary into production templates, bind the
study to Music Studio, render it to full song duration, or publish it.

## What was implemented

- one exact 30-second, 900-frame, 720p30 Blender comparison mode;
- an orbital campfire composition with a continuous camera move, procedural
  campfire, moon, stars, and audio-reactive light;
- three reviewed Poly Haven CC0 `island_tree_01` instances and four reviewed
  Poly Haven CC0 `boulder_01` instances;
- a closed registry pinning all 15 required 1K asset files by URL, byte count,
  and SHA-256;
- explicit foreground plan, install, and verify commands;
- one reviewed `bpy.data.libraries.load` boundary that can append only two
  fixed datablock names from the verified local registry;
- a four-way Visual Studio comparison against three exact earlier Blender
  candidates, with all candidate and preview digests retained; and
- explicit comparison-only enforcement: no binding, full-duration expansion,
  upload package, or publication.

## Files changed

The candidate changes the Blender manifest, analysis, adapter, service,
application contract, Visual Studio surface, deterministic verifiers, setup
targets, current-state documentation, Visual Studio guide, and seeded project
timeline. The asset payload itself remains private ignored local state under
`Soul/visual/assets/blender/polyhaven` and is not committed.

## Commands and deterministic results

- `make blender-curated-assets-plan` — passed; exact foreground plan produced.
- `make blender-curated-assets-install ...` — passed; 15 reviewed files
  installed locally.
- `make blender-curated-assets-check` — passed; 15 files, 89,224,553 bytes,
  registry digest `14dd59f84f215fa6564d057f6fea2c560ca4daa80771b60b25d44d12416324d3`.
- `make verify-blender-scene-a1-a8` — passed, including all legacy A1–A7,
  publication, companion, registry, rejection, and A8 checks.
- `node --check assets/dashboard/dashboard.js` — passed.
- JSON parsing for the template, registry, and tracker catalogs — passed.
- `git diff --check` — passed.

## Live qualification evidence

The ordinary `BlenderSceneService` preview and exact execute path generated one
private candidate from one retained `keep`-reviewed song. It constructed and
packed the `.blend`, rendered all 900 frames, encoded the first exact 30 seconds
of candidate audio, and terminated as `blocked_for_human_review`.

- resolution and rate: 1280×720 at 30 fps;
- frames: 900/900;
- duration: 30.0 seconds;
- wall interval: approximately 14 minutes 52 seconds;
- temporal evidence: `loop_state_equal: false`;
- candidate publication evidence: `publication_eligible: false` and
  `external_publication: false`;
- artifacts: verified scene manifest, packed editable `.blend`, still,
  audio-analysis evidence, and MP4 preview; and
- Dashboard acceptance: the selected Visual Studio project displayed the new
  A8 player plus three digest-bound baseline players, labeled the candidate
  `bounded comparison · not publishable`, and disabled binding.

## Local LLM evaluation

Not applicable. A8 adds deterministic rendering and UI behavior; no model text
is used to decide asset identity, file path, safety, authorization, comparison
lineage, or publication eligibility.

## Memory and lifecycle

- shared Soul memory keys added or changed: none;
- lifecycle states touched: `blocked_for_human_review`, `awaiting_input`,
  `failed`, and `complete` for bounded preview/install/verify/render outcomes;
- no skill-private memory, service, daemon, listener, watcher, scheduled task,
  automatic retry, or background continuation was added.

## Risk classification

Moderate local creative-compute and supply-chain risk. The asset source is
public, but the committed allow-list, exact file digests, explicit installer,
realpath/symlink checks, extra-file rejection, fixed datablock names, private
packing, and nonpublishable comparison gate keep that risk bounded.

## Known weaknesses

- The three trees intentionally reuse one reviewed asset; asset variety is not
  yet demonstrated.
- A mathematically smooth orbit can pass behind foreground trees. That proves
  real spatial parallax and close texture fidelity, but also shows why a later
  shot director needs explicit occlusion planning.
- The campfire, moon, and stars are trusted procedural approximations rather
  than curated or simulated production effects.
- A 900-frame review render took nearly 15 minutes on the qualified host. This
  is bounded and resumable, but should not be presented as an instant action.
- Full-song non-repeating visual direction is intentionally deferred until the
  Operator decides whether A8 is materially better than A5–A7.

## Human review checklist

- [ ] Play all four comparison candidates in Visual Studio.
- [ ] Decide whether tree and boulder fidelity is materially improved.
- [ ] Evaluate whether the continuous orbit is preferable to the short loops.
- [ ] Evaluate campfire, moon, stars, lighting, and audio response separately
  from the imported asset quality.
- [ ] Decide whether foreground occlusion is acceptable evidence or requires a
  revised comparison before promotion.
- [ ] Approve, request revision, or reject A8.
- [ ] Separately approve merge if the candidate is accepted.
