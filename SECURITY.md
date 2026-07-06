# Security Policy

Soul/ is experimental local assistant software.

## Current security posture

Soul/ can inspect local files and, for approved workflows, move selected files or folders to Trash.

Permanent deletion is not supported.

## Reporting issues

If this repository is public and you find a safety or security issue, open a private channel with the maintainer if available. If not available, open a minimal public issue that avoids exposing sensitive paths, secrets, or exploit details.

## Safety rules

- Do not add skills that execute arbitrary shell commands from LLM output.
- Do not let the LLM directly choose filesystem write operations.
- Do not add permanent delete behavior without a separate explicit design review.
- Do not store secrets in memory files, logs, reflection files, or workflow state.
- Keep logs local unless the user explicitly exports them.
