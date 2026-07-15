# Soul Dashboard Product and Visual Direction

## Product shape

The first Soul dashboard is a local, desktop-first interface over the same assistant runtime used by the CLI. It must not implement a second memory model, skill runner, approval system, artifact registry, or safety policy.

The primary navigation now has three tabs in this order:

```text
1. Chat
2. Skill Studio
3. Self Improvement
```

Chat is the daily operating surface. Skill Studio is the controlled skill-creation workflow. Shared workspace, system status, approvals, and activity are supporting views rather than separate assistant brains.

Self Improvement is the evidence-and-review surface for Soul's host environment, language/tool versions, local model runtime, capability matrix, and advisory improvement proposals. It is not an autonomous package manager or privileged administration console.

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

### Self Improvement tab

The tab loads one lightweight read-only environment snapshot when opened. Package update checks, local model assessment, and capability assessment remain explicit foreground actions. Generating advisory improvement proposal packets requires previewing and confirming the exact assessed revision.

The initial surface must make the mutation boundary visible: it cannot install, update, downgrade, or remove packages; change services; download models; implement or promote skills; or run privileged commands. Those actions require separately reviewed executors with package-manager-specific recovery and confirmation behavior.

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

The owner approved the initial Chat/Skill Studio direction and the later Self Improvement third tab. Material changes to dashboard hierarchy, visual language, or authority boundaries still pause for human review.

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
