# Current State

Soul/ is an experimental local-first assistant runtime and creative workspace. One conversation, memory, skill, artifact, approval, policy, and execution core serves both the CLI and authenticated dashboard.

## Product surfaces

```text
Chat
Project Timeline
Self Improvement
  ├─ Skill Studio
  ├─ Self Assessment
  └─ Self Augmentation
Creative Studios
  ├─ Music Studio
  └─ Visual Studio
Administration
  └─ Backup & Recovery
Review Center
```

### Chat

Chat provides persistent multi-turn transmissions, explicit local push-to-talk transcription into an editable unsent draft, explicit bounded local speech for eligible completed Soul messages, immediate accepted-message rendering, truthful working summaries, local model responses, deterministic capability and skill routing, bounded research, shared artifacts, workspace metadata, inbox delivery, memory controls, system status, and manual model/Core controls. One explicit PNG or JPEG attachment plus a question can enter bounded local picture understanding through Gemma on Daily Core. The Operator may also request one current-monitor, active-window, or selected-region screenshot; Dashboard capture is explicit, foreground, and previewed before the existing picture-analysis path runs. Voice Presence accepts only deterministic explicit current-screen requests, checks for Daily Core before capture, retains no pixels, and leaves ordinary screen discussion conversational. There is no periodic capture, background watching, silent Core transfer, or screen control. Source pixels are discarded after the answer by default or retained owner-private with that conversation by explicit Dashboard checkbox; image content remains evidence and cannot authorize actions. Chat can also resolve exact Music Studio and Visual Studio project titles, read their stored briefs and bounded lineage, and—when explicitly asked—inspect an existing still or three sampled frames from an existing motion candidate without requiring the Operator to download and re-upload Soul's own artifact. Archive inspection is read-only and candidate pixels remain untrusted evidence. Explicit music, visual, or combined creative requests can enter a per-conversation bounded workflow: Soul preserves user-required decisions, drafts visible optional fields, presents an exact Core-aware generation action, and returns authenticated candidates for human review. Recorded music or still-image `revise` dispositions can continue through visible Soul-drafted revisions and exact linked generation actions. A kept or exact existing visual context can also prepare a 4-, 8-, or 12-second native text-to-video action; its WebM returns to Chat, while motion review stays in Visual Studio and a stored `revise` review can unlock one linked Chat revision. Combined flows can bind kept stills to kept songs, render reviewed static or generated-motion companions, export kept songs, and create exact local upload packages through separate gates. Recorded music `reject` may prepare permanent candidate deletion after a separate request. Merely mentioning skills, creative work, motion, revision, binding, export, or deletion does not invoke those capabilities.

An ordinary Chat send now writes its concise lifecycle summary to the existing
owner-local application receipt ledger. The Dashboard renders the Operator's
text before opening the response stream, marks it accepted only after the
server records it, and updates one working card from real runtime events.
Reloading or returning to that conversation reconstructs fresh active progress
through the read-only `chats.progress` operation. Terminal or four-hour-stale
receipts are not shown as active. This recovery is load-driven: it adds no
polling, watcher, worker, daemon, or second execution path. Automatic stream
reattachment and durable Studio/administration progress remain deferred.

The Chat context rail now exposes a curated Invocation Guide. It describes
required and optional inputs, Core needs, approval behavior, result shape, and
authority boundaries for supported Operator workflows. The same catalog can
be queried deterministically in Chat. Catalog inspection and its example
wording are inert: neither can execute a skill, change a Core, or authorize a
gate.

Soul's stable `soul.identity.v1` profile is at version 9. Gemma receives a
balanced expression projection and Qwen receives a smaller projection of the
same identity; neither changes authority or routing. Explicit Chat commands can
disable, inspect, and re-enable persona expression for only the active
conversation. Disabled mode is neutral delivery, not disabled truth, evidence,
privacy, skills, approvals, or memory policy.
Matched temporary-state evaluations completed at the production output budget
with 41/41 checks on Gemma Daily Core and 41/41 on Qwen AMD-Free Core. This is
behavioral evidence, not release approval; ordinary Operator conversation
review remains open.

After Voice Presence finishes playing an eligible response, it opens one
visible five-second window for a natural follow-up without another wake
phrase. Speech retains the ordinary utterance bounds; silence returns to
“Hey Soul” listening without counting as a failure. The microphone remains
closed while Soul thinks or speaks.

The installed wake-sensitivity update, natural follow-up behavior, dashboard
self-recognition map, notification cues, spoken notices, screen targeting, and
Core-aware invocation handoff completed Operator live acceptance on
2026-07-27. Minor refinements remain ordinary follow-up work rather than open
release gates.

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
question. Natural `What am I looking at?` wording also forces one fresh active-
window capture. Voice-requested screen answers apply a deterministic literal-
claim guard: quoted or emphasized titles, channels, applications, and control
names absent from that capture's compositor/OCR evidence are withheld.

