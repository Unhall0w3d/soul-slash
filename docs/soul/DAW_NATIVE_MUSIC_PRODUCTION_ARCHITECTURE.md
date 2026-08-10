# DAW-Native Music Production Architecture

Status: research candidate for Operator review

## Objective

Create new Soul music projects as editable productions rather than only stereo
recordings. A project must preserve aligned audio tracks or stems, MIDI where
transcription or symbolic composition is useful, samples, tempo and meter,
markers, routing and effect intent, automation, exact source lineage, and a
reference mix. Localized revisions must leave unaffected material byte-exact.

Existing flattened songs are out of scope. This is a new-song production lane.

The quality target has two parts:

1. the first listening candidate should be comparable to or better than Soul's
   accepted ACE-Step stereo candidates; and
2. the production must become more controllable after generation, so a weak
   lyric, instrument, transition, or effect can be replaced without asking the
   model to reinterpret the entire song.

Neither target is assumed. Both require an A/B qualification.

## Research conclusions

### FL Studio is the native project authority

FL Studio's `.flp` format preserves native project state, but Image-Line does
not publish a supported external writer specification or standalone project
construction API. Soul must not reverse-engineer or directly generate `.flp`.
FL Studio itself creates the `.flp` and, when portability is needed, its Zipped
Project/Loop package containing the project and used samples.

The stable external contract is:

- aligned lossless WAV tracks or stems;
- Standard MIDI Files for notes and suitable controller data;
- captured and derived WAV samples;
- optional SFZ multisample instruments when the installed DirectWave edition
  supports third-party import;
- a DAW-independent Soul production manifest for tempo, meter, markers,
  routing, effects intent, automation, provenance, and hashes; and
- a reference mix.

FL Studio officially imports MIDI and audio. Its MIDI import supports track and
channel selection and time-signature import. Tempo-map, Playlist-marker, and
arbitrary automation round-tripping are not sufficiently documented to make
MIDI the sole authority, so Soul retains those in its manifest as well.

FL Studio's MIDI and Piano-roll Python interfaces run inside the application.
They may later reduce import work, but they are not a headless `.flp` writer and
are not required for the first accepted lane. Mouse-coordinate or menu-driving
automation is out of scope.

### The existing audio model remains useful

Soul currently uses ACE-Step 1.5 4B LM with the 2B Turbo Q8_0 DiT through the
pinned `acestep.cpp` Vulkan runtime. Turbo remains the first full-mix renderer:
it is already qualified on this host and provides the current musical quality
baseline.

The pinned runtime also supports ACE-Step Base tasks that Soul has not exposed:

| Task | Purpose | Turbo | Base |
| --- | --- | --- | --- |
| `text2music` | initial coherent full mix | yes | yes |
| `repaint` | replace a bounded time region | yes | yes |
| `extract` | isolate a named track from a mix | no | yes |
| `lego` | generate a named layer against existing backing | no | yes |
| `complete` | generate accompaniment around an isolated track | no | yes |

The supported track vocabulary includes vocals, backing vocals, drums, bass,
guitar, keyboard, percussion, strings, synth, effects, brass, and woodwinds.
The runtime warns that `lego` output isolation is model-dependent and remains
unverified in this codebase. A pilot must prove whether it returns a usable
isolated layer, a contaminated mix, or requires a following `extract` pass.
Each result receives one explicit disposition: `usable_isolated_track`,
`backing_contaminated_reference`, or `rejected`. Extraction is not a prerequisite
for the first FL-editable package; original aligned WAV layers and explicitly
non-isolated generated parts remain valid assets when labeled truthfully.

The first pilot should add the standard `acestep-v15-base-Q8_0` model. It is the
smallest architectural change and should fit the accepted RX 6900 XT Vulkan
lane. The larger XL Base Q4_K_M is a separate quality candidate: upstream
documents at least 12 GiB with quantization/offload, so this host's 16 GiB makes
it plausible but not production-safe without peak-memory, duration, quality,
and clean-unload evidence.

### Symbolic editability is selective

For isolated pitched instrument tracks, Spotify Basic Pitch can produce MIDI,
pitch bends, and note-event evidence on CPU. It is instrument-agnostic and
polyphonic but explicitly works best on one instrument at a time. Its output is
therefore a review candidate, not musical truth.

Do not force every track into MIDI:

- vocals, effects, ambience, expressive guitar, and complex textures generally
  remain audio;
- bass, keyboard, simple guitar, brass, woodwinds, and lead lines may offer an
  audio/MIDI pair after transcription review;
- drums begin as aligned audio; drum-to-MIDI is a later separately qualified
  specialist rather than a guessed onset map; and
