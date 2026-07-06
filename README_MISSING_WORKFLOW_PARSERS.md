# Soul/ Missing Workflow Parsers Overlay

This overlay repairs the current public repo state by adding the workflow parser files required by:

```ruby
lib/soul_core/workflow_session.rb
```

The repo currently contains:

```ruby
require_relative "selection_parser"
require_relative "confirmation_parser"
```

but does not include:

```text
lib/soul_core/selection_parser.rb
lib/soul_core/confirmation_parser.rb
```

## Install

```bash
cd ~/Projects/soul
git checkout -b fix/missing-workflow-parsers
unzip ~/Downloads/soul_missing_workflow_parsers_overlay.zip
```

## Verify

```bash
ruby -c lib/soul_core/selection_parser.rb
ruby -c lib/soul_core/confirmation_parser.rb
ruby -c lib/soul_core/workflow_session.rb
ruby -c bin/soul
find lib Soul/skills -name "*.rb" -print0 | xargs -0 -n1 ruby -c
```

## Smoke test

```bash
ruby bin/soul intent "run a file cleanup in Downloads"
ruby bin/soul intent "restore the last downloads cleanup"
ruby bin/soul skills
```

Then retry the cleanup/restore flow.
