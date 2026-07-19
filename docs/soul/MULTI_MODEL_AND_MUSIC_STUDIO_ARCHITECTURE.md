# Multi-Model and Music Studio Architecture

## Current production decision

Soul should not become a pile of always-loaded models. The practical topology
for this host is one selected chat model plus manually invoked foreground
specialists:

| Hardware lane | Primary role | Mutually exclusive roles |
| --- | --- | --- |
| RX 6900 XT, 16 GiB, RADV Vulkan | Gemma 4 12B Daily chat | ACE-Step 1.5 4B LM / 2B Turbo foreground Music Core, future qualified vision specialist |
| GTX 1070, 8 GiB, CUDA compute 6.1 | Qwen3 8B reserve chat in Music and AMD-Free Cores | Future bounded speech/OCR specialists |
| Ryzen 7 5800X and 62 GiB RAM | Ruby control plane, storage, audio metadata, post-processing | CPU Whisper transcription and future bounded specialists |

Daily Core keeps Gemma on AMD and leaves NVIDIA available. Music Core is an
explicit, previewed Core transition: Qwen becomes chat on NVIDIA and ACE-Step
claims AMD only for a foreground generation. The music model exits when the
operation terminates. AMD-Free keeps Qwen chat and leaves AMD to the Operator.
Music never triggers an unapproved Core switch. A visible conversational
generation action may include the exact Music Core transition authorized by the
same click; Soul revalidates active work and does not independently decide to
evict a chat engine.

No always-running small routing model is justified yet. Deterministic Ruby
routing is faster, inspectable, and already authoritative. A specialist earns a
profile only after a measured task demonstrates material value.

## Host evidence

Read-only inspection on 2026-07-17 found:

- AMD Radeon RX 6900 XT under Mesa RADV 26.1.4;
- NVIDIA GeForce GTX 1070, 8,192 MiB, compute capability 6.1;
- NVIDIA driver 580.173.02 and CUDA toolkit 12.9;
- AMD Ryzen 7 5800X, 8 cores / 16 threads;
- 62 GiB RAM and 62 GiB swap;
- FFmpeg 8.1.2 and Rubber Band 4.0.0;
- Ollama and Ollama Vulkan installed but inactive and unnecessary for this
  music pilot.

## Historical candidate assessment

The following sections preserve the original NVIDIA/Python pilot rationale and
acceptance evidence. They are not the current production topology. The accepted
production lane is the pinned native Vulkan backend described in
`GEMMA_AND_VULKAN_PRODUCTION_PROMOTION_BRIEF.md` and
`MUSIC_CORE_VULKAN_FEASIBILITY_REVIEW.md`.

### Lead: ACE-Step 1.5 turbo / 2B on NVIDIA

ACE-Step 1.5 is the strongest first pilot because the official project supports
10-second to 10-minute generation, lyrics, reference audio, BPM/key/time
signature controls, repainting, extension, stem separation, and audio
understanding. Its current release documents CUDA, ROCm, MPS, Intel, and CPU
paths, low-VRAM modes, and a legacy-CUDA correction relevant to Pascal GPUs.

The first configuration should use the 2B turbo DiT, smallest suitable planner
LM, batch size one, quantization/offload, and one foreground CLI invocation.
The project's low-memory claims are not host acceptance evidence. The complete
pipeline includes approximately 4.7 GB of 2B DiT weights plus planner, VAE,
working buffers, and decoded audio. The 8 GiB GTX must prove:

- model load and clean unload;
- 30-second instrumental generation;
- 90-second structured generation;
- 150–180-second song generation;
- peak VRAM/RAM and wall time;
- usable audio rather than NaN, silence, or noise;
- deterministic cancellation and partial-output cleanup;
- no effect on AMD chat responsiveness.

Pin an exact upstream release and weight digest at A1. Disable update checks,
automatic downloads, Gradio, REST serving, sharing, and batch generation.

### Comparison: DiffRhythm 1.2

DiffRhythm provides fixed 95-second and 285-second full-song models, text or WAV
reference paths, and an Apache-2.0 code/weight release. Its documented minimum
is 8 GiB with chunking, leaving no comfortable GTX headroom. It is a useful
quality/structure comparison after ACE-Step, preferably as an isolated AMD or
CPU-offload experiment only after a separate review. It is not the lead
integration because the RX lane currently owns conversation and the project has
less complete iteration/editing ergonomics.

### Deferred controls

