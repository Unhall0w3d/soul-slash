# Blender Music-Visual Pipeline Architecture

Status: A1–A5 accepted and merged; A6 visual-fidelity expansion is in progress for Operator review.

## Decision

Blender is a credible third Visual Studio production lane beside the existing
local still and generated-motion lanes. Its best first use is not unrestricted
text-to-3D or character animation. It is controlled, reusable, audio-reactive
scene construction: liminal environments, abstract machinery, impossible
architecture, procedural voids, animated materials, particles, lighting, and
camera paths that can be revised without regenerating every visual decision.

The lane should be described as **Blender Scene** in Visual Studio. It may
produce a still, a short seamless loop, or a full rendered sequence. The
existing FLUX and Wan/FastWan paths remain available when diffusion is the
better fit.

## Why this belongs in Soul

The current motion lanes are effective at producing a visual impression, but
they do not provide durable control over scene geometry, camera placement,
lighting, object identity, or a specific motion channel. Blender can preserve
those elements as editable scene state. This makes requests such as these
meaningfully bounded:

- keep the environment and change only the camera path;
- preserve the camera and make the cyan structure react to the kick;
- slow the portal rotation without changing the lighting;
- render the same scene at a new aspect ratio;
- replace one material or prop while retaining the accepted composition.

It also gives the music-companion pipeline a better route to coherent loops.
A loop can occupy an exact number of musical bars rather than an arbitrary
number of seconds, then repeat through the existing full-duration mux and
publication flow.

## What Blender does not solve automatically

Blender is a renderer and creation environment, not a text-to-scene model.
Soul still needs a scene vocabulary, asset policy, composition logic, and
review loop. High-quality characters, organic creatures, facial performance,
rigging, and natural animation require suitable models, rigs, animation data,
or substantial manual work. Those are not appropriate first acceptance cases.

The initial lane should favor procedural and environmental work where a small
allowlisted vocabulary can produce deliberate results:

- primitive and generated geometry;
- curves, volumes, particles, and geometry-node presets;
- reviewed local meshes and textures;
- bounded material-node templates;
- cameras, lights, fog, depth, and color treatment;
- keyframed or baked transforms and shader values.

## Trust boundary

Blender embeds Python, and Blender documentation warns that Python is not
restricted in what it can do. Soul must therefore not execute arbitrary Python
written by a model, accept an untrusted `.blend` as executable input, or enable
automatic script execution for downloaded project files.

The safe design is:

```text
Operator intent + reviewed music evidence
                  |
                  v
       Soul Scene Manifest (JSON)
                  |
      schema, ranges, assets, digest
                  |
                  v
        trusted Blender adapter
                  |
                  v
      .blend + frame/image output
                  |
                  v
       Visual Studio human review
```

The manifest is a closed scene description. It names only supported object,
material, light, camera, animation, and audio-binding operations. A
repository-owned adapter translates those values through Blender's data-block
API. Unsupported fields fail closed. Imported assets are hashes and contained
paths, not scripts. Python auto-execution remains disabled.

## Proposed manifest

The first schema should retain at least:

- project, revision, parent, and exact music-candidate identities;
- Blender version and renderer profile;
- width, height, FPS, frame range, duration, and loop seam policy;
- deterministic random seed;
- scene palette and world settings;
- allowlisted objects, assets, transforms, materials, lights, and camera;
- animation channels and keyframes;
- music bindings expressed as precomputed values or curves;
- output and retention policy;
- input, asset, manifest, `.blend`, frame-set, and video digests.

Model output may propose this manifest. Deterministic code validates and
normalizes it. The existing exact-preview and confirmation pattern remains the
authority to execute a render.

## Music-reactive animation

Soul should analyze the accepted music artifact outside Blender and persist a
small, reviewable animation evidence set rather than asking Blender to infer
meaning during every render. Useful inputs include:

- tempo, meter, beat, and bar positions;
- accepted section markers;
- low-, mid-, and high-band envelopes;
- transient/onset events;
- overall loudness and energy curves.

The manifest maps those inputs to allowlisted animation targets. For example,
low-band energy may control emission intensity, kick events may trigger a
geometry pulse, and section markers may change lighting state or camera speed.
The mapping is editable and does not change the source music.

A perfect seamless loop needs both the scene state and its animation state to
agree at the seam. The initial qualifier should use a loop length expressed in
whole musical bars and validate the first/last state before full-duration
composition.

## Render and hardware policy

