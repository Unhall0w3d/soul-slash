
# Phase 29 Pathname Repair

This repair adds the missing Ruby standard-library require for `Pathname`.

## Issue

Phase 29 used `Pathname` in `AlphaImplementationTaskPackGenerator#relative_path`, but the file did not require the `pathname` standard library.

The verifier failed with:

```text
NameError: uninitialized constant SoulCore::AlphaImplementationTaskPackGenerator::Pathname
```

## Fix

Add:

```ruby
require "pathname"
```

to:

```text
lib/soul_core/alpha_implementation_task_pack_generator.rb
```

## Scope

This repair changes only:

```text
lib/soul_core/alpha_implementation_task_pack_generator.rb
docs/maintenance/PHASE29_ALPHA_IMPLEMENTATION_TASK_PACK_PATHNAME_REPAIR.md
```
