# Blender Curated Asset Comparison A8 Brief

Status: human-approved implementation brief
Risk: medium owner-local compute and owner-local Visual Studio state

## Objective

Add one bounded Visual Studio study lane that demonstrates whether a reviewed,
locally installed Blender asset library materially improves Soul's scene
quality over the three retained procedural generations. The acceptance sample
is a 30-second night campfire scene rendered at 1280x720 and 30 fps.

The scene keeps the familiar circular ground slice, draws the camera farther
back, completes one closed orbit around the center, and contains a campfire,
rocks or boulders, several trees, a lit moon, and a star field. The exact A5,
A6, and A7 candidates remain available beside the A8 study for human visual
comparison.

## Reviewed asset sources

A8 accepts only the following explicit Poly Haven CC0 1K Blender assets:

- `island_tree_01` for the tree source;
- `boulder_01` for the rock source.

The committed registry pins every downloaded file by URL, byte count, and
SHA-256 digest. Installation is an explicit foreground Make target. It writes
only beneath `Soul/visual/assets/blender/polyhaven`, creates no service or
listener, and exits. A render never performs network access. Missing, extra,
symlinked, oversized, or digest-mismatched asset files fail closed.

The generated candidate records the asset-registry digest and exact asset
identities. Poly Haven attribution is shown in the Dashboard even though CC0
does not require it.

## Closed scene vocabulary

The manifest may select only reviewed asset IDs from the pinned registry and
may specify only bounded transform, instance count, and deterministic seed
values. It cannot provide arbitrary paths, URLs, Python, node graphs, drivers,
add-ons, or collection names.

The trusted adapter owns:

- importing the reviewed tree and boulder datablocks from the verified local
  files;
- deterministic placement on the circular ground slice;
- the procedural campfire, firelight, moon, stars, and one camera orbit;
- bounded audio response for firelight and atmosphere;
- all material and compositor behavior.

Assets remain editable in the retained `.blend`. Imported libraries are copied
into the candidate instead of linked to a mutable external library.

## Temporal contract

The existing 8- and 12-whole-bar loop modes remain unchanged. A8 adds one
separate closed value, `thirty_second_study`, which means exactly 900 frames at
30 fps. It is comparison evidence, not a whole-bar loop and not automatically
eligible for full-song repetition or publication binding.

The analyzer decodes only the first 30 seconds of the exact kept FLAC and does
not force its first and last envelope samples to match. The camera nevertheless
returns to its initial transform at the final frame. Candidate metadata must
say `temporal_mode: thirty_second_study`, `loop_state_equal: false`, and
`publication_eligible: false` truthfully.

## Exact comparison set

The first live A8 study is bound to the retained Glassroot Signal visual
project and its exact kept music candidate. Preview receives three exact prior
local candidate identities from the selected private project and binds each
candidate-record and preview digest into the new scope. Private project or
candidate identities are not committed to the public repository.

Visual Studio renders the four players together when every referenced artifact
still passes its recorded digest. A missing or changed baseline is reported;
Soul does not silently substitute a different candidate.

## Human gates and lifecycle

Preview still produces an exact digest-bound scope. One click approves only
that exact A8 candidate. Execution is foreground, uses the existing exclusive
AMD generation lease, preserves partial frames for explicit resume, and ends
as `blocked_for_human_review`, `failed`, `awaiting_input`, or `canceled`.

Review, deletion, revision, binding, export, upload, and publication gates are
not weakened. A8 study candidates cannot enter binding or publication until a
later human-approved promotion slice defines that behavior.

## Acceptance criteria

- The asset install plan and receipt pin exact CC0 sources, file sizes, and
  SHA-256 digests and reject drift.
- Runtime construction performs no network access and accepts no arbitrary
  asset path or executable content.
- The 30-second profile is distinct from 8/12-bar loop semantics.
- The A8 scene visibly contains the requested ground slice, stars, moon,
  orbiting camera, campfire, boulders, and multiple trees.
- The tree and boulder geometry comes from the verified curated library rather
  than Soul's primitive/procedural builders.
- Visual Studio shows the exact A5/A6/A7/A8 comparison set with playable local
  artifacts and truthful timing labels.
- Deterministic A1-A8 checks, companion/publication regressions, JavaScript and
  Python syntax checks, and `git diff --check` pass.
- One real 900-frame EEVEE render completes through the ordinary Visual Studio
  flow and remains pending human review.

## Explicit non-goals

- No arbitrary BlendKit, model-generated, user-selected, or network-fetched
  asset is accepted at render time.
- No free-form Geometry Nodes or Python execution is introduced.
- No automatic publication, binding, review, deletion, retry, or background
  continuation is introduced.
- No Cycles production animation, full-song render, or general-purpose asset
  browser is qualified in A8.
