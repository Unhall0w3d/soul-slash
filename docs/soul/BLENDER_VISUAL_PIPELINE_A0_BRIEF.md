# Blender Visual Pipeline A0 — Runtime and Bounded Fixture Qualification

Status: Operator-authorized implementation candidate

Authorization date: 2026-08-09

## Outcome

Qualify Atelier's existing Blender 5.2.0 LTS package as a candidate foreground
renderer for the planned Blender Scene Visual Studio lane. A0 inventories the
runtime without saving preferences, renders one repository-owned EEVEE fixture,
proves bounded process termination and split-frame continuation, and records an
immutable technical receipt for human review.

A0 does not add a Dashboard action, accept a model-authored scene, bind output
to Music Studio, enable Blender auto-execution, install an add-on, or promote
Blender as a supported production renderer.

## Adopted fixture

The fixed technical fixture is intentionally small:

```text
renderer: EEVEE
canvas: 640x360
frames: 24
delivery: 24 fps PNG sequence plus H.264 MP4 preview
scene: repository-owned Soul copper/cyan procedural chamber
execution: Blender background mode, factory startup, offline mode, autoexec off
```

The trusted builder uses fixed Blender data blocks, saves one `.blend`, and
contains no external asset, driver, downloaded script, network request, or
extension dependency.

## Exact gate

The runtime CLI exposes only:

```text
check -> complete
plan -> blocked_for_human_review
run -> blocked_for_human_review / failed / canceled
```

`plan` binds the exact Blender binary and digest, adopted version, manifest,
trusted fixture and probe digests, output profile, and confirmation phrase.
`run` rejects stale or mismatched approval.

## Resource and process boundary

- The run acquires the existing exclusive `amd-vulkan-generation` lease.
- Blender and FFmpeg run in bounded process groups.
- Timeout or interruption terminates the complete child process group.
- The first and second halves of the frame sequence are separate exact ranges.
- Encoding starts only after all 24 regular PNG frames exist.
- Partial run state is removed on failure or cancellation.
- No daemon, service, watcher, listener, schedule, queue, or automatic retry is
  created.

## Security boundary

- `--disable-autoexec` remains set for probe, build, and render operations.
- `--offline-mode` and `--factory-startup` isolate the technical fixture from
  owner preferences and online extensions.
- Only the repository-owned probe and fixture scripts may be passed to
  Blender's Python entrypoint.
- The created `.blend` is loaded with auto-execution disabled.
- Output paths must remain inside the selected non-symlink run root.

## Technical acceptance

- the Blender binary is a regular executable and matches the adopted version;
- startup contains no Python exception or traceback;
- the probe identifies background mode, EEVEE, active GPU identity, and
  available Cycles devices without saving preferences;
- the trusted fixture creates a regular `.blend`;
- two bounded frame ranges produce exactly 24 regular PNG frames;
- FFprobe validates the preview dimensions, frame rate, and duration;
- the receipt retains binary, script, scene, frames, and preview digests plus
  elapsed time and device evidence;
- timeout verification leaves no child process, partial directory, or active
  AMD lease.

## Human gate

Technical success ends at `blocked_for_human_review`. The Operator reviews the
fixture preview and receipt. A1 scene-manifest work remains separately gated.

## Completion boundary

A0 is candidate-complete when its deterministic verifier passes and one live
fixture receipt is available for review. A clean startup and live render are
required; a successful process that emits a startup traceback is not qualified.
