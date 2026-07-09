
# Phase 36 Ruby Runtime Compatibility

Phase 36 adds a read-only Ruby runtime compatibility assessment.

## Purpose

The project is beginning to validate against Ruby 4.x while avoiding changes to the operating system Ruby.

The correct model is:

```text
system Ruby stays managed by the OS
project Ruby is selected through rbenv or equivalent
Soul validates against the active project Ruby
```

## New commands

```bash
ruby bin/soul assess ruby-runtime
ruby bin/soul assess ruby-runtime --json
```

Aliases:

```bash
ruby bin/soul assess runtime-compatibility
ruby bin/soul assess ruby-compatibility
```

## Checks

```text
Ruby version and executable
RubyGems version
Bundler version when available
rbenv selected Ruby when available
.ruby-version value
syntax of tracked Ruby files
core CLI smoke checks
```

## Scope

Phase 36 does not:

```text
install Ruby
install gems
run bundle install
modify system Ruby
modify runtime settings
invoke network operations
change application behavior
```

## Result

Soul now has a repeatable compatibility gate before building additional skills on top of a changed Ruby runtime.
