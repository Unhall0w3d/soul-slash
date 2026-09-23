# Soul/ Cloud LLM + Codex Guardrails

The cloud-provider restrictions below govern Soul's advisory provider and
generated-output ingestion paths. Human-authorized Codex work in this workspace
may prepare and edit candidate files using the approved tools and delegation
policy. It remains subject to the task's scope, data-access permissions,
deterministic checks, and human promotion/merge/release gates. This distinction
does not authorize forwarding private repository content, credentials or memory
to another provider, or applying unreviewed provider output as executable work.

Cloud LLMs may be used only for drafting, synthesis, critique, prototype suggestions, and review artifacts.

Cloud LLM outputs must not be applied directly to the repo.

Cloud LLMs must not receive secrets, API keys, credentials, private memory, or private repo content unless explicitly permitted by a human-approved skill brief.

Cloud LLMs must not decide safety classification, approval, persistence, memory promotion, or merge readiness.

Cloud-assisted outputs must remain candidate artifacts for human review.

Soul/ prefers no-key providers for low-trust experiments. For serious cloud-assisted drafting/review, manual API-key providers may be used only when they currently document no-credit-card free API access and the key is created manually by the user.

Soul/ must not scrape, fake, farm, or programmatically create provider accounts or API keys. Programmatic credential acquisition is allowed only through official documented OAuth, device-code, or CLI authentication flows approved in the relevant skill brief.

Soul/ skills are bounded foreground tasks. They must not install, create, enable, or rely on persistent services, daemons, watchers, scheduled tasks, cron jobs, systemd units, launch agents, long-running loops, background polling processes, or always-on monitors unless explicitly approved by the human architect in the skill brief.
