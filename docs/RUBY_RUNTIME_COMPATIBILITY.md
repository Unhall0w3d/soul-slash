
# Ruby Runtime Compatibility

Soul expects Ruby to be selected per project rather than by replacing the operating system Ruby.

## Command

```bash
ruby bin/soul assess ruby-runtime
ruby bin/soul assess ruby-runtime --json
```

Aliases:

```bash
ruby bin/soul assess runtime-compatibility
ruby bin/soul assess ruby-compatibility
```

## Strategy

Use a project-scoped Ruby runtime, such as rbenv:

```bash
rbenv local 4.0.5
```

This creates:

```text
.ruby-version
```

Do not replace the system Ruby just to run Soul.

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

The assessment treats Ruby 3.4+ as acceptable.

Ruby 4.x is considered compatible when syntax checks and core CLI smoke checks pass.
