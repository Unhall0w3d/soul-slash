# Semantic Memory Live Qualification A4 Brief

Status: Operator-approved implementation scope, 2026-08-23

## Objective

Qualify one optional local embedding profile for ordinary approved-memory
retrieval, correct ranking or query-format defects demonstrated by live
evidence, and preserve deterministic lexical fallback when the runtime is
unavailable.

## Approved scope

- Run one temporary loopback-only Ollama process in the foreground.
- Download and evaluate `qwen3-embedding:0.6b-q8_0` locally.
- Use only the public synthetic corpus for repeatable score claims.
- Expand ambiguous fixtures with unambiguous paraphrases and hard negatives.
- Add a bounded query-only instruction and separate hybrid ranking when live
  component evidence justifies them.
- Update deterministic tests, configuration, documentation, and review evidence.

## Authority limits

- No persistent service, unit, timer, watcher, or background worker.
- No automatic download, startup, Core switch, index rebuild, or promotion.
- No cloud transmission or private-memory content in committed evidence.
- Similarity remains recall evidence, never truth or authorization.
- Merge and persistent runtime adoption remain separate human decisions.

## Acceptance criteria

- Hybrid recall exceeds lexical recall without a precision regression.
- All hard negatives abstain.
- Query instruction reaches only query embeddings; documents stay unprompted.
- Lexical fallback retains its independent ranking profile.
- Existing Observatory and semantic Chat-context verifiers pass.
- The temporary Ollama process is stopped after qualification.
