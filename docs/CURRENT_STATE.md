# Current State

Soul/ is an experimental local-first assistant runtime, not only a model frontend. The current implementation shares one conversation, skill, memory, artifact, approval, and policy core across the CLI and foreground dashboard.

## Implemented product surfaces

```text
Chat
Skill Studio
Self Assessment
Self Augmentation
```

Chat provides persistent multi-turn conversations, immediate accepted-message
rendering, truthful foreground work summaries, a responsive Soul familiar,
local/model-backed responses, skill routing, artifacts, workspace metadata,
inbox delivery, initial host status, and explicit refresh. Narrow orientation
may use bounded DuckDuckGo Instant Answers; evidence-bearing work uses an
explicitly configured SearXNG endpoint and selected public HTTPS sources.

The browser dashboard has a single personal administrator boundary. First-run `admin` / `soul123` access is restricted to mandatory password replacement; private dashboard data and controls remain locked until that succeeds. Credentials are salted and derived in ignored local runtime storage. Sessions are bounded to seven days and persist across dashboard restarts using owner-only token digests; raw bearer tokens remain in host-only browser cookies. Sign-ups and additional accounts are unavailable.

Skill Studio provides separate Proposal, Beta, and Production inventories. Human Gate 1 may prepare an exact proposal-local incomplete Beta workspace and bounded Codex handoff without invoking a model. A human or explicitly invoked Codex task implements and tests that candidate. Human Gate 2 approves an exact tested Beta revision; a separate preview/digest/exact-confirmation operation may then copy its self-contained Ruby entrypoint and atomically add one new production registry entry. Existing skills are never replaced, and no gate promotes automatically.

Self Assessment provides one lightweight read-only environment snapshot when opened plus explicit foreground environment, package-update, model-runtime, and capability assessments. It may generate advisory improvement proposal packets only after preview, digest revalidation, and exact confirmation. It cannot apply updates or mutate the host. The internal `self_improvement.*` operation namespace remains stable for compatibility.

## Implemented core capabilities

- model-backed multi-turn conversation with persistent chat identity;
- deterministic capability declarations, intent routing, and skill invocation planning;
- bounded host evidence and follow-up routing;
- layered conversation memory with review, export, and forget controls;
- identity, interests, recent-style awareness, and inspectable boundaries;
- shared artifacts, bounded inspection, creation/revision, and inbox delivery;
- preview-first conversation clearing by exact title, selected set, or all active chats, plus exact single-conversation delete-and-forget;
- production skill registry plus isolated Beta candidates and bounded diagnostics;
- conservative self-skilling intake for genuinely unsupported task requests;
- environment, model-runtime, capability, and improvement-proposal assessment;
- portable typed configuration through CLI overrides, process environment, ignored `.env`, and safe defaults.
- separate bounded `web.lookup` and provenance-preserving `web.research` paths;
- explicit review-only research reflection candidates with no automatic memory promotion.

## Runtime and deployment boundary

The dashboard is dependency-free static HTML/CSS/JavaScript served by a sequential Ruby foreground loopback process:

```bash
ruby bin/soul dashboard
```

The default command does not install a service, bind to the LAN, poll in the background, or continue after the process stops. An owner-approved optional local deployment candidate now keeps Soul loopback-bound while two explicit user services provide persistent operation and Caddy-managed HTTPS on one exact LAN address. Installation remains preview-first and opt-in; client CA trust and local service behavior require human review. Proxmox, containers, Internet exposure, backups, and recovery remain separate deployment tracks.

## Human authority boundary

Soul may assess, explain, draft, stage, test, and produce review artifacts. It may not treat model output or passing tests as approval.

Human approval remains required for:

- risky or destructive execution;
- durable memory/rule promotion;
- proposal and Beta gates;
- system/package mutation;
- provider/privacy exceptions;
- merge and release decisions;
- persistent-service or deployment architecture.

## Current development position

