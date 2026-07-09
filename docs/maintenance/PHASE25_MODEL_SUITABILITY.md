
# Phase 25 Model Suitability Registry

Phase 25 adds an advisory model suitability registry.

## Purpose

Soul needs a way to reason about which model or provider class is appropriate for a task before using local or cloud models for coding, documentation, STT, vision, research synthesis, or long-context work.

## Scope

Phase 25 is advisory only.

It does not:

```text
download models
install packages
enable providers
read secrets
change runtime configuration
route tasks automatically
record audio
capture screenshots
promote alpha artifacts
```

## Commands

```bash
ruby bin/soul assess model-suitability
ruby bin/soul assess model-suitability --json
ruby bin/soul assess model-suitability --task coding
ruby bin/soul assess model-suitability --task speech_to_text --json
```

## Recommendation

Use this registry as the foundation for:

```text
Phase 26: model suitability policy tightening
Phase 27: Codex handoff contract
Phase 28: Codex dry-run review loop
```
