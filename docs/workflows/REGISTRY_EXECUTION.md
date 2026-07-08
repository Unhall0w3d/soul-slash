# Workflow Registry Execution

## Purpose

This phase puts the workflow registry into the workflow execution path.

Before a workflow runs, `WorkflowRunner#run` checks the registry and blocks unregistered workflow intents.

## Behavior

Registered workflow:

```text
intent -> registry check -> existing workflow runner path
```

Unregistered workflow:

```text
intent -> registry check -> blocked_unregistered_workflow
```

The result includes:

```text
state.status = blocked_unregistered_workflow
verification.registry_checked = true
verification.registered_workflow = false
```

## What this phase does not do

This phase does not yet remove existing workflow implementation methods or the YouTube workflow patch.

The registry now guards execution, but individual workflow handlers still live in their current places.

That means `youtube.play` still runs through the existing YouTube workflow path, but only after the registry confirms it is a registered workflow.

## Commands

Verify:

```bash
ruby scripts/verify-workflow-registry-execution.rb
```

Manual check:

```bash
ruby bin/soul workflows --json
ruby bin/soul do "play Folsom Prison Blues on YouTube"
ruby bin/soul respond "cancel"
```

## Next phase

The next phase should move workflow handlers behind explicit registered handler objects.

Target shape:

```text
WorkflowRegistry
  -> WorkflowDefinition
  -> handler class
  -> run/respond/render
```

That is when `youtube.play` can stop relying on monkey-patch routing.
