# Soul Dashboard Product and Visual Direction

## Product shape

The first Soul dashboard is a local, desktop-first interface over the same assistant runtime used by the CLI. It must not implement a second memory model, skill runner, approval system, artifact registry, or safety policy.

The primary navigation begins with two tabs in this order:

```text
1. Chat
2. Skill Studio
```

Chat is the daily operating surface. Skill Studio is the controlled skill-creation workflow. Shared workspace, system status, approvals, and activity are supporting views rather than separate assistant brains.

### Chat tab

The initial Chat composition should include:

- persistent chat list and resume controls;
- the active conversation and composer;
- explicit provider, privacy, task, and failure state;
- a compact system-status card with host identity, collection time, and manual refresh;
- a shared-workspace rail or drawer for artifacts attached to the conversation;
- direct links from completion messages to artifacts, approvals, evidence, and review records.

System status is manually refreshed in the initial dashboard. The interface must not add background polling, watchers, or monitoring services.

### Skill Studio tab

The initial Skill Studio workflow is:

```text
idea
→ bounded brief draft
→ human edit
→ risk and scope review
→ test and local-eval requirements
→ explicit brief approval
→ implementation task pack
→ candidate review artifact
→ human merge decision
```

Skill Studio may organize, draft, validate, and export reviewed candidate material. It must not autonomously invoke Codex, apply patches, register generated skills, promote candidates, or treat model output as approval.

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

## Initial visual review gate

The first locally runnable dashboard slice must pause for human review before Skill Studio behavior or secondary dashboard features expand.

The review should cover:

- overall visual tone;
- information density;
- navigation and two-tab hierarchy;
- Chat composition;
- workspace placement;
- system-status presentation;
- typography and palette;
- use of imagery and motifs;
- motion and interaction feel;
- desired additions, removals, or product-direction changes.

Passing automated tests does not approve the dashboard design. Human visual review is the acceptance gate for the first aesthetic direction.

## Deployment posture

The dashboard is developed and accepted locally before Proxmox is needed. Initial web execution, when separately approved, is foreground and loopback-only. Persistent service installation and LAN deployment belong to a later human-approved deployment brief.
