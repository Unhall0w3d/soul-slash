# Current State

Soul/ is an experimental local-first assistant runtime and creative workspace. One conversation, memory, skill, artifact, approval, policy, and execution core serves both the CLI and authenticated dashboard.

## Product surfaces

```text
Chat
Self Improvement
  ├─ Skill Studio
  ├─ Self Assessment
  └─ Self Augmentation
Creative Studios
  ├─ Music Studio
  └─ Visual Studio
Review Center
```

### Chat

Chat provides persistent multi-turn transmissions, explicit local push-to-talk transcription into an editable unsent draft, explicit bounded local speech for eligible completed Soul messages, immediate accepted-message rendering, truthful working summaries, local model responses, deterministic capability and skill routing, bounded research, shared artifacts, workspace metadata, inbox delivery, memory controls, system status, and manual model/Core controls. One explicit PNG or JPEG attachment plus a question can enter bounded local picture understanding through Gemma on Daily Core. The Operator may also request one current-monitor, active-window, or selected-region screenshot; Dashboard capture is explicit, foreground, and previewed before the existing picture-analysis path runs. Voice Presence accepts only deterministic explicit current-screen requests, checks for Daily Core before capture, retains no pixels, and leaves ordinary screen discussion conversational. There is no periodic capture, background watching, silent Core transfer, or screen control. Source pixels are discarded after the answer by default or retained owner-private with that conversation by explicit Dashboard checkbox; image content remains evidence and cannot authorize actions. Chat can also resolve exact Music Studio and Visual Studio project titles, read their stored briefs and bounded lineage, and—when explicitly asked—inspect an existing still or three sampled frames from an existing motion candidate without requiring the Operator to download and re-upload Soul's own artifact. Archive inspection is read-only and candidate pixels remain untrusted evidence. Explicit music, visual, or combined creative requests can enter a per-conversation bounded workflow: Soul preserves user-required decisions, drafts visible optional fields, presents an exact Core-aware generation action, and returns authenticated candidates for human review. Recorded music or still-image `revise` dispositions can continue through visible Soul-drafted revisions and exact linked generation actions. A kept or exact existing visual context can also prepare a 4-, 8-, or 12-second native text-to-video action; its WebM returns to Chat, while motion review stays in Visual Studio and a stored `revise` review can unlock one linked Chat revision. Combined flows can bind kept stills to kept songs, render reviewed static or generated-motion companions, export kept songs, and create exact local upload packages through separate gates. Recorded music `reject` may prepare permanent candidate deletion after a separate request. Merely mentioning skills, creative work, motion, revision, binding, export, or deletion does not invoke those capabilities.

The Chat context rail now exposes a curated Invocation Guide. It describes
required and optional inputs, Core needs, approval behavior, result shape, and
authority boundaries for supported Operator workflows. The same catalog can
be queried deterministically in Chat. Catalog inspection and its example
wording are inert: neither can execute a skill, change a Core, or authorize a
gate.

After Voice Presence finishes playing an eligible response, it opens one
visible five-second window for a natural follow-up without another wake
phrase. Speech retains the ordinary utterance bounds; silence returns to
“Hey Soul” listening without counting as a failure. The microphone remains
closed while Soul thinks or speaks.

The installed wake-sensitivity update, natural follow-up behavior, and
dashboard self-recognition map have deterministic coverage but remain
**untested in their current live configuration**. Operator validation is
deferred until the next at-computer voice session.

Dashboard notification delivery now has voice, cues-only, and muted modes.
Submission, wake, completion, and attention cues are static local assets.
When Voice Presence is visibly open and idle-listening, Chat, music, visual,
and lyric-analysis completions may additionally use a pre-generated notice in
the selected F3 or M3 voice. Each event performs one point-in-time status check;
there is no polling or event-time synthesis.

Voice screen requests also resolve fresh explicit targets for the active
Hyprland window, focused monitor, all monitors, left/right or numbered monitor,
and a currently visible workspace. Hidden workspaces are never switched
silently. Refresh/update-view language forces the perception path instead of
letting the chat model reuse a prior description, and the vision prompt must
verify names and visible words from pixels rather than echo hints in the
question.

The dashboard has one personal administrator boundary. First-run `admin` / `soul123` access is limited to mandatory password replacement. Salted credentials and seven-day session digests remain in ignored owner-only runtime storage. Sign-ups and additional accounts are unavailable.

### Self Improvement

- **Skill Studio** separates Proposals, Operator-invoked Beta candidates, and Production skills. Gate 1 approves exact scope; Gate 2 approves an exact tested revision; production promotion and completed-proposal closeout remain separate mutations.
- **Self Assessment** collects bounded host, update, runtime, capability, and storage evidence. It can prepare advisory proposals and terminal handoffs but cannot mutate the host.
- **Self Augmentation** creates human-authored architecture proposals, exact allowed-file experiments in isolated worktrees, deterministic candidate dossiers, and external integration handoffs. It cannot invoke Codex, merge, push, or deploy.

### Creative Studios

- **Music Studio** stores immutable project briefs and candidate lineage; supports exact 30-second, 90-second, 3-minute, and 10-minute AMD Vulkan ACE-Step generation; preserves exact `[Instrumental]` no-vocal conditioning while allowing bounded instrumental movement timing in Sound and Structure; creates FLAC masters and MP3 proxies; follows durable jobs across page navigation; records generation timing, CPU vocal evidence, human review, revision drafts, lawful reference profiles and fusions, rejection, export, and one-generation source-preserving trim copies.
- **Visual Studio** provides bounded local FLUX.2 Vulkan still generation, review, guided image edits, Wan 2.2 image-guided motion, FastWan 2.2 native text-to-video, immutable revision lineage, candidate/project deletion, and exact binding to a Music candidate.
- The read-only motion qualification ledger compares retained duration, frame,
  delivery, elapsed-time, and human-review evidence without automatically
  declaring any profile aesthetically qualified.
