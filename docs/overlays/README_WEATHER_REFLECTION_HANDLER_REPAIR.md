# Weather Reflection Handler Repair Overlay

This overlay repairs a partial weather reflection handler install.

## Problem

The first patch could leave `reflection.rb` in a partial state:

```text
weather dispatch: ok
weather handler: ok
workflow context helper: missing
rain shower code rule: missing
snow code rule: missing
```

That means the dispatch and method name existed, but the complete handler body did not. Extremely helpful, in the same way an umbrella frame without fabric is technically an umbrella if you enjoy being lied to.

## Fix

This repair script:

- makes a timestamped backup of `lib/soul_core/reflection.rb`
- ensures `skill.weather.report` dispatch exists
- removes any existing partial `reflect_weather_report`
- removes any existing partial `weather_workflow_context_for`
- inserts the full weather reflection handler
- runs `ruby -c`
- provides a stronger verifier

## Apply

```bash
unzip ~/Downloads/soul_weather_reflection_handler_repair_overlay.zip
chmod +x scripts/repair-weather-reflection-handler.rb scripts/verify-weather-reflection-handler.rb
ruby scripts/repair-weather-reflection-handler.rb
ruby scripts/verify-weather-reflection-handler.rb
```

## Test

Reject stale generic candidate first if still pending:

```bash
ruby bin/soul reflection reject latest --reason "Redundant generic weather reflection; superseded by repaired specific weather reflection handler."
```

Then generate a new one from an international weather task:

```bash
ruby bin/soul skill weather.report -- --location "Toronto, Canada" --detailed
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```

Expected candidate should mention:

- international location support
- geocoding evidence
- rain showers distinguished from snow showers
- Open-Meteo rain-shower codes 80..82 not being classified as snow

For Home/override workflow context:

```bash
ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "somewhere else"
ruby bin/soul respond "London, UK"
ruby bin/soul respond "yes"
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```

Expected candidate should mention:

- user-provided override
- international geocoding
- UK -> GB alias behavior

## Suggested commit

```bash
git status --short
git add .
git commit -m "Repair weather reflection handler"
git push origin main
```