Weather speech is now presentation-aware without changing retained Chat text.
Recorded `weather.report` metadata expands compact units into pronounceable
phrases, inserts measured sentence boundaries, and applies a modestly slower
responsive rate. Harmless speech-to-text bullet punctuation on an affirmative
weather follow-up no longer diverts the detailed report into the general model.

The dashboard has one personal administrator boundary. First-run `admin` / `soul123` access is limited to mandatory password replacement. Salted credentials and seven-day session digests remain in ignored owner-only runtime storage. Sign-ups and additional accounts are unavailable.

### Self Improvement

- **Skill Studio** separates Proposals, Operator-invoked Beta candidates, and Production skills. Gate 1 approves exact scope; Gate 2 approves an exact tested revision; production promotion and completed-proposal closeout remain separate mutations.
- **Self Assessment** collects bounded host, update, runtime, capability, and storage evidence. It can prepare advisory proposals and terminal handoffs but cannot mutate the host.
- **Guided Maintenance**, under Administration, consumes fresh assessment evidence and previews the exact Arch/AUR and Flatpak transaction plus a privacy-filtered Hyprland restore map. A1 remains read-only. The accepted A2 path adds a visible, bounded, one-password terminal executor and a no-mutation terminal rehearsal. A2B adds a single-use XDG desktop handoff so native package evidence and an approved transaction can run outside the deliberately confined Dashboard without weakening its systemd sandbox. A2 live execution remains disabled by default and always stops before reboot. The accepted A3 path adds a separately disabled conditional-reboot gate, digest-bound restore journal, exact reboot vector, and bounded one-shot post-login Hyprland restorer. On the Operator's workstation, the reviewed resume unit and display-recovery hook completed a supervised end-to-end update, reboot, DP-3 recovery, and exact Codex/Opera workspace restoration on 2026-07-28. Both live gates remain disabled outside an exact supervised transaction.
- Fleet status now emits the portable canonical device ID `workstation`. The
  former `maven` ID and `SOUL_FLEET_MAVEN_*` environment names remain bounded
  read aliases for existing private state; newly written snapshots, topology,
  refresh results, and tracked examples use `workstation` and
  `SOUL_FLEET_WORKSTATION_*`.
- **Crucible** is the optional Fedora 44 KVM fleet member on Forge. Its first
  integration collects bounded live DNF5, kernel, reboot, SSH, and guest-agent
  evidence while retaining inventory-only control. DNF5 maintenance and reboot
  gates remain deliberately unavailable. Operator-managed reservations now
  provide stable identities for the workstation, Forge, the Pi-hole appliance,
  and Crucible. Deployment-specific card names remain ignored local
  configuration; public source preserves functional roles and stable IDs.
- **Self Augmentation** creates human-authored architecture proposals, exact allowed-file experiments in isolated worktrees, deterministic candidate dossiers, and external integration handoffs. It cannot invoke Codex, merge, push, or deploy.

### Creative Studios

- **Music Studio** stores immutable project briefs and candidate lineage; supports exact whole-second AMD Vulkan ACE-Step generation from 30 seconds through 5 minutes plus a fixed 10-minute option; preserves exact `[Instrumental]` no-vocal conditioning while allowing bounded instrumental movement timing in Sound and Structure; creates FLAC masters and MP3 proxies; follows durable jobs across page navigation; records generation timing, CPU vocal evidence, human review, revision drafts, lawful reference profiles and fusions, rejection, export, and one-generation source-preserving trim copies. A short/long variable-duration qualification passed technically at 43 and 248 seconds; musical acceptance remains human review.
- **Visual Studio** provides bounded local FLUX.2 Vulkan still generation, review, guided image edits, Wan 2.2 image-guided motion, FastWan 2.2 native text-to-video, immutable revision lineage, candidate/project deletion, and exact binding to a Music candidate.
- The read-only motion qualification ledger compares retained duration, frame,
  delivery, elapsed-time, and human-review evidence without automatically
  declaring any profile aesthetically qualified.
- A reviewed still or short generated-motion candidate can become a music companion with framing, matte, fades, repetition where needed, and full-song audio muxing. A kept/exported song with a final visual can produce an editable exact local YouTube upload package. The owner-authorized upload A0 candidate adds a foreground Desktop OAuth flow, exact channel verification, digest-bound upload preview, resumable upload, reviewed thumbnail application, and private local receipt. Private is the default; nothing uploads automatically, and Soul never changes visibility after upload. Live upload acceptance remains open. A separate owner-authorized Description Sync A0 candidate can preview and replace only the exact NOC Thoughts URL block in explicitly mapped existing videos while preserving their remaining descriptions and snippet metadata; live metadata authorization and execution remain open.