- A reviewed still or short generated-motion candidate can become a music companion with framing, matte, fades, repetition where needed, and full-song audio muxing. A kept/exported song with a final visual can produce an editable exact local YouTube upload package. Nothing uploads or publishes automatically.

Historical procedural camera movement is retired. The current generated-motion
lanes are explicit, short, review-gated candidates: image-guided Wan output is a
fixed resource-oriented study, while native FastWan output supports 4, 8, or 12
seconds at a delivered 24 fps. Longer companions repeat one accepted scene and
are labeled accordingly.

The operator-facing flows are documented in [`docs/guides/`](guides/).

## Runtime topology

The stable chat API alias is `soul-local-chat`; actual model identity is reported separately.

- **Daily Core:** Gemma 4 12B Instruct Q4_K_M through Ollama/Vulkan on AMD.
- **AMD-Free Core:** Qwen3 8B Q4_K_M through llama.cpp/CUDA on NVIDIA.
- **Music Core:** Qwen chat on NVIDIA while ACE-Step 1.5 4B LM / 2B Turbo Q8_0 uses AMD/Vulkan only during bounded music generation.

Core changes are click-authorized and lease-revalidated. Before a conversational creative generation or revision action is offered, Soul reports the active Core, required Core, whether the click includes a transfer, and why. Music generation/revision requires Music Core; visual-only generation/guided revision requires AMD-Free Core; reviewed-source-only operations do not manufacture a transfer. The exact action click authorizes the disclosed transition and bounded operation together, while execution revalidates the requirement and delegates to the existing Core controller. Model text cannot initiate one and no failover occurs on its own. Music and image models do not remain resident. No idle-unload timer, unattended Core switch, worker queue, or background polling loop is present.

## Deployment

`make dashboard` runs a foreground loopback development instance. The reviewed optional deployment installs explicit user services for the loopback dashboard and Caddy HTTPS on one exact LAN address. Installation is preview-first, requires a changed administrator password and exact confirmation, and leaves firewall, DHCP, router, and client certificate trust to the Operator.

Proxmox, Internet exposure, multi-user accounts, backup, and disaster recovery remain separate future tracks.

## Memory, artifacts, and deletion

Mutable owner memory lives under ignored `Soul/private/memory/`; tracked memory files are neutral public seeds. Durable promotion remains human-reviewed.

An optional external Knowledge Vault may supplement these canonical stores with
portable Markdown notes. Soul can inspect and search it in bounded foreground
operations, project approved memory into a generated index, and import one
explicit note as a candidate through an exact review gate. Obsidian is an
optional human surface rather than a dependency. The vault is never watched,
automatically synchronized, or treated as approved memory.

Knowledge Reflection deterministically classifies one explicit structured
candidate before storage. Reviewed durable project knowledge may receive an
exact vault-note preview; preferences route to shared-memory review, Studio
evidence remains in its canonical archive, transient or unverified material
stays conversational, and likely secrets are never-store. A1 does not yet
initiate reflection autonomously from a conversation. A2 adds one deliberately
narrow Chat request that asks the configured local model to draft a single
candidate from the active bounded transcript. Non-vault results create no
isolated pending store. Vault-eligible results remain private review state until
the Operator sends the exact candidate ID and digest; execution then delegates
to A1 and recomputes the entire write scope.

Project Timeline provides one shared implementation ledger in the Dashboard and
through explicit deterministic Chat controls. A neutral public seed initializes
ignored owner-local state on first use. Items carry an explicit horizon, status,
priority, implementation summary, models/languages/technologies, interfaces,
commands, references, acceptance criteria, notes, source, and optimistic
revision. The curated seed includes a compact implemented-feature inventory as
well as active and pending work. Soul does not infer status from tests, commits,
conversation, or model output, and no watcher or background tracker exists.

Conversations, skill candidates, music projects, visual projects, reference profiles, logs, and generated artifacts have explicit lifecycle boundaries. Reversible archive/Trash behavior is preferred where appropriate. Permanent deletion exists only for previewed exact scopes and preserves separately exported finished files where the relevant workflow says so.

## Human authority boundary

Soul may inspect, explain, draft, research, stage, generate, test, and produce evidence. It may not treat model output, passing tests, successful generation, or a machine-heard result as authorization.

Human approval remains required for risky or destructive execution, durable memory/rule promotion, skill and augmentation gates, production registration, host mutation, provider/privacy exceptions, service installation, merge, release, upload, and publication.

## Current development focus

The foundational Conversational Soul milestone is complete. Deployment/Core orchestration, Self Improvement, Music Studio, Visual Studio still and short-motion lanes, and local publication packaging are implemented and under owner use.

Near-term work is expected to concentrate on:

- chat usability, persona fidelity, and dashboard-capability invocation through skills;
- interruption-aware duplex voice beyond the reviewed push-to-talk,
  per-message speech, and visible local wake-word presence paths;
- production hardening and documentation of creative workflows;
- additional Music Studio refinement based on real generations;
- motion-quality refinement based on reviewed image-guided and native scenes;
- explicit one-shot monitor, window, or region capture building on the bounded
  Gemma 4 picture-understanding path now available in Chat;
- backup/recovery and broader deployment only under separate review.

No release or stable tag has been created.

## Primary references

- [`README.md`](../README.md)
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)
- [`docs/ROADMAP.md`](ROADMAP.md)
- [`docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`](soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md)
- [`docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md`](soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md)
- [`docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md`](soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md)
- [`docs/guides/PROJECT_TIMELINE.md`](guides/PROJECT_TIMELINE.md)
