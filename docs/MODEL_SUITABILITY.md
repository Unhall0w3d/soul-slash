
# Model Suitability Registry

The model suitability registry is an advisory policy layer for deciding which model or provider class is appropriate for a task.

It does not enable routing. It does not read secrets. It does not install packages. It does not download models.

## Commands

```bash
ruby bin/soul assess model-suitability
ruby bin/soul assess model-suitability --json
ruby bin/soul assess model-suitability --task coding
ruby bin/soul assess model-suitability --task speech_to_text --json
```

Aliases:

```bash
ruby bin/soul assess models-suitability
ruby bin/soul assess suitability
```

## Task categories

```text
routing
summarization
coding
documentation
research_synthesis
vision
speech_to_text
text_to_speech
long_context
local_privacy_sensitive
```

## Provider classes

```text
local_llm
local_stt
local_tts
approved_cloud_llm
approved_cloud_vision
```

These are provider classes, not configured providers.

## Policy

- Prefer local execution for private, audio, screenshot, credential, and local-file tasks.
- Require explicit approval before sending repo context, screenshots, audio, or private files to a cloud provider.
- Do not use model suitability assessment to enable providers automatically.
- Do not download models automatically.
- Do not store secrets in the suitability registry.
- Treat scores as advisory, not as automatic routing decisions.
- Codex or cloud coding tasks must receive bounded file lists, acceptance criteria, and verifier expectations.

## Recommended next phase

This historical recommendation was completed: later phases added model suitability policy tightening and a Codex-readiness boundary. Current direction is tracked in `docs/CURRENT_STATE.md`.