- the original extracted or generated audio track is always preserved beside
  any editable MIDI interpretation.

This hybrid gives FL Studio note-level editability where it is credible without
discarding the audio model's timbre and performance.

## Soul Production Graph

Soul owns a versioned DAW-independent graph. FL Studio owns the human working
`.flp`. Neither silently overwrites the other.

```text
production.json
project/
  reference/
    reference-mix.wav
  tracks/
    drums.wav
    bass.wav
    guitar.wav
    vocals.wav
  midi/
    bass.mid
    keyboard.mid
  samples/
    source/
    derived/
    instruments/
  automation/
    track-id.parameter.csv
  markers.csv
  README.md
  checksums.sha256
```

The graph records:

- project identity, revision, parent revision, rights status, and model receipts;
- sample rate, bit depth, absolute duration, BPM/tempo events, key, PPQ, meter
  events, sections, and named markers;
- stable track IDs, roles, audio/MIDI/sample kind, clips, bar/beat/tick placement,
  gain, pan, fades, mute/solo intent, routing, sends, and buses;
- source asset and derivative hashes;
- logical effects and automation curves independent of a specific plugin;
- an edition-aware mapping from logical effects or instruments to reviewed FL
  Studio stock plugins and presets; and
- import and human-return receipts.

Tempo and bar locations are approved evidence, not assumed prompt compliance.
Soul measures candidate tempo and downbeats, records confidence and exact
48-kHz sample offsets, and asks the Operator to accept or correct the timebase.
The accepted receipt binds PPQ 960, tempo events, meter events, named markers,
and section boundaries. An FL import proof renders clicks placed on selected
bar markers and must reproduce their expected offsets within 48 samples (1 ms).

All aligned audio starts at project time zero, even if a track begins with
silence. Use 48 kHz, 24-bit WAV for FL interchange and retain Soul's FLAC master
and MP3 proxy separately. The reference mix never substitutes for the tracks.

## Stock FL Studio capability inventory

FL Studio edition and installed content determine which stock generators,
effects, presets, and sample libraries are available. After installation, Soul
must build an owner-local capability manifest containing:

- exact FL Studio version and edition;
- installed stock generators and effects;
- available factory sample and preset roots;
- DirectWave Player versus full DirectWave capability;
- shared host/Winboat exchange path;
- the Operator-approved stock instruments and effects Soul may target; and
- one tested import/render receipt per supported asset type.

The manifest is inventory, not permission to launch FL Studio or mutate a
project. Machine-specific paths and licensed content remain private.
Its exact SHA-256 digest is bound into every handoff. A plugin or preset mapping
is not called portable until the tested stock template reopens and renders under
the same version, edition, plugin inventory, and preset-root evidence.

DirectWave Player loads only DirectWave's own formats. Full DirectWave adds
sample editing and third-party program import, including SFZ and SoundFont2.
When full DirectWave is unavailable, Soul falls back to plain WAV samples and
Sampler Channels rather than manufacturing a proprietary preset.

## Sample Lab

Operator-authorized microphone or webcam-microphone capture becomes an
immutable source recording. Capture is one visible foreground operation with a
fixed maximum duration, selected input device, live indication, explicit stop,
and terminal receipt. No watcher or resident recorder is introduced.

Derived assets may include:

- trimmed and faded one-shots;
- seamless loops;
- transient slices for Slicex or a drum kit;
- tuned single-sample instruments;
- multisampled SFZ instruments where supported;
- stretched, reversed, filtered, denoised, layered, or pitch-shifted variants;
- granular textures intended for Fruity Granulizer; and
- a dry source plus effect-chain preview.

Transformations are represented as deterministic recipes with parameters and
hashes. AI may propose a recipe or classify the sound's likely musical role; it
does not silently open a capture device, destroy the source, or claim an
unreviewed derivative is production-ready.

FL Studio's stock surfaces align with this lane: Sampler Channel for one-shots,
Edison for recording/editing, Slicex for playable transient slices, Fruity
Granulizer for granular synthesis, and full DirectWave for multisamples. Soul
targets only the subset present in the capability manifest.

## Model and Core orchestration

Creative Core remains the correct audio-generation configuration:

- Qwen chat remains on NVIDIA;
- AMD is reserved for one bounded ACE-Step operation;
- Turbo renders the initial full mix;
- Base performs extraction, Lego layering, completion, or repainting;
- both models unload after the bounded operation; and
- no generation queue or always-resident music process is added.

