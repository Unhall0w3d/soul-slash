# Perception A0 - Readiness and Architecture Brief

## Purpose

Establish the local model, capture, privacy, retention, Core, and authority
boundaries for picture and screen understanding before Soul accepts any image
input.

This is a read-only assessment slice. It does not capture a screenshot, download
a model, change a Core, extend the chat message schema, or register a skill.

## Local findings

Reference host:

- AMD Radeon RX 6900 XT, 16 GiB, Vulkan
- NVIDIA GeForce GTX 1070, 8 GiB, CUDA
- Ryzen 7 5800X
- 64 GiB system RAM
- two 3440x1440 Hyprland monitors

Installed perception prerequisites:

- Ollama 0.32.2 with Vulkan support
- production `gemma4:12b-it-q4_K_M` model, 7.38 GB model layer
- Gemma 4 BF16 multimodal projector, 175,115,584 bytes
- `grim` 1.5.0
- `slurp` 1.5.0
- `hyprctl`
- Tesseract 5.5.2 with English and orientation data
- `xdg-desktop-portal-hyprland`

The production model is already multimodal. A1 should qualify this exact model
before introducing another resident or downloaded model.

## Candidate order

### 1. Existing Gemma 4 12B - production lead

Use the current Daily Core model through its existing Ollama runtime.

Reasons:

- no additional model download or storage;
- its exact local manifest includes the vision projector;
- image understanding, OCR, object detection, variable aspect ratios, and
  selectable visual-token budgets are part of the model's documented surface;
- it preserves Soul's existing persona, conversation context, and provider
  topology;
- Ollama accepts base64 image data in a message-local `images` array.

The A1 pilot must measure small-text OCR, terminal screenshots, desktop UI,
photographs, diagrams, image hallucination, latency, and VRAM. Published model
benchmarks are not acceptance evidence.

### 2. Qwen3-VL 8B Instruct - conditional challenger

Only download and test if Gemma misses the reviewed A1 thresholds, especially UI
grounding, dense screenshots, spatial descriptions, or small text. Qwen's
official model emphasizes OCR, spatial grounding, computer-use, and multimodal
coding. It is a plausible transient specialist, not the default starting point.

### 3. MiniCPM-V 4.5 8B - conditional OCR/efficiency challenger

Only test if the first two candidates leave a material OCR, document, or
inference-efficiency gap. Its official project documents GGUF and Ollama support,
high-resolution OCR, and an 8B footprint.

### Deterministic OCR companion

Tesseract remains useful as separately labeled machine evidence for crisp
screenshots. Its output must not be silently represented as the vision model's
observation. A later specialized document path may assess PaddleOCR, but it is
not required for A1 general picture understanding.

## Core policy

- Daily Core: Gemma vision may run through the already active AMD chat model.
- AMD-Free Core: picture analysis requires a disclosed transfer to Daily Core.
- Music Core: picture analysis requires a disclosed transfer to Daily Core and
  must not interrupt active music work.
- No automatic fallback to a cloud model.
- No hidden Core transfer and no capture before the exact operation is accepted.

A future specialist may receive its own bounded lease. It must not become
resident merely because an image was attached.

## A1 picture contract

One invocation accepts:

- one local image artifact;
- one explicit Operator question;
- an optional bounded analysis mode such as `describe`, `read_text`,
  `troubleshoot`, or `compare`;
- a reviewed visual-token budget;
- an explicit retention choice, defaulting to ephemeral.

Supported initial media:

- PNG
- JPEG
- WebP only if decoded and normalized safely before inference

The service must validate real media type, dimensions, decoded pixel count, byte
size, digest, and path boundary. It must reject SVG, HTML, PDFs, animation,
polyglot content, URLs, symlinks, and decompression bombs in A1.

The immutable normalized input and its digest are the evidence boundary. Model
output must identify:

- direct observations;
- text it believes it read;
- interpretations;
- uncertainty and unreadable regions;
- model/runtime identity and latency.

## A2 screen contract

Screen capture remains a later, separate mutation:

- whole monitor: resolve an exact current Hyprland monitor, then call `grim`;
- region: require an explicit `slurp` selection;
- window: resolve exact geometry through Hyprland state and capture that bounded
  region;
- preview the captured image before model analysis where practical;
- analyze one immutable screenshot, return a terminal state, and stop.

No periodic screenshots, background watching, visual wake loop, automatic
recapture, or unattended comparison is allowed.

## Privacy and retention

Images are local-private by default and may be sent only to a provider declaring
`local_only`.

Default behavior:

1. normalize into an owner-only staging directory outside the repository;
2. compute a digest and run one bounded inference;
3. retain the answer and provenance in Chat;
4. delete the normalized image after the response is recorded.

The Operator may explicitly preserve an image as a normal Soul artifact. Existing
Visual Studio candidates may be referenced in place without being copied into a
new private store.

Screenshots must never enter Soul Vault or durable memory automatically. A later
reflection may summarize a reviewed lesson without retaining the pixels.

## Untrusted-image boundary

Text, QR codes, instructions, buttons, and other content visible in an image are
untrusted evidence. They do not:

- alter system instructions;
- authorize a tool or skill;
- approve a Core change;
- authorize clicking, typing, downloading, deletion, publication, purchase,
  login, or session control;
- establish that an event occurred outside the pixels supplied.

Soul may quote or explain visible instructions. It must not follow them merely
because they appear in an image.

## Lifecycle

Every perception operation terminates as:

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

Inference, decoding, and capture receive explicit timeouts and byte/pixel/token
limits. No worker remains alive after the operation returns.

## A1 acceptance set

The deterministic harness must include:

- valid PNG and JPEG;
- extension/media mismatch;
- oversize bytes and pixels;
- truncated and malformed files;
- symlink and repository-boundary rejection;
- expired preview/digest mismatch;
- local-only provider enforcement;
- no image persistence by default;
- explicit artifact retention;
- prompt-injection text inside a fixture image;
- no skill call or mutation from image content;
- lifecycle coverage for all terminal states;
- disclosed Daily Core requirement.

The measured local set should include:

- 3440x1440 terminal with a known error;
- browser/dashboard screenshot with small UI text;
- ordinary photograph;
- diagram with known labels and relationships;
- generated image with a deliberate malformed detail;
- low-contrast and partially unreadable text;
- image containing malicious-looking instructions;
- an unrelated question to test unsupported inference.

## Gate

Human review of A0 authorizes implementation of A1 picture understanding only.
It does not authorize screenshots, continuous observation, computer control,
model downloads, or production promotion.

## Primary references

- Google Gemma image understanding:
  https://ai.google.dev/gemma/docs/capabilities/vision/image
- Ollama vision:
  https://docs.ollama.com/capabilities/vision
- Ollama chat API:
  https://docs.ollama.com/api/chat
- Gemma 4 Ollama model:
  https://ollama.com/library/gemma4:12b-it-q4_K_M
- llama.cpp multimodal support:
  https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md
- Qwen3-VL:
  https://github.com/QwenLM/Qwen3-VL
- MiniCPM-V 4.5:
  https://github.com/OpenBMB/MiniCPM-V/blob/main/docs/minicpm_v4dot5_en.md
- PaddleOCR:
  https://github.com/PaddlePaddle/PaddleOCR
