# Blender Generated Asset Fidelity A9 Brief

Status: human-approved qualification brief
Risk: medium owner-local GPU compute and owner-private generated imagery

## Objective

Qualify how far Soul can improve one immutable, owner-private image-to-3D
character reconstruction before generated assets are admitted to Visual Studio's
production vocabulary. The study compares reconstruction variance, one bounded
higher-resolution geometry probe, semantic material treatment, scene polish,
and renderer quality while holding the character identity, pose, camera path,
duration, and review framing constant.

A9 produces comparison evidence only. It does not make a generated character
publication-eligible and does not generalize Visual Studio into an arbitrary
asset importer.

## Exact private source

The first study uses the locally retained winged-figure reconstruction whose
GLB digest is recorded in an owner-private qualification manifest. Public code
accepts no source path, URL, prompt, or model-generated Python. A trusted caller
supplies a manifest beneath the configured private generated-asset root; the
adapter verifies the declared asset identifier, byte count, SHA-256 digest,
schema, and bounded profile before Blender imports it.

The original image, generated meshes, textures, frames, and comparison videos
remain outside Git. Public review artifacts may record only non-secret profile
names, measurements, limitations, and redacted artifact identities.

## Qualification matrix

### Reconstruction search

- Generate up to five res-1024 candidates with explicit fixed seeds.
- Use the reviewed clean-alpha source and the pinned local TRELLIS runtime.
- Require GPU execution and fail rather than falling back to CPU.
- Record elapsed time, peak device-memory evidence when available, output
  digest, byte count, mesh metrics, and a deterministic four-angle review.
- Do not automatically select a winner. Machine evidence may rank candidates;
  human visual review chooses the retained source.

### Higher-resolution probe

- The only higher geometry profile is documented res-1536; res-2048 is
  prohibited.
- Run geometry-only first with a hard timeout and GPU-required behavior.
- Stop after one out-of-memory, invalid-output, or runtime-bound failure.
- A textured 1536 candidate may run only after the geometry probe records a
  valid result within the host's 16 GiB device-memory boundary.
- The existing res-1024 conditioning and texture-model limits are reported
  truthfully; A9 must not call a 4096 atlas or a larger input "2048 geometry."

### Blender fidelity treatments

The trusted adapter may apply only closed presets owned by the repository:

- normalized smooth shading and conservative normal treatment;
- deterministic spatial candidate masks for skin, hair, wings, cloth, and
  boots, producing separate Principled material instances that retain the
  verified source texture;
- bounded roughness, sheen, coat, and subsurface values per semantic role;
- a fixed layered star field with dim, medium, and hero populations;
- fixed warm, neutral, amber, and red light sources;
- one exact 360-degree camera orbit with no duplicate endpoint frame;
- AgX grading and one reviewed compositor-glow preset;
- 720p baseline and 1080p polished preview profiles.

Spatial material masks are candidates, not semantic truth. The four-angle
review must expose misclassified faces, waxy skin, merged feathers, texture
seams, and invented rear surfaces rather than hiding them.

## Renderer qualification

EEVEE remains the production preview renderer. A9 may probe Cycles only after
the exact Blender executable reports a usable Cycles engine and reviewed AMD
HIP device. The first Cycles test is limited to four still angles and a
two-second temporal sample at 720p, 64 then 128 samples, adaptive sampling, and
OpenImageDenoise with albedo and normal passes.

Missing Cycles or HIP support is a recorded unavailable capability, not a
reason to install or replace Blender automatically. No full-loop Cycles render
runs until a later human decision reviews the short comparison and measured
cost.

## Lifecycle and bounds

Each foreground study ends as `complete`, `failed`, `canceled`,
`awaiting_input`, or `blocked_for_human_review`. It performs no background
continuation, listener, service, watcher, or scheduled work.

The candidate limit is five 1024 reconstructions, one 1536 geometry probe, one
optional 1536 textured reconstruction, four stills per treatment, and one
12-second EEVEE comparison loop per approved treatment. Partial outputs are
retained for explicit inspection; retries require a new foreground invocation.

## Acceptance criteria

- Public code accepts only bounded presets and verified private manifests; no
  arbitrary asset path, URL, shader graph, Python, add-on, or command enters
  Blender.
- Res-2048 geometry is rejected and resolution, conditioning, atlas, and output
  dimensions remain distinct in receipts and UI-facing evidence.
- Candidate generation is fixed-seed, GPU-required, bounded, and records exact
  outputs without selecting a winner.
- Semantic material treatment visibly uses separate reviewed material roles
  while preserving the source texture and declaring spatial-mask uncertainty.
- The polished scene contains layered colored stars, fixed lighting, a closed
  360-degree orbit, AgX grading, and deterministic loop timing.
- Renderer probing fails closed when Cycles/HIP is unavailable.
- Deterministic A9 verification, existing Blender regressions, Python syntax,
  JSON validation, and `git diff --check` pass.
- Real generated and rendered artifacts remain owner-private and end blocked
  for human visual review.

## Explicit non-goals

- No automatic production promotion, publication, binding, upload, deletion,
  winner selection, or aesthetic approval.
- No unsupported res-2048 geometry, unbounded seed search, cloud generation,
  or CPU reconstruction fallback.
- No automatic retopology, rigging, character animation, procedural feather
  replacement, or human-base reconstruction in this slice.
- No arbitrary generated-asset browsing or file selection in Visual Studio.
- No persistent generation worker or overnight scheduler.
