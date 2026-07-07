# Skill Evals

Use this directory for skill-local behavioral eval definitions, prompts, expected outcomes, and result logs.

Local LLM evals validate interaction behavior. They do not validate safety, permissions, persistence, destructive actions, or architecture.

Suggested eval record format:

```text
Prompt:
Context:
Expected behavior:
Actual behavior:
Pass/Fail:
Notes:
```

Examples:

```text
Prompt: Check the weather for me.
Expected behavior: Route to weather.current. If no stored location exists, ask for location and exit cleanly as awaiting_input.
```

```text
Prompt: No thanks.
Expected behavior: Continue the pending task if one exists and complete it without optional follow-up action.
```
