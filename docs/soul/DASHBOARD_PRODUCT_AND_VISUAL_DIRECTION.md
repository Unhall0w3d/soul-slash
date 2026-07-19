# Soul Dashboard Product and Visual Direction

## Product shape

The dashboard is Soul's primary daily interface over the same application, conversation, memory, skill, artifact, approval, policy, and execution core used by the CLI. It must not develop a second assistant brain or duplicate authority rules in browser-only code.

Current primary navigation is:

```text
Chat
Self Improvement
  ├─ Skill Studio
  ├─ Self Assessment
  └─ Self Augmentation
Creative Studios
  ├─ Music Studio
  └─ Visual Studio
```

Review Center is a header-level supporting dialog. Core selection, provider/config identity, local connection state, and logout remain visible in the top bar.

## Surface roles

### Chat

Chat is the default operating surface: persistent transmissions, immediate user-message rendering, model/work progress summaries, active conversation, artifacts, workspace, inbox, system state, runtime state, and explicit model/Core controls.

The Soul portrait is functional presence rather than decoration. Masked/dim represents listening or idle state; unmasked/brighter presentation reflects real thinking, responding, or bounded work. It must not imply model throughput or activity that is not actually occurring.

### Self Improvement

Skill Studio, Self Assessment, and Self Augmentation are grouped because all three concern Soul's capabilities and stewardship, but their authority boundaries remain distinct. Their current operator flows are documented in:

- `docs/guides/SKILL_STUDIO.md`
- `docs/guides/SELF_ASSESSMENT.md`
- `docs/guides/SELF_AUGMENTATION.md`

### Creative Studios

Music Studio and Visual Studio are project/candidate workspaces. They preserve exact inputs and lineage, expose resource state, preview consequential operations, and keep machine evidence separate from human artistic judgment.

- `docs/guides/MUSIC_STUDIO.md`
- `docs/guides/VISUAL_STUDIO.md`

### Review Center

Review Center unifies redacted pending-approval and recent execution evidence. Inspection is not authorization. Approval values, private request text, replay, mutation, and destructive history controls remain unavailable there.

## Configuration and deployment posture

The public repository contains no required operator-specific IP address, hostname, credential, model path, or workspace path.

```text
CLI override
→ process environment
→ ignored local .env
→ tracked safe default
```

`make dashboard` is the foreground development path. The reviewed optional persistent deployment keeps Soul loopback-bound behind Caddy HTTPS on one exact LAN endpoint. Service installation, firewall configuration, client CA trust, and wider exposure remain explicit human operations.

## Current visual identity

Soul is a local machine familiar: precise, curious, collaborative, technically deep, and visibly constrained by human authority. The approved character is an androgynous silver-haired machine soul with an articulated dark mask, indigo-black tailored techno-organic materials, fine bronze-gold construction, and restrained cerulean energy.

The interface no longer follows the older purple necromantic grimoire direction. Avoid spellbooks, runes, occult framing, generic robot imagery, and theatrical claims of hidden system activity.

### Palette

```text
Abyssal base       #060B11  page depth and low-luminance canvas
Deep indigo        #101729  layered surfaces and character material
Cerulean presence  #20C8F2  active, available, verified, and focus state
Pale blue-gray     #D9E5EA  primary readable text
Bronze structure   #8E6F3A  frames, separators, and restrained geometry
Operator amber     #D4AF37  review and human authority
Destructive red    #FF1744  destructive action and systemic failure
```

Violet remains atmospheric material depth, not an action color. Large white surfaces are excluded to protect sustained readability on dark displays.

### Form and composition

- Use dark layered surfaces, asymmetric curves, precise borders, concentric instrumentation, and restrained signal geometry.
- Favor strong silhouette and clear hierarchy over high-frequency ornament.
- Keep detailed artwork away from messages, forms, tables, logs, lyrics, and code.
- Use gold for meaningful Operator attention rather than routine decoration.
- Retain conventional labels wherever metaphor would obscure behavior.
- Avoid generic commercial-SaaS cards and flat white panels.

### Typography and legibility

- Display headings use an elegant serif with robust fallbacks.
- Body and controls use a clean readable sans serif.
- IDs, code, evidence, and compact status use a monospace face.
- Secondary utility text must remain at least 11 px at normal zoom.
- Labels use at least 12 px, supporting text generally 13–14 px, and conversation text 15 px or larger.
- Ultrawide layouts keep primary conversation content left-oriented within its working region rather than floating in the screen center.

### Motion

The interface may feel alive through finite transitions tied to real tab, focus, message, Core, or task state. It must not use decorative timers, simulated throughput, continuous background polling, or ambient motion that competes with information.

Reduced-motion preferences disable the optional interaction layer. The pulsing system-status instrument must remain restrained and must not be presented as a measurement unless associated data is current.

## Language

Terms such as Operator, transmission, signal, Core, continuity, foundry, survey, and studio are appropriate when their function remains obvious. Soul's voice may be present, but factual labels—model, accelerator, host, lifecycle, privacy, approval, failure, and destructive scope—must stay truthful and direct.

The public project identity is summarized as:

```text
Conversation · Capability · Creation · Stewardship
```

## Human visual review

Passing automated tests does not approve dashboard design. Material changes to navigation, hierarchy, character identity, palette, typography, motion, authority presentation, or creative workflow require human visual inspection.

Review should consider:

- whether the interface feels coherent and alive without becoming noisy;
- readability at normal zoom and on ultrawide displays;
- visibility of Core, resource, lifecycle, and authority state;
- whether metaphor supports rather than hides function;
- preservation of feature parity and exact human gates;
- consistency between Chat, Self Improvement, and Creative Studios.
