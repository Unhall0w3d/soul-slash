# Codex Native Subagents

Primary Codex—the active Sol model—uses native Spark, Luna, and Terra subagents as bounded
collaborators. They are separate from Soul's local GPT-OSS Dev Worker. Native
subagents may receive Codex tools appropriate to their assigned role; the local
worker receives only an exact non-secret context packet and returns candidate
text.

The Operator's machine-wide policy lives in `~/.codex/AGENTS.md`, so the same
routing and trust rules apply across repositories. The policy does not grant a
subagent new authority and does not replace a repository's own `AGENTS.md`.

## Routing

| Model | Preferred work |
| --- | --- |
| Primary Sol | Architecture, security, credentials, destructive or privileged operations, remote maintenance, backup/recovery, tightly coupled integration, and final decisions |
| Terra | Bounded medium-complexity implementation, debugging, code review, and integration after architecture and authority are settled |
| Luna | Fast scoped analysis, documentation and test synchronization, fixtures, mechanical refactors, and small reversible fixes |
| Spark Explorer | Read-only repository mapping and exact evidence collection |
| Spark Worker | Small reversible implementations with explicit ownership and acceptance criteria |
| Soul Dev Worker | Tool-less local analysis, critique, or candidate patch from parent-supplied non-secret excerpts |

Primary Sol selects the least costly adequate model after considering risk,
ambiguity, context size, expected implementation depth, current known model
allowances, and handoff/review overhead.

## Assignment contract

A native subagent handoff identifies:

- one bounded objective and deliverable;
- read-only scope or exact file ownership;
- acceptance criteria and commands;
- authority limits and non-goals;
- the shared-worktree rule: preserve edits made by other agents;
- required return evidence: paths, commands, results, uncertainty, and scope
  deviations.

Terra and Luna normally receive a purpose-built handoff rather than the full
conversation. This keeps private and irrelevant context out of the assignment
and makes the result easier to evaluate.

## Evidence-based trust

Trust belongs to the completed assignment, not the model name.

- **Evidence-trusted** mapping with exact paths, line ranges, commands, and
  labeled uncertainty is consumed without repeating the same search. Primary
  Sol rechecks contradictory, drift-sensitive, or risk-critical claims.
- **Change-trusted** low-risk work with clean ownership and passing targeted
  checks is reviewed through shared-worktree status, a risk-proportionate diff,
  and returned evidence. Every check mandated by the repository or approved
  brief must still be run and evidenced by the assigned agent. Primary Sol does
  not reimplement the change or automatically rerun every successful check; one
  additional integration check is enough unless independent primary execution
  is explicitly required.
- **Independently verified** work covers security, credentials, destructive or
  privileged behavior, persistence, remote maintenance, backup/recovery,
  releases, confirmation gates, destructive protections, safety and path
  checks, memory policy, human review requirements, and tightly coupled
  architecture. These remain primary-owned and require independent validation
  even when a subagent contributes evidence.

Unexpected files, overlapping edits, missing evidence, failed checks,
uncertainty, or newly discovered risk revoke task-level trust and return the
work to primary Sol. A narrower retry is used only when it has a clear
expected benefit.

This structure reduces duplicated token use while retaining meaningful review:
primary Sol evaluates the evidence and integration boundary instead of
repeating successful delegated work from scratch.