The Conversational Soul milestone is complete at its Phase 13 stopping point following owner approval on 2026-07-15. Phase 12D.5 was reviewed and merged with bounded Beta workspace preparation and preview-gated Beta-to-production promotion. Phase 13A passes all ten deterministic integrated scenarios through isolated real application/runtime boundaries. Phase 13B completed a bounded local-model run with 20/20 model turns and 6/6 continuity probes, while recording sustained latency as a known weakness. Phase 13C aligns documentation and the aggregate verifier suite. No release or tag has been created; later work begins as a separately approved milestone.

The Deployment and Operations milestone now has manual, preview-gated
multi-profile runtime control and selected-profile login startup. The active
quality profile uses Ministral 3 14B Instruct 2512 Q4_K_M on AMD Vulkan; Qwen3
8B Q4_K_M on NVIDIA CUDA remains an explicit fallback profile. No automatic
switching, fallback, idle unload, or reboot is introduced. Runtime identity is
reported separately from the stable `soul-local-chat` OpenAI-compatible API
alias, so callers do not misidentify the loaded model.

The next accepted design direction is Multi-model and Music Studio A0. It keeps
Ministral conversation on AMD and proposes a measured ACE-Step 1.5 foreground
pilot on the otherwise-idle NVIDIA card, mutually exclusive with Qwen fallback.
The target product is an iterative project workspace for 2–3 minute songs,
lyrics, lawful references, candidates, repainting, stems, and creative review.
A0 installed and ran nothing. The first Music A1 candidate now provides an
optional `uv` preflight, pinned and preview-gated user-local setup, separately
confirmed verified model downloads, and a bounded offline foreground pilot.
The default checkpoint names are exact but publicly overridable through a
reviewed manifest. After owner approval, the pinned v0.1.8 source and isolated
Python 3.12 environment were installed user-locally. PyTorch 2.10 CUDA 12.6
successfully imported ACE-Step and ran synchronized matrix multiplication on
the GTX 1070 through its compatible `sm_60` cubin. After a second owner
approval, all 7,709,375,886 bytes across the 25 selected
checkpoint files passed their pinned size and SHA-256 checks; no partial file
was retained as a checkpoint. The first 30-second float16 attempt produced NaN
latents; a second float32 generation succeeded but exposed upstream output
cleanup. The exact Soul compatibility overlay now honors float32, prevents the
automatic downloader, retains bounded output, and rejects zero-exit failures.
The final 30-second candidate is a verified 48 kHz stereo FLAC and passed human
listening review. The subsequent 90-second candidate also completed as a valid,
non-silent 48 kHz stereo FLAC in 47.966 seconds of measured wall time, preserved
AMD chat health, and released NVIDIA afterward. It now awaits human listening
review. Full A1 remains open until that review plus the 180-second host pilot
passes.

Self Assessment now also projects the exact CachyOS core-package reboot request
relative to current boot time. On this host the July 17 package transaction is
newer than the July 11 boot, so a reboot is correctly recommended without Soul
performing or scheduling it.

Detailed references:

- `docs/CONVERSATIONAL_SOUL_ROADMAP.md`
- `docs/MILESTONES.md`
- `docs/ARCHITECTURE.md`
- `docs/INTERACTION_ARCHITECTURE.md`
- `docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`
- `docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md`
- `docs/soul/PHASE12E_UNIFIED_REVIEW_CENTER_BRIEF.md`
- `docs/soul/PHASE13A_INTEGRATED_ACCEPTANCE_HARNESS_BRIEF.md`
- `docs/soul/MUSIC_STUDIO_A1_SETUP_BRIEF.md`
- `docs/soul/PHASE13B_LOCAL_MODEL_AND_DASHBOARD_ACCEPTANCE_BRIEF.md`
- `docs/soul/PHASE13C_CONVERSATIONAL_SOUL_CLOSEOUT_BRIEF.md`
- `docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md`
- `docs/soul/HUMAN_REVIEW_GATE.md`