Historical procedural camera movement is retired. The current generated-motion
lanes are explicit, short, review-gated candidates: image-guided Wan output is a
fixed resource-oriented study, while native FastWan output supports 4, 8, or 12
seconds at a delivered 24 fps. Longer companions repeat one accepted scene and
are labeled accordingly.

The operator-facing flows are documented in [`docs/guides/`](guides/).

### Administration

- **Backup & Recovery** inspects the configured encrypted restic repository,
  captures the exact owner allow-list through a reviewed gate, verifies and
  inventories snapshots, preserves deleted paths through a 30-day
  deletion-detection hold, and restores only into isolated owner-private
  staging. The first live encrypted capture passed verification on 2026-07-27.
  Retention remains exact and manual; live-tree promotion is not automated.
- Crucible provides a reboot-qualified, independently mounted 100 GiB XFS
  target at `/srv/soul-backup`, reachable through key-only SSH/SFTP. Backup &
  Recovery now has a candidate manual password-bearing gate to initialize the
  encrypted repository, copy missing snapshots, verify metadata, and prove
  coverage. Remote deletion and nightly execution remain disabled.

## Runtime topology

The stable chat API alias is `soul-local-chat`; actual model identity is reported separately.

- **Daily Core:** Gemma 4 12B Instruct Q4_K_M through Ollama/Vulkan on AMD.
- **AMD-Free Core:** Qwen3 8B Q4_K_M through llama.cpp/CUDA on NVIDIA.
- **Music Core:** Qwen chat on NVIDIA while ACE-Step 1.5 4B LM / 2B Turbo Q8_0 uses AMD/Vulkan only during bounded music generation.

Core changes are click-authorized and lease-revalidated. Before a conversational creative generation or revision action is offered, Soul reports the active Core, required Core, whether the click includes a transfer, and why. Music generation/revision requires Music Core; visual-only generation/guided revision requires AMD-Free Core; reviewed-source-only operations do not manufacture a transfer. The exact action click authorizes the disclosed transition and bounded operation together, while execution revalidates the requirement and delegates to the existing Core controller. Model text cannot initiate one and no failover occurs on its own. Music and image models do not remain resident. No idle-unload timer, unattended Core switch, worker queue, or background polling loop is present.

## Deployment

`make dashboard` runs a foreground loopback development instance. The reviewed optional deployment installs explicit user services for the loopback dashboard and Caddy HTTPS on one exact LAN address. Installation is preview-first, requires a changed administrator password and exact confirmation, and leaves firewall, DHCP, router, and client certificate trust to the Operator.

Hosting Soul itself on Proxmox, Internet exposure, and multi-user accounts
remain separate future tracks. Forge currently hosts the Warden Pi-hole
appliance and the Crucible Fedora backup/DNF5 laboratory. Backup & Recovery now
has a candidate-complete encrypted local
foundation and one verified live capture; retention execution, a second copy,
live-tree promotion, and full disaster-recovery qualification remain separate
review gates.

## Memory, artifacts, and deletion

Mutable owner memory lives under ignored `Soul/private/memory/`; tracked memory files are neutral public seeds. Durable promotion remains human-reviewed.

An optional external Knowledge Vault may supplement these canonical stores with
portable Markdown notes. Soul can inspect and search it in bounded foreground
operations, project approved memory into a generated index, and import one
explicit note as a candidate through an exact review gate. Obsidian is an
optional human surface rather than a dependency. The vault is never watched,
automatically synchronized, or treated as approved memory.

Local Project and Document Search unifies bounded lexical retrieval across
repository documentation, the configured Knowledge Vault, and canonical Music
and Visual project briefs. Results retain source adapters, canonical
references, exact searched-text digests, excerpts, and freshness metadata.
Search creates no index or memory, reads no arbitrary filesystem roots, and
does not treat retrieved text as authority.

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

- final human review of version-9 persona fidelity on Gemma and Qwen;
- interruption-aware duplex voice beyond the reviewed push-to-talk,
  per-message speech, and visible local wake-word presence paths;
- production hardening and documentation of creative workflows;
- additional Music Studio refinement based on real generations;
- motion-quality refinement based on reviewed image-guided and native scenes;
- broader visual-perception refinement beyond the implemented explicit,
  one-shot monitor, active-window, visible-workspace, and region paths;
- additional restore-registry applications only through separate identity,
  duplicate-detection, placement, and live review; and
- broader deployment only under its own review.

No release or stable tag has been created.

## Primary references

- [`README.md`](../README.md)
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)
- [`docs/ROADMAP.md`](ROADMAP.md)
- [`docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`](soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md)
- [`docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md`](soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md)
- [`docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md`](soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md)
- [`docs/guides/PROJECT_TIMELINE.md`](guides/PROJECT_TIMELINE.md)