FL Studio should not compete with active ACE-Step Vulkan inference. On the
expected Winboat deployment, project import, stock-plugin work, and rendering
occur after ACE-Step releases AMD. The installation slice must verify the
actual graphics/audio path rather than assuming concurrent use is harmless.
It records observed host and guest RAM/VRAM, Windows process GPU assignment,
shared-path ownership and atomic rename behavior, FL audio-device and offline
render success, and a negative concurrency assertion that no ACE-Step process
or AMD model allocation remains before FL Studio launches.

Composition planning is a separate phase. Soul or GPT-OSS Dev Core may turn the
approved musical conversation into a schema-valid production graph: sections,
chords, rhythmic roles, instrument plan, track entrances, automation intent,
and validation questions. That model never writes `.flp` or decides that an
audio/MIDI transcription is correct. The saved graph then enters Creative Core
for audio generation.

No new Core is required for A0. A future Production Core is justified only if
measured switching between planning, ACE-Step, and FL Studio becomes materially
confusing or error-prone.

## New-song production loop

```text
approved musical brief
  -> structured production graph and stock-instrument plan
  -> Creative Core Turbo reference mix
  -> human musical-quality gate
  -> Base extraction into selected aligned tracks
  -> optional Base Lego additions or bounded repaint
  -> optional per-track Basic Pitch MIDI candidates
  -> deterministic reference mix from preserved tracks
  -> FL Studio interchange package
  -> human opens/imports and saves the authoritative FLP/ZIP
  -> human exports changed stems/MIDI through a reviewed return package
  -> Soul reconciles only changed track IDs into a new graph revision
```

For a localized revision, Soul receives a stable track ID, time or bar range,
requested change, and exact parent revision. It creates an alternate audio
track, MIDI clip, sample, or automation curve. Unaffected artifact hashes must
remain identical. The result is an A/B patch package; it does not replace the
accepted parent or edit `.flp` directly.

## Phased qualification

### A0 — FL Studio interchange proof

1. Install FL Studio and record version, edition, deployment path, and shared
   exchange directory.
2. Inventory stock instruments, effects, samples, and DirectWave capability;
   hash the exact capability manifest.
3. Import a tiny synthetic package containing aligned WAV, MIDI notes and CC,
   tempo/meter/marker sidecars, and one static checksummed sample fixture.
4. Save `.flp`, create a Zipped Project/Loop package, reopen it, and render a
   reference WAV.
5. Complete an expected-import checklist distinguishing automatically imported
   fields from human-applied fields. Persist the exact mapping from Soul
   `track_id` to FL channel, Playlist lane, and Mixer lane.
6. Export a human-edited MIDI/stem return package with parent revision, FL
   version/edition, changed track IDs, source hashes, sample rate, render
   settings, and asset hashes. Ambiguous, renamed, added, missing, or re-rendered
   assets fail closed until the Operator explicitly reconciles them.
7. Verify observed Winboat GPU assignment, shared-path permissions and atomicity,
   FL audio/offline rendering, and absence of an ACE-Step process or AMD model
   allocation before launch.

### A1a — ACE-Step Base resource pilot

Pin the exact standard Base Q8_0 filename, revision, byte size, and SHA-256.
Run bounded 30- and 90-second fixtures and record peak AMD VRAM, host RAM, wall
time, exit status, and process/model cleanup. Three sequential runs must return
within 256 MiB of the pre-run AMD allocation and 512 MiB of pre-run host memory
after cache settlement. Cancellation and a forced model failure must remove
partial outputs and leave no resident ACE-Step process.

Optionally pilot XL Base Q4_K_M afterward. Promote it only if it materially
improves human-rated output without unsafe memory pressure or excessive delay.

### A1b — ACE-Step audio-editability pilot

Against a controlled owned multitrack fixture and new 30–90 second instrumental
and vocal-led candidates, test `extract`, `lego`, `complete`, and regional
`repaint`.

- Raw output duration may differ from its source by no more than 10 ms. Any
  deterministic pad, trim, or correlation-based offset correction is retained
  in the manifest; canonical tracks then have exactly the project sample count.
- Selected onset/bar alignment must be within 10 ms before correction and 1 ms
  after applying the recorded offset.
- On the controlled fixture, extraction must improve target-to-interference
  SI-SDR by at least 6 dB over the input mixture. Production candidates also
  require a human solo-isolation rating of at least 3/5.
- A summed-track reconstruction must retain the exact accepted duration, remain
  below 0 dBFS, fall within 2 LU of the Turbo reference before final gain
  matching, and receive a human musical-usability rating of at least 3/5.
- Every Lego result receives `usable_isolated_track`,
  `backing_contaminated_reference`, or `rejected`; contaminated output cannot be
  presented as an editable stem.

