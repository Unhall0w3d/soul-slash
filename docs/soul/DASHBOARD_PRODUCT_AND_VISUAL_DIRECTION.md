# Soul Dashboard Product and Visual Direction

## Product shape

The first Soul dashboard is a local, desktop-first interface over the same assistant runtime used by the CLI. It must not implement a second memory model, skill runner, approval system, artifact registry, or safety policy.

The primary navigation now has three tabs in this order:

```text
1. Chat
2. Skill Studio
3. Self Assessment
```

Chat is the daily operating surface. Skill Studio is the controlled skill-creation workflow. Shared workspace, system status, approvals, and activity are supporting views rather than separate assistant brains.

Self Assessment is the evidence-and-review surface for Soul's host environment, language/tool versions, local model runtime, capability matrix, and advisory improvement proposals. It is not an autonomous package manager or privileged administration console. The name distinguishes evidence gathering from the future Self Augmentation concept, which would prepare architecture-level proposals through a separate human-reviewed boundary.

### Chat tab

The initial Chat composition should include:

- persistent chat list and resume controls;
- the active conversation and composer;
- explicit provider, privacy, task, and failure state;
- a compact system-status card with host identity, collection time, and manual refresh;
- a shared-workspace rail or drawer for artifacts attached to the conversation;
- direct links from completion messages to artifacts, approvals, evidence, and review records.

System status is collected once when the dashboard opens and may be refreshed manually. The interface must not add background polling, watchers, or monitoring services.

### Skill Studio tab

The implemented Skill Studio lifecycle is:

```text
idea, capability gap, or bounded brief draft
→ proposal review and exact-revision human Gate 1
→ isolated, unregistered Beta implementation
→ required tests and bounded human-invoked diagnostics
→ exact-tested-revision human Gate 2
→ separate later promotion and merge decisions
```

Skill Studio organizes proposals, Beta candidates, required tests, diagnostics, and production registry summaries. It must not autonomously invoke Codex, apply patches, register generated skills, promote candidates, or treat model output as approval.

Each proposal now shows one deterministic lifecycle stage and the exact skill ID from its Beta manifest. Once that exact ID is present in the production registry, Skill Studio may offer a separately previewed and confirmed closeout that deletes the proposal and superseded Beta copy while preserving the production skill and shared diagnostics.

### Self Assessment tab

The tab loads one lightweight read-only environment snapshot when opened. Package update checks, local model assessment, and capability assessment remain explicit foreground actions. Generating advisory improvement proposal packets requires previewing and confirming the exact assessed revision.

The initial surface must make the mutation boundary visible: it cannot install, update, downgrade, or remove packages; change services; download models; implement or promote skills; or run privileged commands. Those actions require separately reviewed executors with package-manager-specific recovery and confirmation behavior.

### Review Center

Phase 12E adds Review Center as a header-level supporting surface, not a fourth primary tab. It unifies redacted pending-approval state and bounded recent execution activity with manual refresh, filters, and record detail. Inspection is not authorization: approval values, private request text, full scope values, execution replay, approval mutation, and history mutation remain unavailable.

### Shared workspace

The shared workspace is an artifact- and task-oriented projection of Soul's existing registries. It is not an unrestricted filesystem browser.

Initial workspace items may include:

- attached and recently delivered artifacts;
- revisions and provenance;
- implementation task packs;
- skill briefs and human-review artifacts;
- pending approvals and blocked-for-review results;
- deterministic completion and failure summaries.

## Configuration posture

The public repository must contain no operator-specific IP address, hostname, credential, model alias, or workspace path as a required assumption.

Configuration precedence is:

```text
CLI override
→ process environment
→ ignored local .env
→ tracked safe default
```

The dashboard consumes the same typed configuration contract as the CLI. Settings must identify their current source, validation, behavioral effect, privacy or risk impact, and restart requirement. Secrets are redacted and are never returned through general configuration responses.

## Visual source

The first visual attempt must draw from:

- `assets/brand/soul-slash-brand-board.png`
- `assets/brand/soul-slash-repo-header.png`
- `assets/brand/soul-slash-supporting-scene.png`
- `assets/brand/soul-slash-primary-mark.png`
- `assets/brand/soul-slash-repo-icon.png`
- `docs/BRANDING.md`

The visual target is an operational instrument with restrained arcane character: trustworthy, local, precise, and alive with system state without becoming theatrical or visually noisy.

## Initial design tokens

The existing brand board supplies the starting palette:

```text
Arcanum Violet  #6E3DDF  model activity, active focus, creative drafting
Spectral Teal    #00E2D6  verified state, connectivity, successful evidence
Pale Silver      #E6ECF1  primary text and high-contrast marks
Ember Gold       #FFB14A  human gates, approvals, interface emphasis
Shadow Ink       #0A0D12  page background
Necro Slate      #151922  panels, cards, elevated working surfaces
```