Use one pinned Blender LTS version for a qualified project family. Blender's
official production guidance notes that version changes can affect production
results and recommends a single LTS version for a project.

At the time of this review, Atelier already reports the Arch package
`blender 17:5.2.0-4` at `/usr/bin/blender`; the binary identifies itself as
Blender 5.2.0 LTS. That makes the installed build the sensible first A0
candidate, but it remains inventory evidence only. A0 must record its exact
binary and runtime capabilities before Visual Studio trusts it.

The recommended first renderer is EEVEE because short stylized music visuals
need rapid iteration more than physically accurate ray tracing. Cycles remains
an optional final-quality profile after an A/B review proves that its visual
gain justifies the runtime.

The RX 6900 XT is the preferred render device. Blender 5.0 officially supports
HIP on Linux for RDNA1 and newer cards, including the RX 6000 series. The GTX
1070 may be qualified as a CUDA fallback, but its lower memory and lack of RTX
hardware make it the secondary path.

This does not require a new Core initially. The render should use the existing
exclusive AMD creative-resource lease while Soul is in an AMD-available state.
ACE-Step, FLUX, Wan/FastWan, and Blender must not compete for the AMD device.
The resource panel should identify the exact Blender renderer and device while
the foreground job is active.

## Bounded render contract

Each Blender operation remains one finite foreground job with:

- an explicit frame range, resolution, FPS, and timeout;
- one contained project/output root;
- no daemon, watcher, resident server, or background queue;
- cancellation that terminates the Blender process and records partial frames;
- an explicit terminal state of `complete`, `failed`, `canceled`, or
  `blocked_for_human_review`;
- failure on missing frames, invalid assets, non-zero exit, timeout, GPU OOM,
  manifest drift, or encoder failure;
- cleanup rules that distinguish resumable frames from failed disposable data.

Blender supports background rendering and exact frame ranges. The lane should
render PNG or OpenEXR frames first, verify completeness, then encode the video.
Frame sequences make cancellation, resume, and partial-failure evidence much
safer than rendering directly to a single movie file.

## Artifact package

An accepted Blender candidate should preserve:

```text
scene.json
scene.blend
assets/
audio-analysis.json
render-receipt.json
preview.webm or preview.mp4
checksums.sha256
```

Final frame sequences may be retained until review/export and then handled by
an explicit retention policy. Eligible textures may be packed into `.blend`,
but Blender cannot pack every heavy external resource, so the manifest and
asset directory remain authoritative.

## Visual Studio integration

The existing pipeline already provides the needed control points:

1. Visual Studio stores immutable projects, revisions, candidates, and human
   review.
2. The AMD generation lease prevents overlapping creative renders.
3. Music binding accepts one exact reviewed visual artifact.
4. Full-duration companion rendering repeats or composes the reviewed motion
   against the exact music candidate.
5. Publication packaging and YouTube upload remain separate explicit gates.

The Blender lane should add its own operation family and artifact kind rather
than masquerading as Wan/FastWan output. It may reuse the existing review,
binding, final companion, and publication layers after their source-kind checks
are deliberately extended.

## Implemented qualification slices

### A0 — installation and capability proof

- Pin a Blender LTS release and record binary/version identity.
- Inventory EEVEE and Cycles devices without changing persistent preferences.
- Prove RX 6900 XT rendering and inspect the GTX 1070 fallback.
- Render one repository-owned fixture in background mode.
- Measure startup, elapsed time, peak VRAM/RAM, exit, and cleanup.

### A1 — closed scene manifest and trusted adapter

- Define the smallest scene schema and strict validator.
- Construct a camera, world, lights, materials, and a few procedural objects
  through a repository-owned adapter.
- Produce a deterministic `.blend` and low-resolution still.
- Reject unknown operations, unsafe paths, embedded scripts, and manifest drift.

Implemented. The closed manifest caps objects, materials, lights, animation
channels, supported primitives, scalar/vector ranges, exact IDs, safe output
names, and strictly increasing frame positions. The repository-owned adapter
constructs data blocks without accepting paths, scripts, drivers, add-ons,
node programs, or downloaded `.blend` input.

### A2 — bounded loop and music-reactive proof

- Analyze one reviewed music candidate into bounded curves.
- Render one 8- or 12-musical-bar, 24 or 30 FPS EEVEE loop.
- Qualify seam continuity, cancellation, partial-frame resume, and encoding.
- Compare EEVEE with one bounded Cycles render before offering Cycles publicly.