Use a fixed brief, fixed source, and fixed seeds where the task accepts a seed.
Randomize labels for a human-blinded Turbo-reference versus structured-render
A/B. The structured candidate must score at least 3/5 on musical coherence,
sound quality, arrangement, and mix, and may not trail Turbo by more than 0.5 in
mean score. Turbo remains the quality authority; the summed-track render is a
separately rated editability candidate and never silently replaces it.

### A2 — Production graph and package writer

Add closed schemas, immutable lineage, track manifests, aligned WAV/MIDI/sample
packaging, checksums, and deterministic validation. No FL Studio invocation.

### A3 — Stock template and import bridge

Create one human-authored FL Studio template using only inventoried stock
plugins, stable mixer lanes, buses, and macro parameters. First accept a manual
supported import. Then evaluate an in-application FL Studio script for reducing
repetitive note/marker import. Do not add external `.flp` writing or GUI driving.

### A4 — Sample Lab

Add bounded capture, source preservation, deterministic derivation recipes,
Sampler/Slicex/Granulizer packages, and optional SFZ output when supported.

### A5 — Localized revision and reconciliation

Create alternative takes for one track or time range, preserve all unaffected
hashes, render A/B references, ingest a human-return package, and record an
explicit reconciliation decision.

### A6 — Dashboard and conversational skills

Expose Editable Production as a new Music Studio mode. Soul gathers missing
inputs, explains Core needs, reports each bounded phase, produces the FL handoff,
and links returned candidates. Destructive project removal and final publication
retain their existing human gates.

## Acceptance measurements

- FL Studio opens the package using documented import surfaces.
- The FL-authored `.flp` and ZIP reopen with no missing stock assets.
- Initial reference quality is not materially worse than current Turbo output.
- The blinded A1b protocol meets its declared per-dimension and mean-score
  thresholds; a failed structured render leaves Turbo authoritative.
- Extracted/generated tracks remain sample-aligned for the entire song.
- The summed track reference is musically usable and exposes measured bleed or
  reconstruction differences rather than hiding them.
- Reviewed MIDI is rhythmically and harmonically credible for the selected stem.
- One localized edit changes only its declared artifacts and reference render.
- One human FL Studio edit returns without losing lineage or overwriting Soul's
  accepted parent.
- The accepted timebase receipt and FL click render agree within 48 samples at
  selected bar markers.
- Capture ends visibly and leaves no resident process.
- Every model and FL invocation is bounded, foreground, and receipt-backed.

## Explicit non-goals

- reverse-engineering or directly writing `.flp`;
- screen-coordinate, mouse, or menu automation;
- retrofitting existing flattened projects;
- pretending source separation is the same as original multitrack recording;
- converting every expressive audio part into MIDI;
- silently using unavailable plugins or licensed factory content;
- keeping FL Studio, a recorder, or a music model resident; or
- promising higher musical quality before the human A/B qualification.

## Primary references

- [FL Studio project formats](https://www.image-line.com/fl-studio-learning-content/fl-studio-online-manual/html/fformats_project.htm)
- [FL Studio audio and MIDI export](https://www.image-line.com/fl-studio-learning-content/fl-studio-online-manual/html/fformats_save_export.htm)
- [FL Studio MIDI import](https://www.image-line.com/fl-studio-learning-content/fl-studio-online-manual/html/automation_midiimport.htm)
- [FL Studio MIDI scripting](https://www.image-line.com/fl-studio-learning-content/fl-studio-online-manual/html/midi_scripting.htm)
- [FL Studio Piano-roll scripting](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/pianoroll_scripting_api.htm)
- [FL Studio Sampler Channel](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/chansettings_sampler.htm)
- [FL Studio DirectWave](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/plugins/DirectWave.htm)
- [FL Studio Edison](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/plugins/Edison.htm)
- [FL Studio Slicex](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/plugins/Slicex.htm)
- [FL Studio Fruity Granulizer](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/plugins/Fruity%20Granulizer.htm)
- [ACE-Step 1.5 tutorial](https://github.com/ace-step/ACE-Step-1.5/blob/v0.1.8/docs/en/Tutorial.md)
- [Pinned acestep.cpp task architecture](https://github.com/ServeurpersoCom/acestep.cpp/blob/7eb27775fd110a8b2503ac089aedcc02416caa0a/docs/ARCHITECTURE.md)
- [ACE-Step 1.5 GGUF model family](https://huggingface.co/Serveurperso/ACE-Step-1.5-GGUF/tree/main)
- [Spotify Basic Pitch](https://github.com/spotify/basic-pitch)