- YuE can produce and continue full songs, but the official full-generation
  path historically targets much larger GPUs. Community quantized 8 GiB paths
  add complexity and are not the first reliable integration.
- MusicGen is useful for short text/melody studies, but official medium-model
  guidance recommends 16 GiB and its core workflow is short-sequence oriented.
- ACE-Step XL requires at least 12 GiB with offload and 20 GiB is recommended.
  It does not fit the GTX lane and would displace chat on AMD.
- An AMD ROCm ACE-Step path is experimental. ACE-Step documents an RX 6900 XT
  override, but AMD's supported Radeon Linux matrix excludes this card and
  Arch. Do not replace the working RADV/Vulkan conversation stack for A1.
- The community GGML/Vulkan ACE-Step path is promising, but it must be reviewed
  and benchmarked separately from the official Python/CUDA pilot.

## Music Studio product model

Music Studio should be a project workspace, not a single prompt box.

### Project surface

Each project exposes:

- title, intent, target duration, instrumental/vocal mode, and rights status;
- a musical brief: genre concepts, era, mood, energy curve, instrumentation,
  vocal qualities, BPM, key, meter, song structure, and exclusions;
- lyrics with named sections and revision history;
- lawful references and extracted descriptors;
- generation candidates with seed, exact model profile, parameters, duration,
  resource receipt, and waveform/audio preview;
- A/B notes, ratings, selected lineage, repaint/extend operations, and exports;
- a concise conversation thread scoped to the project through shared Soul
  context rather than a music-private memory store.

The first dashboard version should favor clear controls and iteration history
over a DAW imitation. A waveform/timeline becomes useful for repainting, but a
full multitrack editor is later work.

### Audio artifact policy

Every completed generation produces two linked artifacts from one model run:

- a 48 kHz stereo FLAC as the canonical, lossless candidate master; and
- an MP3 listening proxy for smaller dashboard playback, LAN transfer, and
  convenient sharing.

The MP3 is encoded from the retained FLAC in a bounded foreground post-process;
it is never a second model generation and never replaces or deletes the master.
The A2 schema records both paths, byte sizes, SHA-256 digests, codec details,
encoder version, and exact arguments. The initial recommended proxy is LAME V2
variable bitrate, subject to measured browser compatibility and owner review in
the A2 brief. A generation reaches `complete` only after both artifacts validate;
an encoding failure remains explicit and preserves the valid FLAC for review.

### Storage

Private project material belongs under an ignored local root:

    Soul/music/projects/<project-id>/
      project.json
      inputs/
      generations/
      reviews/
      exports/

Repository code contains schemas and examples only. Audio, lyrics, private
notes, reference files, generated stems, and model caches are never committed.
Project records are task artifacts, not durable personality memory. Stable user
preferences may enter the existing shared memory layer only through its normal
review controls.

## Reference and research boundary

Soul must distinguish three inputs:

1. Musical concepts: researched descriptions of genre, structure, production,
   instrumentation, harmony, rhythm, and historical context with sources.
2. Private inspiration notes: artist/song names the operator uses to explain a
   target. These are not automatically sent to a generator.
3. Reference audio: an exact local file the operator affirms they own, created,
   licensed, or otherwise have permission to use for the selected operation.

By default Soul distills named inspiration into musical attributes and removes
artist names from the generation prompt. The approved A5 design may transiently
decode one Operator-supplied YouTube URL in a bounded, foreground,
`analysis_only` operation, retaining provenance and non-expressive derived
evidence while deleting source audio and raw transcription. The exact boundary
is defined in `MUSIC_REFERENCE_LIBRARY_AND_URL_INGESTION_DESIGN.md`. It does not
scrape streaming services, train a LoRA, clone a voice, or create a cover from a
commercial recording. Retained reference audio, cover, source-structure, and
LoRA modes each still require a later operation-specific brief because they
preserve different amounts of timbre, melody, rhythm, harmony, and structure.

Generated output remains a candidate. Soul records provenance and similarity
review notes but cannot certify originality, copyright status, permissions, or
release readiness. Export/publishing is a separate human action.

## Resource arbitration

Extend the existing explicit runtime-control concepts rather than inventing
automatic GPU scheduling.

An A2 resource coordinator should expose read-only inventory and exact foreground
lease acquisition for named lanes:

- amd-conversation
- nvidia-fallback
- nvidia-music
- cpu-audio

Rules:

