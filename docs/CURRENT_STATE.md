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
  ├─ Visual Studio
  └─ Mix Studio
Administration
  ├─ Project Timeline
  ├─ Memory Observatory
  ├─ Backup & Recovery
  └─ Guided Maintenance
Review Center
```

### Chat

Chat provides persistent multi-turn transmissions, explicit push-to-talk that records one bounded local utterance for local transcription and automatic submission through ordinary Chat, explicit bounded local speech for eligible completed Soul messages, immediate accepted-message rendering, truthful working summaries, local model responses, deterministic capability and skill routing, bounded research, shared artifacts, workspace metadata, inbox delivery, memory controls, system status, and manual model/Core controls. One explicit PNG or JPEG attachment plus a question can enter bounded local picture understanding through Gemma on Daily Core. The Operator may also request one current-monitor, active-window, or selected-region screenshot; Dashboard capture is explicit, foreground, and previewed before the existing picture-analysis path runs. Voice Presence accepts only deterministic explicit current-screen requests, checks for Daily Core before capture, retains no pixels, and leaves ordinary screen discussion conversational. There is no periodic capture, background watching, silent Core transfer, or screen control. Source pixels are discarded after the answer by default or retained owner-private with that conversation by explicit Dashboard checkbox; image content remains evidence and cannot authorize actions. Chat can also resolve exact Music Studio and Visual Studio project titles, read their stored briefs and bounded lineage, and—when explicitly asked—inspect an existing still or three sampled frames from an existing motion candidate without requiring the Operator to download and re-upload Soul's own artifact. Archive inspection is read-only and candidate pixels remain untrusted evidence. Explicit music, visual, or combined creative requests can enter a per-conversation bounded workflow: Soul preserves user-required decisions, drafts visible optional fields, presents an exact Core-aware generation action, and returns authenticated candidates for human review. Recorded music or still-image `revise` dispositions can continue through visible Soul-drafted revisions and exact linked generation actions. A kept or exact existing visual context can also prepare a 4-, 8-, or 12-second native text-to-video action; its WebM returns to Chat, while motion review stays in Visual Studio and a stored `revise` review can unlock one linked Chat revision. Combined flows can bind kept stills to kept songs, render reviewed static or generated-motion companions, export kept songs, and create exact local upload packages through separate gates. Recorded music `reject` may prepare permanent candidate deletion after a separate request. Merely mentioning skills, creative work, motion, revision, binding, export, or deletion does not invoke those capabilities.

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

Explicit Skill Studio inventory questions now use a deterministic read-only
projection shared by Chat and Voice Presence. Soul can report current proposal
stages, Beta run and test state, and production registry entries. Proposal
approval, Beta creation or execution, promotion, closeout, rejection, and
deletion remain exact Skill Studio actions and cannot be authorized by the
conversation response.

The first Fundamental Skill Cohort A1 candidate adds `files.inspect`. An
explicit Chat or Voice request can list one directory level, stat one path, or
read one bounded UTF-8 text file beneath a root approved in local `.env`
configuration. The portable default exposes only the project root. Absolute
paths from conversation, traversal, hidden paths, symlinks, secret-bearing
files, binaries, oversized reads, writes, recursive scans, indexes, caches, and
background continuation remain unavailable. The Operator accepted this slice
on 2026-08-02.

The second accepted cohort skill, `network.diagnose`, is a bounded foreground network
evidence surface. It may inspect local IP addresses and Linux routes, resolve
one target, send one fixed one-packet reachability probe, or attempt one
zero-payload TCP connection. It rejects scans, ranges, URLs, multiple targets,
retries, monitoring, and mutation. The Operator accepted this slice on
2026-08-02.

The third accepted cohort skill, `repository.inspect`, exposes one configured local
Git repository through bounded branch, HEAD, status, recent-log, staged-diff,
and working-tree-diff evidence. It uses fixed read-only Git commands with time
and output ceilings, excludes secret-shaped paths, withholds credential-like
diff content, and cannot mutate or contact a remote. The Operator accepted this
slice on 2026-08-02.

The fourth accepted cohort skill, `workspace.artifact.compose`, gives the mature
Phase 11C/11D artifact workflow a modern public skill identity without adding a
second writer or approval path. Explicit Chat or Voice deliverables draft one
bounded local-provider preview; an expiring digest-bound token gates exclusive
verified creation, canonical attachment, revision lineage, and shared-workspace
delivery. The Operator accepted this slice on 2026-08-02.

The fifth and final accepted cohort skill, `web.research`, packages Soul's existing
bounded SearXNG/Brave research service, direct CLI, and Chat/Voice evidence path
without adding another HTTP client or application operation. Provider queries,
public-source SSRF defenses, provenance, foreground ceilings, grounded artifact
handoff, and separate reflection and memory gates remain intact. The Operator
accepted this slice on 2026-08-02, completing Fundamental Skill Cohort A1.

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

Voice Presence A4 is a local-only latency candidate. It uses a bounded
trailing-silence endpoint of 0.95 seconds so a natural mid-sentence pause is not
mistaken for the end of the turn, calibrates `Hey Soul` at boost 3.5 and
threshold 0.15, selects exact `base.en` for conversational transcription
while retaining `small.en` for Music Studio analysis, and preloads Supertonic
as a private-pipe child of the visible application. Content-free per-stage
timings are visible for the active turn only. Narrow repeat requests replay the
byte-identical latest session WAV without another model or synthesis call; the
cache and warm child disappear on pause, restart, or close. Ordinary Voice
Presence conversation also requests the local provider's reviewed no-reasoning
mode under a 384-token spoken-response ceiling. Explicit deliberation phrases
retain normal reasoning, and Dashboard text inference is unchanged. Live wake,
false wake, latency, replay, and pronunciation review remains required.

When a narrow stable-knowledge question produces no DuckDuckGo Instant Answer
and no research backend is configured, Soul now falls back explicitly to the
selected local model's general knowledge. It does not present that answer as
retrieved or sourced. Requests requiring current, consequential, comparative,
or cited evidence continue to use the bounded research path.

The installed wake-sensitivity update, natural follow-up behavior, dashboard
self-recognition map, notification cues, spoken notices, screen targeting, and
Core-aware invocation handoff completed Operator live acceptance on
2026-07-27. Minor refinements remain ordinary follow-up work rather than open
release gates.

Dashboard notification delivery now has full voice, priority voice, cues-only,
and muted modes. Submission, wake, completion, and attention cues are static
local assets. Priority Voice limits speech to material attention such as a
fleet degradation, reboot requirement, or backup verification issue; a first
fleet snapshot is deliberately silent. Review-ready music, visual, lyric,
improvement, and recovery events remain visible in the exact Dashboard record.
When Voice Presence is visibly open and idle-listening, Chat, music, visual,
lyric-analysis, improvement, and recovery completions may additionally use a
pre-generated notice in the selected F3 or M3 voice. Each event performs one
point-in-time status check; there is no polling or event-time synthesis.

Voice Presence can also opt into observing the standard desktop-notification
D-Bus method while its own visible window remains open. It does not replace or
control Noctalia. The first reviewed cohort classifies Discord, Webex, Teams,
and Steam from application metadata only; notification titles, bodies, images,
actions, and history are never retained. Normal items remain visual-only. A
recognized high-urgency communication may use one cooldown-limited static
notice while Soul is idle-listening. Browser-originated sites and native popup
windows remain outside this narrow observer and are never guessed from screen
content.

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

- **Skill Studio** separates Proposals, Operator-invoked Beta candidates, and Production skills. Gate 1 approves exact scope; the reviewed local GPT-OSS Dev lane can draft one proposal-local read-only candidate and run it through networkless deterministic checks; Gate 2 approves an exact tested revision; production promotion and completed-proposal closeout remain separate mutations. GPT-OSS-generated Betas remain sandboxed during human trials.
- **Self Assessment** collects bounded host, update, runtime, capability, and storage evidence. A separate digest-bound Dev synthesis gate can record evidence-linked observations and explicit unknowns from the latest scope, but cannot change evidence or invoke follow-on work. Long-running synthesis persists as one reconnectable bounded job; Dashboard-process interruption fails visibly without automatic replay. Advisory proposals remain available, while host maintenance, reboot, and verification are owned exclusively by Administration → Guided Maintenance.
- **Self Augmentation** creates human-authored architecture proposals, exact allowed-file experiments in isolated worktrees, deterministic candidate dossiers, and external integration handoffs. An optional pre-gate GPT-OSS critique can review one proposal without selecting files or deciding Gate A1. After Gate A1, a separate digest-bound GPT-OSS action can translate the exact experiment, proposal, original handoff, and allowed-file scope into an owner-private advisory implementation handoff for human/Codex review. Both GPT-OSS actions use the reconnectable single bounded-job lane and fail closed across Dashboard restart. They cannot inspect or edit the worktree, emit code or commands, add paths, decide Gate A2, invoke Codex, merge, push, or deploy.

The current Core taxonomy is Soul Core (`daily`), Soul-Lite Core (`amd-free`),
Creative Core (`music`), Free Core (`free`), and Dev Core (`dev`). Free Core
unloads all chat and development models and locks the Dashboard to Core
selection. Dev Core pairs Qwen chat on NVIDIA with digest-pinned GPT-OSS 20B on
AMD. Scoped Dev work restores the prior eligible Core and never preempts
Creative work. The 2026-08-03 live matrix confirmed Creative blocking,
Soul-Lite and Soul Core restoration, and resident GPT-OSS reuse across two
selected-Dev requests. The repair merged through PR #130 prevents shared
Soul-Lite/Creative intent changes from re-entering the model-runtime lease
lock; the restarted Dashboard service is running that revision. Mistral
remains an explicit fallback only.

Primary Codex can also invoke GPT-OSS through the repository-local Soul Dev
Worker skill. Codex supplies one exact non-secret context packet; Soul returns
schema-validated analysis, critique, or candidate unified-diff text without
repository, shell, network, test, Git, approval, or merge authority. Native
Codex delegation now uses Spark's separate allowance for repository mapping
while it is available, then falls back to Luna Low. Luna High is the default
bounded implementation and substantive-review worker; Terra Medium is reserved
for integration ambiguity or coupling that Luna cannot resolve confidently.
Primary Sol retains architecture, sensitive authority, and final integration.
Exact assignment contracts support evidence-trusted mapping and change-trusted
reversible work without automatic full re-review by a more expensive model.
API rates are treated only as a relative-cost proxy, never as proof of Codex
subscription accounting. Security, credentials, privileged or destructive
behavior, persistence, remote maintenance, backup/recovery, and final
integration remain independently verified by primary Sol. See
`docs/guides/CODEX_SUBAGENTS.md` and `docs/guides/DEV_WORKER.md`.

### Creative Studios

- **Music Studio** stores immutable project briefs and candidate lineage; supports exact whole-second AMD Vulkan ACE-Step generation from 30 seconds through 5 minutes plus a fixed 10-minute option; preserves exact `[Instrumental]` no-vocal conditioning while allowing bounded instrumental movement timing in Sound and Structure; creates FLAC masters and MP3 proxies; follows durable jobs across page navigation; records generation timing, CPU vocal evidence, human review, revision drafts, lawful reference profiles and fusions, rejection, export, and one-generation source-preserving trim copies. A short/long variable-duration qualification passed technically at 43 and 248 seconds; musical acceptance remains human review.
- **Visual Studio** provides bounded local FLUX.2 Vulkan still generation, review, guided image edits, Wan 2.2 image-guided motion, FastWan 2.2 native text-to-video, and a candidate Blender 5.2 EEVEE lane for editable audio-reactive whole-bar procedural scenes. A separate nonpublishable 30-second Blender study compares one curated-asset orbital scene against three exact earlier candidates; its two reviewed Poly Haven CC0 assets are installed explicitly, verified by size and SHA-256, packed into the private `.blend`, and never fetched during rendering. All production lanes preserve immutable revision lineage, candidate/project deletion boundaries, and exact Music-candidate binding.
- **Mix Studio A0/A1/A2** inventories only keep-reviewed finished exports whose stereo
  master and supporting metadata still match their recorded hashes. It creates
  immutable edit decision lists with bounded trims, incoming crossfades,
  transition notes, and deterministic cue timing. An exact click gate can copy
  the verified stereo masters with a JSON EDL, CSV cue sheet, README, and
  `sha256sum`-compatible manifest for a conventional editor. A separate exact
  foreground gate can render the sealed plan into a private FLAC and 320 kbps
  MP3 listening candidate with authenticated dashboard playback. A2 records
  the Operator's sequencing and transition review with preserved correction
  history. Only the latest exact `keep` review can export the verified A1 FLAC
  and MP3 with JSON metadata, a human-readable summary, and checksums beneath
  `~/Music/soul-music/mixes/finished`. The accepted audio is not mastered,
  published, visually assembled, inferred into stems, or claimed as a native
  DAW project.
- The read-only motion qualification ledger compares retained duration, frame,
  delivery, elapsed-time, and human-review evidence without automatically
  declaring any profile aesthetically qualified.
- A reviewed still or short generated-motion candidate can become a music companion with framing, matte, fades, repetition where needed, and full-song audio muxing. A kept/exported song with a final visual can produce an editable exact local YouTube upload package. The accepted owner-authorized upload path adds a foreground Desktop OAuth flow, exact channel verification, digest-bound upload preview, resumable upload, reviewed thumbnail application, and private local receipt. One supervised private upload completed on 2026-07-30; private remains the default, nothing uploads automatically, and Soul never changes visibility after upload. A separate owner-authorized Description Sync A0 candidate can preview and replace only the exact NOC Thoughts URL block in explicitly mapped existing videos while preserving their remaining descriptions and snippet metadata; live metadata authorization and execution remain open.

Historical procedural camera movement is retired. The current generated-motion
lanes are explicit, short, review-gated candidates: image-guided Wan output is a
fixed resource-oriented study, while native FastWan output supports 4, 8, or 12
seconds at a delivered 24 fps. Longer companions repeat one accepted scene and
are labeled accordingly.

The operator-facing flows are documented in [`docs/guides/`](guides/).

### Administration

- **Project Timeline** provides the shared, explicitly maintained owner-local
  implementation ledger through the Dashboard and deterministic Chat controls.
- **Guided Maintenance** consumes fresh read-only assessment evidence and
  previews the exact trusted pacman repository and Flatpak transaction plus a privacy-filtered
  Hyprland restore map. A1 remains read-only. The accepted A2 path adds a
  visible, bounded terminal executor and no-mutation rehearsal. A2B adds a
  single-use XDG desktop handoff so native package evidence and an approved
  transaction can run outside the deliberately confined Dashboard without
  weakening its systemd sandbox. Native one-password execution remains the
  portable public default. The Operator's historical A4 v3 authority completed
  supervised combined maintenance on 2026-07-29; A11 now retires unattended
  AUR execution. The A11 root helper can update only trusted repositories and
  Flatpak. Pending AUR updates remain visible and require a separate expiring,
  digest-bound interactive terminal with clean/diff/PKGBUILD menus and no
  predetermined answers. The exact A11 v1 helper was installed and passed its
  native passwordless self-check on 2026-08-02; no AUR update was pending for a
  live interactive observation. The device-card UX
  collects and rechecks stale native evidence, retains the exact human-reviewed
  click gate, and refreshes the card from the exact terminal receipt. A2 always
  stops before reboot. Reboot is a distinct A3 transaction with its own
  preview, digest, journal, and authorization; package-command vectors must be
  empty, so it cannot rerun `yay`, pacman, or Flatpak. The accepted zero-prompt
  reboot-only path completed again on 2026-08-09 with no package replay or
  password prompt. All three displays, the active workspace, Vesktop, Steam,
  Teams, Opera GX, and Codex Desktop restored; Steam launched no game. Webex
  remained the sole bounded application result and is now an accepted manual
  post-login action. The pending journal was consumed, and the Operator accepted
  the orchestration as implemented. Both live gates remain disabled outside an
  exact supervised transaction. Portable status-only devices retain compact LAN cards; the
  current Apple-mobile candidate can additionally attach a privacy-filtered
  wired product/iOS/battery projection after an exact reviewed private-MAC
  match, without granting device mutation authority.
- Fleet status emits the portable canonical device ID `workstation`. The former
  `maven` ID and `SOUL_FLEET_MAVEN_*` environment names remain bounded read
  aliases for existing private state; newly written snapshots, topology,
  refresh results, and tracked examples use `workstation` and
  `SOUL_FLEET_WORKSTATION_*`.
- **Crucible** is the optional Fedora 44 KVM fleet member on Forge. Its base
  integration collects bounded live DNF5, kernel, reboot, SSH, and guest-agent
  evidence. The D1 candidate replaces cloud-init's broad passwordless rule
  with a SHA-256-bound root helper exposing only self-check, one fixed DNF5
  upgrade, and one fixed reboot. Exact helper status unlocks device-scoped
  Maintenance and Reboot; a missing or invalid helper falls closed to
  inventory-only. The 173-package live update completed with a terminal
  receipt and zero updates remaining. A post-run correction now compares a
  freshly probed running kernel with the newest installed kernel instead of
  trusting DNF5's incomplete reboot signal. The separately authorized reboot
  returned with a new boot identity, passed all four readiness checks, and now
  reports the current `7.1.5` kernel, zero updates, and Healthy state.
  Operator-managed reservations provide stable identities for the workstation,
  Forge, the Pi-hole appliance, and Crucible. Deployment-specific card names
  remain ignored local configuration; public source preserves functional roles
  and stable IDs.
- Guided Maintenance separates rich **SSH integrated** cards from compact
  **Status only** network-presence cards. Each surface lays out independently,
  preserving compact status-only rows as the fleet grows.
- **Fleet Operations Evidence A0** is candidate-complete for Operator review.
  Guided Maintenance now projects the latest retained transaction per control
  target beside newer persisted fleet evidence. Execution and reconciliation
  remain separate: newer assessed evidence can verify the narrow maintenance
  or reboot goal, report attention, remain pending, or stay unknown without
  turning command completion into a health claim. The projection is bounded,
  deterministic, address-free, read-only, and introduces no collection,
  schedule, agent, generic command, or fleet-wide authority.
- **Host Stewardship A0–A2** is Operator-approved and merged. Its
  static capability registry distinguishes availability from authority; Host
  Presence composes bounded current host/Core evidence with source-attributed
  persisted security and backup-automation status only when requested. File
  Steward uses a separate, empty-by-default `SOUL_FILE_STEWARD_ROOTS` allowlist
  for one-level inventory and exact regular-file rename, move, copy,
  quarantine, and restore. Every mutation is digest-bound, revalidated, and
  receipt-backed. Overwrite, recursion, symlinks, hidden/secret-shaped paths,
  hard links, directory mutation, and permanent deletion remain unavailable.
- **Software and Storage Steward A0–A1** is candidate-complete for Operator
  review. Software inventory reports bounded pacman, foreign/AUR, orphan,
  Flatpak, and public Arch security evidence without package mutation. Storage
  inventory reports bounded device, filesystem, NVMe, and configured Btrfs
  compression evidence without paths, serials, command lines, or storage
  mutation. I/O diagnosis remains a separate one-shot request and does not
  elevate when `iotop` is unavailable to the Dashboard process.
- **Incident Narrator A0** is candidate-complete for Operator review. It composes only
  retained normalized Wazuh, maintenance-receipt, and backup/DRS evidence into
  a deterministic newest-first chronology. Observations, cautious inference,
  and missing evidence remain distinct; raw alert descriptions, paths, command
  lines, credentials, model use, source refresh, and remediation are excluded.
- **Fleet Historical Telemetry and Observability A1** is deployed, technically
  qualified, and Operator-approved. A dedicated
  unprivileged guest runs Prometheus, Loki, Grafana, and Caddy; Caddy alone
  exposes the private HTTPS 443 application surface while every datastore and
  collector control surface remains on loopback. A key-only, non-root SSH
  management plane exposes only digest-bound APT maintenance and reboot
  operations to Soul. Four explicitly enrolled Linux roles deliver pinned
  Alloy Unix metrics under stable low-cardinality identities. Prometheus keeps
  at most 30 days and 28 GB, Loki keeps at most 14 days, and raw telemetry stays
  outside Restic/DRS. Journal collection, alerts, Soul query integration, and
  telemetry-driven mutation remain disabled; Wazuh is still the security
  authority.
- **Fleet Observability A1.1** is deployed, technically qualified, and
  Operator-approved. It keeps
  the approved collection topology unchanged while adding a compact freshness
  and health overview, collapsed compute, storage, network, service, stability,
  thermal, and power rows, and an owner-private approximate global-presence
  marker. The public dashboard contains location placeholders only.
- **Fleet Observability A2/A3** is candidate-complete and partially
  live-qualified. Observatory now has six dashboard-only operational alerts,
  reboot and redacted maintenance overlays, host-network evidence, and an
  owner-private SNMP lane. Soul exposes one fixed, foreground, read-only
  summary through Host Stewardship, explicit Chat/Voice questions, and Incident
  Narrator, with a private Grafana drill-down and no arbitrary query or mutation
  authority. Four Linux endpoints and one reviewed switch are reporting; the
  second switch remains an explicit SNMP source gap. All four enrolled collectors now apply the exact
  redacted maintenance-unit journal filter. Operator visual and conversational
  review is still required. The overview distinguishes labeled CPU-package,
  NVMe-composite, and chipset temperatures, rejects impossible values, and
  correlates package temperature directly with CPU activity.
- **Security Monitoring** is live and read-only. Wazuh remains the authoritative
  investigation console; Guided Maintenance and Local Topology show accepted
  manager, exact agent, alert, notification, and adapted-posture projections.
  The posture layer now accepts a bounded owner-private set of independently
  scan-bound endpoint reviews: Atelier and Crucible retain separate raw scores,
  exact device cards select only their associated agent review, and aggregate
  Chat/Voice status never invents a fleet compliance percentage.
  Chat and Voice Presence share one deterministic `security.status` invocation
  for explicit questions such as `How does security look?`. It refreshes the
  bounded A4a/A4b evidence in the foreground and retains aggregate counts only.
  Raw events, alert descriptions, ClamAV freshness, acknowledgement,
  suppression, quarantine, and remediation are unavailable.
- **Backup & Recovery** inspects the configured encrypted restic repository,
  captures the exact owner allow-list through a reviewed gate, verifies and
  inventories snapshots, preserves deleted paths through a 30-day
  deletion-detection hold, and restores only into isolated owner-private
  staging. The first live encrypted capture passed verification on 2026-07-27.
  Retention remains exact and manual; live-tree promotion is not automated.
- Crucible provides a reboot-qualified, independently mounted 100 GiB XFS
  target at `/srv/soul-backup`, reachable through key-only SSH/SFTP. Backup &
  Recovery's manual gate initialized the independently encrypted repository,
  copied the accepted snapshots, verified metadata, and proved exact
  coverage through original-snapshot lineage. Both repository passwords were
  subsequently rotated through a local echo-disabled gate. Remote deletion
  remains disabled.
- Nightly DRS A2/A3 is live-qualified on the Operator workstation. One
  host-encrypted user credential feeds a hardened, no-restart systemd
  `oneshot` that reuses the accepted A1 transaction. The 2026-07-29
  qualification created local snapshot `7b5c625e…c54ba1`, verified its exact
  lineage among six Crucible snapshots, and completed in 26 seconds. The
  permanent timer is enabled for 3:00 AM local time with no retry, pruning,
  remote deletion, or unattended restore authority.

## Runtime topology

The stable chat API alias is `soul-local-chat`; actual model identity is reported separately.

- **Daily Core:** Gemma 4 12B Instruct Q4_K_M through Ollama/Vulkan on AMD.
- **AMD-Free Core:** Qwen3 8B Q4_K_M through llama.cpp/CUDA on NVIDIA.
- **Music Core:** Qwen chat on NVIDIA while ACE-Step 1.5 4B LM / 2B Turbo Q8_0 uses AMD/Vulkan only during bounded music generation.

Core changes are click-authorized and lease-revalidated. Before a conversational creative generation or revision action is offered, Soul reports the active Core, required Core, whether the click includes a transfer, and why. Music generation/revision requires Music Core; visual-only generation/guided revision requires AMD-Free Core; reviewed-source-only operations do not manufacture a transfer. The exact action click authorizes the disclosed transition and bounded operation together, while execution revalidates the requirement and delegates to the existing Core controller. Model text cannot initiate one and no failover occurs on its own. Music and image models do not remain resident. No idle-unload timer, unattended Core switch, worker queue, or background polling loop is present.

## Deployment

`make dashboard` runs a foreground loopback development instance. The reviewed optional deployment installs explicit user services for the loopback dashboard and Caddy HTTPS on one exact LAN address. An optional validated private DNS hostname may provide the certificate and application authority without changing that exact-IP bind. Installation is preview-first, requires a changed administrator password and exact confirmation, and leaves DNS records, firewall, DHCP, router, and client certificate trust to the Operator.

Hosting Soul itself on Proxmox and Internet exposure remain separate future
tracks. Multi-user accounts are a deliberate non-goal: Soul is designed as a
single-Operator experience. Forge currently hosts the Warden Pi-hole appliance
and the Crucible Fedora backup/DNF5 laboratory. Backup & Recovery now has an
accepted encrypted local foundation, verified live captures, and an accepted
encrypted second copy on Crucible. The supervised DRS transaction,
host-encrypted unattended credential, and nightly 3:00 AM activation are
live-qualified. Remote retention, live-tree promotion, and full isolated
disaster-recovery rehearsal remain separate review gates.

## Memory, artifacts, and deletion

Mutable owner memory lives under ignored `Soul/private/memory/`; tracked memory
files are neutral public seeds. The Operator has approved a transition from
per-record review to standing autonomous authority for ordinary memory when
changes are local, attributable, reversible, recoverable, and governed by a
reviewed deterministic policy. Protected authority, security, identity,
credential, export, physical-purge, and broad-retention changes remain explicit
human decisions.

Memory Retrieval and Observatory A0–A32 is implemented and production-qualified,
including final human Voice semantic-recall acceptance. A
synthetic deterministic corpus compares lexical and hybrid recall, an optional
owner-private index is source- and payload-digest bound, and Administration
exposes a read-only ledger/index summary plus one explicit diagnostic query.
Only active approved records are eligible. Invalid or stale derived state falls
back to approved-only lexical retrieval, and the Observatory has no mutation
controls, polling, service installation, automatic model download, or Core
switch authority. Ordinary Chat now admits fresh hybrid results by canonical
memory ID, re-reads approved content from the ledger, and otherwise preserves
the prior lexical context exactly. A7 qualifies the local Qwen3 0.6B Q8_0
embedding profile at a 1024-token ceiling and adds a reviewed inactive,
unenabled endpoint whose lifecycle follows explicit Core selection. Non-Free
Cores may start it; Free Core stops it. The model remains demand-loaded and
semantic failure still preserves lexical retrieval. Live preview/execute
acceptance has exercised every Core and restored Soul-Lite successfully. The
Dashboard performs at most two delayed read-only status checks after a
successful Core activation so short runtime-readiness or lease-settlement
windows do not masquerade as a failed transition; it never retries the
mutation.

The A5 surface adds bounded runtime inventory and a fixed owner-private review.
A6 provides a separately gated,
one-time bootstrap for installations whose canonical ledger is empty: only
top-level bullets from the existing owner-reviewed rules and lessons files may
be projected through append-only creation and approval events. The projection
is content-free at its response boundary, idempotent, and does not include
private YAML, draft lessons, index rebuilding, or runtime lifecycle changes.
The live A6 bootstrap imported 32 reviewed rules and lessons through 64 valid
append-only lifecycle events; owner-private review fixtures and derived vectors
remain ignored local state.

Memory Automation Governance A9-A10 is implemented. It can adopt the existing
canonical ledger in place, add a tamper-evident event chain, reconstruct
point-in-time lifecycle state, and append compensating rollback without
changing ordinary retrieval or migrating the Soul Vault. Live owner-private
ledger adoption completed on 2026-08-24 and its complete post-baseline chain is
verified.

Conversation Observation Capture A11 is deployed and has captured its first
post-deployment live Dashboard exchanges during end-to-end qualification.
Every successfully completed application chat turn is mirrored as an ordered,
cross-segment hash-chained pair of exact user and assistant source observations
in ignored owner-private storage. Canonical history rotates through bounded
32-MiB segments without a lifetime retention ceiling; normal capture validates
only the active segment and uses a rebuildable, content-free sharded index for
historical idempotency. Explicit integrity verification walks the entire
history. Capture and integrity receipts remain content-free, request replay is
idempotent, and a capture failure does not erase the already persisted chat
response. Observations do not enter ordinary retrieval.
Memory Observation Derivation A12 is live-qualified. One explicit
foreground invocation can verify and consume at most twelve newly captured
exchanges, make one bounded local-model synthesis request, and append a strict
private proposal packet. The append-only packet is evidence for the later
deterministic lifecycle engine: it does not write canonical memory or enter
retrieval. Empty valid results advance the packet-derived cursor; failures do
not. Deterministic protection classification cannot be downgraded by model
output, and public receipts remain content-free.

Memory Lifecycle Admission A13 is live-qualified. Verified ordinary
proposals are admitted or rejected by deterministic evidence, confidence, and
protection policy; admitted mutations share an auditable compensatable
transaction. Memory Live Qualification A14 adds a supervised foreground
capture-to-derivation-to-admission-to-retrieval-to-compensation harness using
the existing local GPT-OSS Dev lane. Its deterministic fixture and live
qualification are complete: one real Dashboard fact produced one local-model
proposal, deterministic active admission, cross-chat ordinary-memory recall,
exact audited compensation, direct retrieval abstention, and fresh-chat
non-recall. The canonical audit and all derived ledgers remained valid after
compensation.

Historical Chat Backfill A15 is live-qualified. A content-free,
digest-bound foreground preview selects at most 50 complete uncaptured
exchanges from at most 25 persisted active or archived chats after a bounded
500-chat/20,000-message scan; exact execute
appends them through the existing A11 identity and chain protections. The live
owner-private pass captured all 15 outstanding exchanges (30 messages) across
two chats, then reached `no_work` with a valid 38-event observation chain. It never
manufactures incomplete turns, invokes a model, mutates canonical memory, or
continues in the background.

Memory Autonomous Lifecycle A16 is live-qualified. One explicit foreground
cycle drains one older verified derivation packet when present; otherwise it
derives one bounded packet and immediately passes that exact packet through the
A13 deterministic admission policy. Stable sub-request identities and a
content-free hash-chained cycle journal make interrupted retries reconcilable
without duplicate proposals or canonical records. Protected proposals remain
blocked for human review. The Core-aware scheduled worker, the 3D Observatory,
and Foundry-hosted Qdrant/FalkorDB projections remain subsequent reviewed
slices. The first live Dev Core cycle admitted one active ordinary memory from
the historical observation batch; exact replay was idempotent and all audit,
observation, derivation, admission, and cycle chains remained valid. Redis is
not required for this program stage.

Memory Core-Aware Worker A17 is installed and live-qualified. Its systemd user
timer runs a hardened oneshot activation only after a
verified pending-work check. It skips Free and Creative Cores, abstains from
model loading when no work exists, and processes at most one A16 cycle per
activation. Soul Core may use the existing reviewed temporary Soul-Lite handoff;
Soul-Lite and Dev Core can run directly. Installation remains behind an exact
fresh-plan digest and confirmation phrase, and live timer cadence, Core
restoration, and busy-lane behavior remain human acceptance tests.
The exact worker entry point is foreground-live-qualified under Dev Core: it
processed the remaining historical batch, correctly rejected one proposal that
lacked cited user evidence, then returned `no_work` on the next invocation
without model use or canonical mutation. All underlying evidence chains remain
valid. The exact reviewed timer was installed and enabled on 2026-08-24; its
first scheduled activation detected Dev Core and returned `no_work` with no
model invocation or mutation, then terminated successfully.

Memory Rebuildable Projection A18–A29 is deployed and production-qualified. It
deterministically maps the authoritative ledger and its
verified approved-memory embedding index into a private Qdrant vector bundle
and a content-free FalkorDB relationship graph. Raw memory text remains on
Atelier: Qdrant receives vectors plus minimal metadata and returns canonical
memory identifiers for a local join; FalkorDB receives lifecycle/provenance
metadata and only explicit supersession or exact-duplicate edges. Both stores
are disposable, non-authoritative, and fail back to local retrieval. The
owner-private Foundry deployment is active behind authenticated TLS, while
Atelier retains canonical content and local join authority.

Memory Projection Deployment A19 is installed and live-qualified in a dedicated
unprivileged Debian 13 LXC,
2 vCPUs, 2 GiB RAM, 512 MiB swap, and 24 GiB local storage. It deliberately
avoids nested Docker: Qdrant uses the checksum-pinned official 1.19.0 Debian
asset, Debian supplies signed Redis 8, and FalkorDB uses its checksum-pinned
4.20.4 module. Only authenticated TLS database ports from one fixed private
client are allowed; plaintext ports, browser UIs, public ingress, raw remote
memory content, reverse synchronization, and canonical mutation are prohibited.
The deterministic planner validates owner-private deployment evidence and
produces a content-free digest-bound plan. Installation required explicit
adoption of the A19 brief and its exact confirmation; later rebuilds remain
bounded, digest-bound foreground operations.

An optional external Knowledge Vault may supplement these canonical stores with
portable Markdown notes. Soul can inspect and search it in bounded foreground
operations, project approved memory into a generated index, and import one
explicit note as a candidate through an exact review gate. Obsidian is an
optional human surface rather than a dependency. The vault is never watched,
automatically synchronized, or treated as approved memory.

Storage & Retention A2 now provides a read-only artifact-class and backup
coverage census across Chat, memory, private state, Music/Visual projects,
finished exports, Studio workflows, maintenance, staging, caches, models, and
the local Knowledge Vault. The current verified path manifest and accepted
Crucible replica inventory all 32 required durable artifact classes, including
the Vault, chats, core private state, creative projects, and finished exports.
Private Git history for the Vault remains supplementary rather than replacing
Restic.

Backup Manifest Reconciliation A0 is live-accepted: five durable sources and
seven portable exclusions were added with zero removal or replacement. The
strict-additive retention repair is merged and live. The final verified
snapshot, canonical retention ledger, owner-private receipt, and accepted
Crucible replica agree; all 32 required artifact classes are verified with no
coverage or exclusion gaps.

Bounded Storage Cleanup A3 is accepted as a review-gated
foreground executor for only three
accepted categories: allowlisted temporary review residue older than 24 hours,
regular project logs older than 30 days, and failed partial Music quarantine
trees older than 24 hours with no active Music lease. Preview binds a
metadata-only recursive identity; execute revalidates exact scope, stages in
the same parent, verifies inode identity, and removes only the reviewed trees.
Protected data and every other artifact class remain non-executable. Preview
evidence does not grant deletion authority. No automatic cleanup or manifest
mutation exists.

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
The seed is intentionally first-use only. A later mismatch with the revisioned
owner ledger can be repaired only through an explicit, additive manual
reconciliation that preserves private-only records and current revisions.

Conversations, skill candidates, music projects, visual projects, reference profiles, logs, and generated artifacts have explicit lifecycle boundaries. Reversible archive/Trash behavior is preferred where appropriate. Permanent deletion exists only for previewed exact scopes and preserves separately exported finished files where the relevant workflow says so.

## Human authority boundary

Soul may inspect, explain, draft, research, stage, generate, test, and produce evidence. It may not treat model output, passing tests, successful generation, or a machine-heard result as authorization.

Human approval remains required for risky or destructive execution, protected
memory or rule promotion, skill and augmentation gates, production
registration, host mutation, provider/privacy exceptions, service installation,
merge, release, upload, and publication. Verified ordinary memory may move
through the separately reviewed deterministic lifecycle policy.

The deployed owner-private Qdrant and FalkorDB services remain disposable,
content-free projections. A21 defines a bounded generation coordinator: both
generation-specific stores must verify before one owner-local selector can
activate their exact pair. A22 adds verified TLS transports, exact bounded
readback, owner-private atomic selector persistence, and one foreground
preview/execute command. Failure leaves local authoritative retrieval and the
previous selector intact. The first exact generation is now live-qualified and
active after verified population of 33 Qdrant vectors, 34 FalkorDB nodes, and 5
explicit edges. Local retrieval remains authoritative; automatic projection
routing, rollback, and retirement remain later reviewed gates. A23 adds a separate
foreground diagnostic query that can rank identifiers through the active
Qdrant generation and inspect only explicit FalkorDB relationships, then joins
all returned content from the canonical local ledger. It rejects stale or
malformed projection evidence and falls back to the existing local retrieval
service. This path is live-qualified but intentionally not routed into Chat or
Voice until comparative ranking and abstention behavior are reviewed.
A24 adds a content-withholding foreground qualification harness over a fixed
owner-private positive/negative corpus. It compares the existing local path
with A23 projection candidates across a closed 0.50..0.80 threshold sweep, but
cannot select a winner, change production behavior, or route Chat/Voice.
The first private live run covered 11 positive and 5 negative cases. Its
diagnostic command later proved not to load the production `.env`, so its
`0.65` result is retained as historical A24/A25 evidence rather than current
production proof.

A25 compared three fixed hybrid strategies without changing routing. A26 adds
an owner-private, atomic, audited, reversible selector. A27 routes both ordinary
Chat and Voice Presence through one adapter that uses projection evidence as a
gate, preserves local ordering, and re-reads approved content from the canonical
ledger. A29 corrected the diagnostic environment, retained A25 unchanged for
audit and rollback, and activated the distinctly named
`projection_gate_local_order_a29` profile at `0.55`. The production-facade
qualification completed all 16 reviewed cases with 11/11 positive hits, 5/5
negative abstentions, zero forbidden hits, and mean positive reciprocal rank
`0.881818`. Projection failure returns to local retrieval without changing the
active selector or canonical memory.

A28 and A32 provide a deterministic rotatable Canvas starmap in Memory Observatory
alongside the existing 2D constellation and lifecycle layouts. All modes retain
the 240-node/400-explicit-edge caps and expose metadata only; depth is visual
presentation, not inferred semantic topology. Deterministic closure through
A32 passes. Authenticated human review approved the 3D interaction, fallback
modes, accessibility, privacy, and aesthetics. Final Voice experience
acceptance passed on 2026-08-25 through durable-fact recall, paraphrased
follow-up, unsupported-fact abstention, and verification that canonical memory
and the active projection remained unchanged. Residual wake-phrase misses are
a separate Voice Presence tuning concern rather than a memory-closure blocker.

Memory Exact-Duplicate Consolidation A30 and Lifecycle Maintenance A31 are
approved, integrated, and live-qualified. One Core-aware worker activation can
supersede at most one same-layer approved ordinary
memory whose content differs only in surrounding or repeated whitespace. It
uses deterministic confidence/age/identifier survivor ordering, excludes any
protected group, emits canonical audit and rollback evidence, and exposes no
memory content. It does not perform semantic similarity, conflict resolution,
rewriting, physical deletion, or projection mutation. The approved A31
coordinator gives ordinary observation lifecycle work priority, integrates the
exact-duplicate operation into the existing A17 one-shot timer, and reports a
stale projection as a separate reconciliation consequence. It never rebuilds
the projection within that canonical activation. A33 is candidate-complete:
it records a durable content-free request after a canonical mutation, and only
a later eligible A17 activation may rebuild the local index and activate one
dual-verified remote generation. Missing requests recover from digest drift,
work is bound to the canonical audit head, and automatic retries block after
three failures. Live timer-driven A33 acceptance remains pending. The first
bounded owner-private consolidation and
its separately confirmed projection rebuild completed successfully; current
worker evidence returns `no_work` without model use or mutation.

### Deterministic memory lifecycle admission and foreground cycle

Verified A12 proposal packets can now be processed one packet at a time by a
foreground deterministic policy. Protected, assistant-only, and weakly
supported proposals are excluded; medium-confidence ordinary proposals remain
candidates; high-confidence ordinary proposals can become active. Canonical
writes use the A10 audit chain and compensatable transaction references, while
a separate content-free hash-chained decision journal records why each proposal
was handled. A16 can now run derivation and admission as one explicit bounded
foreground cycle with interruption-safe replay. No background execution,
automatic chat trigger, consolidation, or external vector/graph projection is
enabled in this slice.

## Current development focus

The foundational Conversational Soul milestone is complete. Deployment/Core orchestration, Self Improvement, Music Studio, Visual Studio still and short-motion lanes, and local publication packaging are implemented and under owner use.

Near-term work is expected to concentrate on:

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
