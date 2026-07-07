# Weather Reflection Handler Overlay

This overlay adds a specific `skill.weather.report` reflection handler.

## Why

The weather skill worked, but reflection was still using the generic handler. That produced redundant candidate lessons like:

- weather.report is read-only
- detailed reports close as complete
- deterministic data should be used

Those were already approved and did not capture the new behavior:

- Home/default location confirmation
- Somewhere-else overrides
- international geocoding support
- country aliases such as `UK -> GB`
- clean failed-weather handling
- rain shower codes not being classified as snow

## Live repo check

Before this overlay was generated, the live repo showed:

- `lib/soul_core/reflection.rb` had specific handlers for Downloads, restore, inspect, system status, and ask-mode tasks, but no `skill.weather.report` handler.
- `Soul/skills/weather/report.rb` already emitted the fields this handler needs: `parsed_location_hint`, `geocoding_attempts`, `resolved_location`, `detailed_report`, warnings, and verification fields.
- The live weather skill already had corrected rain/snow event classification.

Because the local branch may be ahead of live, this overlay uses a patch script instead of replacing `reflection.rb`.

## Files

```text
scripts/patch-weather-reflection-handler.rb
scripts/verify-weather-reflection-handler.rb
README_WEATHER_REFLECTION_HANDLER.md
docs/overlays/README_WEATHER_REFLECTION_HANDLER.md
```

## Apply

```bash
unzip ~/Downloads/soul_weather_reflection_handler_overlay.zip
chmod +x scripts/patch-weather-reflection-handler.rb scripts/verify-weather-reflection-handler.rb
ruby scripts/patch-weather-reflection-handler.rb
ruby scripts/verify-weather-reflection-handler.rb
```

## Test

Run a weather workflow that includes an override:

```bash
ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "somewhere else"
ruby bin/soul respond "London, UK"
ruby bin/soul respond "yes"
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```

The candidate should mention international geocoding and override behavior.

Run the Toronto detailed task:

```bash
ruby bin/soul skill weather.report -- --location "Toronto, Canada" --detailed
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```

The candidate should mention rain/snow classification when rain-shower signals are present.

## Reject old generic candidate

If the latest pending reflection is the older generic weather one, reject it first:

```bash
ruby bin/soul reflection reject latest --reason "Redundant generic weather reflection; superseded by specific weather reflection handler."
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Add weather reflection handler"
git push origin main
```