Implemented for EEVEE. Soul decodes the exact kept FLAC into bounded low,
mid, high, energy, and kick evidence outside Blender, validates equality at
the loop boundary, renders PNG frames, verifies completeness, and only then
encodes the MP4 with the exact source audio. Failed partial frame sets are
retained for one explicit bounded resume. Cycles remains inventoried but is
not offered by the Dashboard.

### A3 — Visual Studio candidate lifecycle

- Add Blender Scene project/preview/execute/review/revision operations.
- Expose renderer, device, progress, frame evidence, and terminal state.
- Preserve exact source, revision, asset, and render lineage.

Implemented as an additive full-width Visual Studio lane with closed template,
kept-song, whole-bar, quality, seed, and retained-direction controls. It
supports preview, exact execution, review, immutable revision, retained-frame
resume, private artifact delivery, binding, and deletion.

### A4 — Music binding and publication

- Bind one kept Blender candidate to one kept music candidate.
- Reuse the full-duration companion and upload-package gates.
- Prove thumbnails, MP4/WebM compatibility, description lineage, and cleanup.

Implemented. One kept Blender candidate may be copied into only its exact kept
music lineage. The existing full-duration mux and private YouTube package
gates accept the reviewed MP4 loop, derive a thumbnail when no still binding
exists, and preserve Blender, music, and publication digests.

### A5 — templates and conversational collaboration

- Add reviewed scene templates for abstract, liminal, architectural, and
  audio-reactive work.
- Let Chat gather missing scene decisions and draft a manifest without silently
  rendering.
- Keep character rigs, arbitrary add-ons, downloaded `.blend` auto-execution,
  and unrestricted Python outside the supported lane.

Implemented as five reviewed construction families: abstract, liminal,
architectural, Soul-themed audio-reactive chamber, and bioluminescent grove.
The shared capability catalog teaches Chat and Voice what Blender Scene can
do and which inputs it needs, but first-generation Blender construction stays
an explicit Visual Studio action. Creative-direction prose is retained as
review/revision evidence; the current closed templates, not model-written
Python, determine geometry. Conversational scene-manifest compilation remains
a future separately qualified expansion.

## Reference visualizer assessment

The three Operator-selected DROELOE visualizers establish a useful complexity
ladder rather than one all-or-nothing target:

- *Downside Up* and *Landscape* use stylized low-poly terrain, celestial
  bodies, geometric structures, strong color scripting, and deliberate camera
  motion. That visual language is achievable with the current closed
  procedural vocabulary and richer template authoring.
- *Feeble Games* adds a dense authored bioluminescent forest, painterly
  foliage, varied silhouettes, and a travel-through-environment composition.
  The current grove template can reproduce the broad mood and reusable scene
  logic, but not that exact richness. Comparable fidelity will require a later
  reviewed asset lane for local meshes, curves, foliage, and textures rather
  than weakening the adapter to accept arbitrary files or Python.

This boundary is intentional: the A5 lane is useful today, source-editable,
and safe to iterate, while richer authored asset packs can extend visual
quality without replacing its lineage and approval model.

## First recommended experiment

Create one Soul-themed impossible architectural chamber using primitive and
procedural geometry, restrained fog, copper and cyan materials, one looping
camera move, and three music-derived animation channels. Render an eight-second
1920x1080 24 FPS EEVEE preview on the RX 6900 XT. Cancel once, resume the missing
frame range, encode only after frame completeness, and repeat the run with the
same manifest to compare artifact and visual stability.

That experiment answers the important questions without pretending Blender is
already a general scene-generation system.

## Primary references

- Blender 5.0 command-line arguments:
  <https://docs.blender.org/manual/en/5.0/advanced/command_line/arguments.html>
- Blender Python API quickstart:
  <https://docs.blender.org/api/dev/info_quickstart.html>
- Blender scripting and security:
  <https://docs.blender.org/manual/en/5.0/advanced/scripting/security.html>
- Blender Cycles GPU rendering:
  <https://docs.blender.org/manual/en/5.0/render/cycles/gpu_rendering.html>
- Blender production deployment guidance:
  <https://docs.blender.org/manual/en/dev/advanced/deploying_blender.html>
- Blender render output and frame-sequence documentation:
  <https://docs.blender.org/manual/en/4.5/render/output/index.html>
- Blender packed external data:
  <https://docs.blender.org/manual/en/4.5/files/blend/packed_data.html>
