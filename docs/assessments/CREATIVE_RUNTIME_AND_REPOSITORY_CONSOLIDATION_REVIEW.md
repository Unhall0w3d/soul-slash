# Creative Runtime and Repository Consolidation Review

## Outcome

Candidate-complete documentation and setup consolidation for the supported
Gemma/Qwen/ACE-Step/FLUX/Wan stack and the reviewed Visual Studio generated
motion lanes.

## What changed

- Public product, architecture, requirements, roadmap, milestone, setup, and
  Operator documentation now reflects still, image-guided motion, native
  text-to-video, motion revision, Music binding, and repeated full-duration
  companions.
- The Makefile exposes the reviewed chat defaults and all integrity-bound
  creative manifests through `make defaults-show`.
- `make supported-stack-check` performs read-only checks of the supported
  creative lanes.
- `config/model_overrides.example.mk` documents a portable ignored
  `Makefile.local` override path. Chat models accept an exact GGUF filename/URL
  or Ollama tag. Creative substitutions require a complete manifest binding
  repository, revision, filename, size, digest, and runtime bounds.
- The generic Ollama setup now offers the reviewed Gemma Daily Core by default;
  the llama.cpp setup retains the reviewed Qwen NVIDIA reserve default.
- A hard-coded operator home fallback in `system.status` was removed.
- Historical review commands were sanitized so public documents no longer
  retain an operator-specific checkout path, hostname, or assigned LAN address.

## Repository privacy review

Confirmed ignored local domains include:

- `Soul/private/`
- `Soul/runtime/`
- `Soul/music/`
- `Soul/visual/`
- generated Skill Studio and Self Improvement proposals/experiments
- conversation, workflow, reflection, and execution state
- `.env`, `Makefile.local`, model weights, logs, caches, and credentials

The working-tree candidate list contains source, public configuration,
documentation, deterministic verifiers, and curated brand assets only.
Generated projects and owner state remain local.

## Commands and deterministic results

```text
make defaults-show — PASS
make help — PASS
bash -n scripts/soul-setup-ollama.sh scripts/soul-setup-llamacpp.sh — PASS
ruby -c Soul/skills/system/status.rb — PASS
ruby scripts/verify-music-studio-a3.rb — PASS
ruby scripts/verify-visual-studio-native-video.rb — PASS
ruby scripts/verify-visual-studio-generated-motion.rb — PASS
ruby scripts/verify-visual-motion-qualification.rb — PASS
ruby scripts/verify-visual-studio-a1.rb — PASS
ruby scripts/verify-visual-studio-a2.rb — PASS
ruby scripts/verify-music-publication-package.rb — PASS
ruby scripts/verify-music-revision-draft.rb — PASS
ruby scripts/verify-music-visual-companion.rb — PASS
ruby scripts/verify-phase12c-foreground-dashboard.rb — PASS
git diff --cached --check — PASS
```

The Phase 12C aggregate verifier initially reported the three new untracked
visual verifiers as curation candidates. After intentional file-by-file staging
and one trailing-whitespace correction, the full aggregate regression passed.

## Local LLM evaluation

Not run. Setup integrity, repository privacy, exact approval gates, media
validation, and lifecycle behavior are deterministic concerns.

## Known weaknesses

- Creative model substitution requires authoring a complete manifest; this is
  intentionally more work than supplying a filename because compatibility and
  integrity cannot be inferred safely.
- Motion quality and runtime remain hardware-sensitive. Twelve-second native
  delivery uses bounded 16-to-24 fps interpolation and still requires human
  review for artifacts.
- Repeating a short accepted scene creates a full-duration presentation, not
  unique long-form generated footage.
- Optional runtime and model installation remains a sequence of separate
  preview/confirmation gates rather than one unattended installer.

## Memory and lifecycle

Memory keys added or used: none.

Lifecycle states covered by the affected bounded operations:

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

No new service, daemon, listener, watcher, scheduler, queue, or unattended
model process was added.

## Risk classification

Class 3: local model/runtime installation guidance and bounded creative
generation. Installation and download remain exact preview-gated; public
publication remains a human action.

## Human review checklist

- [ ] Public setup describes the actual supported default models.
- [ ] Local model choices can be retained without modifying tracked files.
- [ ] Creative overrides retain exact digest and compatibility evidence.
- [ ] Private projects, conversations, memory, proposals, and runtime state are
      absent from the staged candidate.
- [ ] Native 4/8/12-second controls and live status are accurate in the
      dashboard.
- [ ] All deterministic verifiers pass after intentional staging.
- [ ] No upload, publication, unattended Core switch, or persistent creative
      model was introduced.
