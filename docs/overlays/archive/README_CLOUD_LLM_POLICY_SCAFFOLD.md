# Soul/ Cloud LLM Policy Scaffold Overlay

This is the first cloud-assist overlay.

It adds policy/configuration scaffolding only.

It does **not** implement provider clients.

It does **not** add Mistral setup instructions yet.

It does **not** make outbound network calls.

Tiny mercy. We can invite cloud models into the architecture without immediately handing them a wrench.

## Adds

```text
docs/soul/SOUL_DESIGN_ETHOS.md
docs/soul/CLOUD_LLM_POLICY.md
docs/soul/CLOUD_PROVIDER_CONFIG.md
docs/soul/RESEARCH_SYNTHESIS_POLICY.md
docs/soul/CLOUD_ASSIST_SKILL_TEMPLATE.md
docs/soul/HUMAN_REVIEW_GATE.md
docs/soul/AGENTS_CLOUD_LLM_APPEND.md
Soul/config/cloud_providers.example.yaml
README_CLOUD_LLM_POLICY_SCAFFOLD.md
docs/overlays/README_CLOUD_LLM_POLICY_SCAFFOLD.md
```

## AGENTS.md

This overlay does not overwrite `AGENTS.md`.

Review:

```bash
cat docs/soul/AGENTS_CLOUD_LLM_APPEND.md
```

Then append it manually if appropriate:

```bash
cat docs/soul/AGENTS_CLOUD_LLM_APPEND.md >> AGENTS.md
```

Manual append is intentional. `AGENTS.md` is too important to clobber with a zip file like a raccoon in a filing cabinet.

## Mistral

Mistral is included as the primary serious manual-key provider candidate because current official docs state Free mode API access is enabled by default with no credit card required.

Mistral account/API-key setup documentation is intentionally deferred until the provider test overlay.

At that time, documentation should cover:

```text
account creation
API key generation
.env setup
cloud.providers.test smoke test
no-secret logging verification
```

## Apply

```bash
unzip ~/Downloads/soul_cloud_llm_policy_scaffold_overlay.zip
```

## Review

```bash
git diff -- docs/soul Soul/config/cloud_providers.example.yaml
cat docs/soul/AGENTS_CLOUD_LLM_APPEND.md
```

Optional AGENTS append:

```bash
cat docs/soul/AGENTS_CLOUD_LLM_APPEND.md >> AGENTS.md
```

## Commit

```bash
git status --short
git add docs/soul Soul/config/cloud_providers.example.yaml README_CLOUD_LLM_POLICY_SCAFFOLD.md docs/overlays/README_CLOUD_LLM_POLICY_SCAFFOLD.md
git add AGENTS.md # only if you appended the guardrail block
git commit -m "Add cloud LLM policy scaffold"
git push origin main
```