- one owner per GPU lane;
- nvidia-fallback and nvidia-music conflict;
- AMD conversation and NVIDIA music may coexist;
- lease acquisition revalidates the associated process/service state;
- stale leases expire only through bounded foreground inspection;
- no queue waits after returning control;
- no automatic service stop, fallback, preemption, or retry;
- cancellation terminates only the exact recorded process group;
- model caches unload at task completion unless the human later approves a
  bounded warm-session design.

Before a music run, Soul verifies Qwen is inactive, NVIDIA has sufficient free
memory, no music lease exists, the selected project/input digests are current,
and the output target is new. If blocked, it returns blocked_for_human_review
with the exact conflict.

## Generation lifecycle

Every generation is a bounded foreground task:

    draft
    → validate project, rights attestations, parameters, paths, and resources
    → preview exact model/input/output/resource scope
    → explicit START_MUSIC_GENERATION confirmation
    → acquire NVIDIA music lease
    → spawn one allowlisted argument-array process
    → stream bounded progress and logs
    → validate audio container, duration, channels, sample rate, and non-silence
    → atomically publish candidate metadata
    → release process and lease
    → blocked_for_human_review for listening and creative review

Terminal states are complete, failed, awaiting_input, canceled, or
blocked_for_human_review. The process receives a fixed wall timeout. Cancellation
sends TERM to its exact process group, waits a bounded interval, then KILLs that
group if necessary. Incomplete audio stays quarantined and is never presented as
a valid candidate.

The current sequential dashboard server cannot support truthful interactive
cancellation while one request owns a long generation. Therefore A1 is CLI-only.
A later dashboard brief must design one bounded task/progress channel with an
explicit cancellation path and prove that no generation survives server
shutdown, client abandonment, timeout, or task completion. Polling loops and
fire-and-forget workers are not acceptable shortcuts.

## Phased implementation

### A0 — architecture and candidate selection

This document. No installation, weight download, generation, or new tab.

### A1 — isolated NVIDIA feasibility pilot

- Pin ACE-Step release, weights, hashes, Python/CUDA compatibility, and exact
  commands.
- Install only in a user-local versioned environment after preview.
- Run a foreground benchmark at 30, 90, and 150–180 seconds.
- Keep AMD chat active and Qwen inactive.
- Remove or retain the environment only through the reviewed pilot decision.

### A2 — project schema and resource coordinator

- Add ignored project storage with deterministic schemas and provenance.
- Define the linked FLAC-master and MP3-proxy artifact schema and bounded
  transcode/validation receipt.
- Add read-only GPU inventory and explicit cross-runtime leases.
- Add bounded CLI create/generate/cancel/inspect operations.
- Do not add the dashboard tab yet.

### A3 — first Music Studio dashboard

- Project list, creative brief, lyrics/structure editor, exact generation
  preview, progress/cancel surface, audio candidates, and A/B review.
- One generation at a time; no background queue or automatic model load.

### A4 — controlled iteration

- Repaint, extend, retake, stem extraction, candidate lineage, and export.
- Each mode receives exact input/provenance and overwrite protections.

### A5 — knowledge and reference refinement

- Bounded genre/production research with citations.
- Bounded URL feature extraction and descriptor suggestions with transient media.
- Private Artist → Album → Track profiles and versioned composition syntheses.
- Human-reviewed whole/component retry and coherent two-to-five-profile fusion.
- Separately reviewed lawful reference, personalization, and similarity checks.

## Acceptance criteria for A1

Proceed beyond the pilot only if:

- the exact GTX configuration fits without desktop instability;
- a 2–3 minute generation finishes within an owner-acceptable time;
- AMD chat remains responsive;
- output is structurally usable enough to justify iteration work;
- startup, progress, cancellation, failure, and unload are observable;
- no listener, service, auto-download, update check, or hidden cache persists;
- the operator reviews three or more seeded candidates and wants the workflow
  integrated rather than merely technically possible.

## Primary sources

- ACE-Step 1.5 repository and release:
  https://github.com/ace-step/ACE-Step-1.5
- ACE-Step installation and AMD notes:
  https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/INSTALL.md
- ACE-Step GPU troubleshooting:
  https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/GPU_TROUBLESHOOTING.md
- ACE-Step control/reference tutorial:
  https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/Tutorial.md
- DiffRhythm:
  https://github.com/ASLP-lab/DiffRhythm
- YuE:
  https://github.com/multimodal-art-projection/YuE
- MusicGen:
  https://github.com/facebookresearch/audiocraft/blob/main/docs/MUSICGEN.md
- AMD Radeon ROCm Linux compatibility:
  https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/native_linux/native_linux_compatibility.html
