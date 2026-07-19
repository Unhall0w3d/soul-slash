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

Chat provides persistent multi-turn transmissions, immediate accepted-message rendering, truthful working summaries, local model responses, deterministic capability and skill routing, bounded research, shared artifacts, workspace metadata, inbox delivery, memory controls, system status, and manual model/Core controls. Explicit music, visual, or combined creative requests can enter a per-conversation bounded workflow: Soul preserves user-required decisions, drafts visible optional fields, presents an exact Core-aware generation action, and returns authenticated audio/image candidates for human review. Merely mentioning skills or creative work does not invoke the catalog or start generation.

The dashboard has one personal administrator boundary. First-run `admin` / `soul123` access is limited to mandatory password replacement. Salted credentials and seven-day session digests remain in ignored owner-only runtime storage. Sign-ups and additional accounts are unavailable.

### Self Improvement

- **Skill Studio** separates Proposals, Operator-invoked Beta candidates, and Production skills. Gate 1 approves exact scope; Gate 2 approves an exact tested revision; production promotion and completed-proposal closeout remain separate mutations.
- **Self Assessment** collects bounded host, update, runtime, capability, and storage evidence. It can prepare advisory proposals and terminal handoffs but cannot mutate the host.
- **Self Augmentation** creates human-authored architecture proposals, exact allowed-file experiments in isolated worktrees, deterministic candidate dossiers, and external integration handoffs. It cannot invoke Codex, merge, push, or deploy.

### Creative Studios

- **Music Studio** stores immutable project briefs and candidate lineage; supports exact 30-second, 90-second, 3-minute, and 10-minute AMD Vulkan ACE-Step generation; creates FLAC masters and MP3 proxies; follows durable jobs across page navigation; records generation timing, CPU vocal evidence, human review, revision drafts, lawful reference profiles and fusions, rejection, export, and one-generation source-preserving trim copies.
- **Visual Studio** provides bounded local FLUX.2 Vulkan still generation, review, guided image edits, candidate/project deletion, and exact binding to a Music candidate.
- A reviewed still can become a static music companion with framing, matte, fades, and full-song audio muxing. A kept/exported song with a final visual can produce an editable exact local YouTube upload package. Nothing uploads or publishes automatically.

Generated video remains a qualification track. Historical procedural FFmpeg motion effects are retired from advancement; the supported presentation holds the reviewed frame static. Short model-generated motion is not yet a production feature.

The operator-facing flows are documented in [`docs/guides/`](guides/).

## Runtime topology

The stable chat API alias is `soul-local-chat`; actual model identity is reported separately.

- **Daily Core:** Gemma 4 12B Instruct Q4_K_M through Ollama/Vulkan on AMD.
- **AMD-Free Core:** Qwen3 8B Q4_K_M through llama.cpp/CUDA on NVIDIA.
- **Music Core:** Qwen chat on NVIDIA while ACE-Step 1.5 4B LM / 2B Turbo Q8_0 uses AMD/Vulkan only during bounded music generation.

Core changes are click-authorized and lease-revalidated. A reviewed conversational creative action may include its exact required Core transition; model text cannot initiate one and no failover occurs on its own. Music and image models do not remain resident. No idle-unload timer, unattended Core switch, worker queue, or background polling loop is present.

## Deployment

`make dashboard` runs a foreground loopback development instance. The reviewed optional deployment installs explicit user services for the loopback dashboard and Caddy HTTPS on one exact LAN address. Installation is preview-first, requires a changed administrator password and exact confirmation, and leaves firewall, DHCP, router, and client certificate trust to the Operator.

Proxmox, Internet exposure, multi-user accounts, backup, and disaster recovery remain separate future tracks.

## Memory, artifacts, and deletion

Mutable owner memory lives under ignored `Soul/private/memory/`; tracked memory files are neutral public seeds. Durable promotion remains human-reviewed.

Conversations, skill candidates, music projects, visual projects, reference profiles, logs, and generated artifacts have explicit lifecycle boundaries. Reversible archive/Trash behavior is preferred where appropriate. Permanent deletion exists only for previewed exact scopes and preserves separately exported finished files where the relevant workflow says so.

## Human authority boundary

Soul may inspect, explain, draft, research, stage, generate, test, and produce evidence. It may not treat model output, passing tests, successful generation, or a machine-heard result as authorization.

Human approval remains required for risky or destructive execution, durable memory/rule promotion, skill and augmentation gates, production registration, host mutation, provider/privacy exceptions, service installation, merge, release, upload, and publication.

## Current development focus

The foundational Conversational Soul milestone is complete. Deployment/Core orchestration, Self Improvement, Music Studio, Visual Studio stills, and local publication packaging are implemented and under owner use.

Near-term work is expected to concentrate on:

- chat usability, persona fidelity, and dashboard-capability invocation through skills;
- production hardening and documentation of creative workflows;
- additional Music Studio refinement based on real generations;
- measured visual-motion qualification before any production motion path;
- backup/recovery and broader deployment only under separate review.

No release or stable tag has been created.

## Primary references

- [`README.md`](../README.md)
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)
- [`docs/ROADMAP.md`](ROADMAP.md)
- [`docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`](soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md)
- [`docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md`](soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md)
- [`docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md`](soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md)