Typography begins with:

```text
Display headings: Cinzel or a compatible open serif
Body and controls: Inter or a compatible clean sans serif
Code and identifiers: JetBrains Mono or a compatible monospace
```

The implementation must use distributable fonts or robust system fallbacks. It must not depend on fonts installed only on the project owner's machine.

## Visual restraint

- Use the primary mark, luminous slash, fine circuits, rings, and sigils as sparse identity accents.
- Reserve detailed grimoire scenes for onboarding, empty states, an about view, or a restrained header treatment.
- Do not place high-detail imagery behind message text, tables, forms, logs, or code.
- Prefer thin borders, quiet layered surfaces, small status glows, and precise geometry over ornamental frames around every component.
- Use gold for meaningful human attention, not routine decoration.
- Do not encode lifecycle, risk, or approval state through color alone.
- Maintain readable contrast, visible keyboard focus, reduced-motion behavior, and usable zoom.
- Avoid generic commercial-SaaS gloss and avoid turning every control into fantasy decoration.

## Visual review posture

The owner approved the initial Chat/Skill Studio direction and the third assessment tab. The July 2026 signal-interface refresh moves the visual language toward Soul's machine-familiar identity: dark technical surfaces, teal operational emphasis, restrained violet, scalable code-native fields, and concise persona-aware terms such as Operator, signal, transmission, continuity, and capability. It deliberately avoids making metaphor obscure product meaning. Material changes to dashboard hierarchy, visual language, or authority boundaries still pause for human review.

The interface type scale treats 11 px as the minimum for secondary utility text at normal dashboard zoom. Labels use at least 12 px, supporting copy generally uses 13–14 px, and conversation content uses 15 px or larger. Teal represents active, available, and verified state; amber represents Operator attention and approval; red represents failure and destructive boundaries. Violet is atmospheric only, not an action color.

Soul may feel responsive through short CSS transitions tied to a real tab, hover, focus, or runtime state. The dashboard does not use timers, polling, infinite ambient animation, or decorative motion that competes with information. Reduced-motion preferences disable the optional interaction animation layer.

## Gilded machine-soul research direction

The later design candidate takes inspiration from the design principles behind Warframe's Orokin and Cephalon technology without copying its named interface, glyphs, assets, or exact layouts. Research sources included:

- Digital Extremes' official [Content Creator Art Style Guide](https://www.warframe.com/en/steamworkshop/content-creator-art-style-guide), particularly its emphasis on sweeping silhouettes, over-the-top whole-form composition, faction distinction, and restraint with high-frequency detail;
- Digital Extremes' [TennoCon 2025 Art & Animation Deep Dive](https://www.warframe.com/de/news/tennocon-2025-art-animation-of-warframe-deep-dive), including the described approach to machinery that opens as the player approaches and the blending of organic shapes with mechanical detail;
- the official [Warframe Mission Interface](https://support.warframe.com/hc/en-us/articles/38801911653517-Mission-Interface), used as a reference for peripheral transmissions and semantically consistent status placement;
- the official [Operator Report: The Void](https://www.warframe.com/en/news/operator-report-the-void-ko), used only as thematic context for spatial depth and luminous energy contained by ancient high technology.

Soul's translation uses abyssal indigo-black as the dominant screen material, metallic gold as structural hierarchy, cerulean as active machine presence, muted pale cyan-gray for readable copy, and crimson only for real destructive or failed state. Porcelain white is deliberately excluded from large digital surfaces because sustained high luminance is unsuitable for the owner's dashboard.

Major containers use asymmetric curves, layered border gradients, orbital nodes, and restrained filigree rather than conventional flat cards. The visual system prioritizes overall silhouette over repeated ornament. Finite `core-unseal`, `inscription-resolve`, and `core-awaken` effects respond to real tab, message, or element appearance. They run only when reduced motion is not requested and do not simulate model throughput or introduce timers.

The following remain future concepts until supported by real product behavior: runtime-reactive throughput visualization, parameter dials, a memory graph/arbor, first-instantiation narrative, and collaborative asset editing effects. Evocative names must not replace truthful CPU, GPU, memory, model, lifecycle, or authorization labels.

The review should cover:

- overall visual tone;
- information density;
- navigation and three-tab hierarchy;
- Chat composition;
- workspace placement;
- system-status presentation;
- typography and palette;
- use of imagery and motifs;
- motion and interaction feel;
- desired additions, removals, or product-direction changes.

Passing automated tests does not approve dashboard design. Human visual review remains the acceptance gate for material interface changes.

## Deployment posture

The dashboard is developed and accepted locally before Proxmox is needed. Initial web execution, when separately approved, is foreground and loopback-only. Persistent service installation and LAN deployment belong to a later human-approved deployment brief.
