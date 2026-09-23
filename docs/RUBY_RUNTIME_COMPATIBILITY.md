
# Ruby Runtime Compatibility

Soul expects Ruby to be selected per project rather than by replacing the operating system Ruby.

## Command

```bash
rbenv exec ruby bin/soul assess ruby-runtime
rbenv exec ruby bin/soul assess ruby-runtime --json
```

Aliases:

```bash
rbenv exec ruby bin/soul assess runtime-compatibility
rbenv exec ruby bin/soul assess ruby-compatibility
```

## Strategy

Use a project-scoped Ruby runtime, such as rbenv:

```bash
rbenv local 4.0.7
```

This creates:

```text
.ruby-version
```

Do not replace the system Ruby just to run Soul. `uv` manages Soul's Python environments, not Ruby. The Makefile selects the installed rbenv version when present; direct CLI calls should use `rbenv exec ruby bin/soul ...` or an activated rbenv shell. The project assessment requires the pinned version and the Prism parser. User services should launch the exact private Ruby path from the approved installation; privileged host-maintenance helpers remain on the OS interpreter until their authority boundary is separately reviewed.

## What the assessment checks

```text
active Ruby interpreter
Ruby executable path
RubyGems version
Bundler version if available
rbenv-selected Ruby
.ruby-version value
syntax of tracked Ruby files
core Soul CLI smoke checks
```

## What the assessment does not do

```text
install gems
run bundle install
mutate system Ruby
modify project files
use the network
promote generated files
```

## Compatibility rule

The assessment requires the active interpreter to match `.ruby-version` and report the Prism parser. It runs syntax and core CLI smoke checks with that same interpreter. Ruby 4.0.7 is the current Soul pin; update the pin deliberately after qualifying a newer stable Ruby.
