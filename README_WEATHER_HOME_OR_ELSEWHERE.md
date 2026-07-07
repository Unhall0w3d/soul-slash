# Soul/ Weather Home or Elsewhere Overlay

This overlay updates weather conversation behavior.

## Behavior

Explicit location:

```bash
ruby bin/soul do "what is the weather today in London, UK"
```

runs immediately.

No explicit location, but `.env` has Home:

```bash
ruby bin/soul do "what is the weather like today"
```

now asks:

```text
Do you want the weather for Home or somewhere else?
```

Then:

```bash
ruby bin/soul respond "home"
```

uses `SOUL_WEATHER_LOCATION`.

Or:

```bash
ruby bin/soul respond "somewhere else"
ruby bin/soul respond "Toronto, Canada"
```

uses the override.

You can also answer the first prompt directly:

```bash
ruby bin/soul respond "Paris, France"
```

## Coverage

The skill is not intentionally US-only. It uses Open-Meteo geocoding and coordinate-based weather/air-quality APIs.

Practical limits:

- location must resolve through geocoding
- weather must be available for the resolved coordinate
- air quality may be unavailable; this becomes a warning, not fabricated data

## Updates

```text
Soul/skills/weather/report.rb
lib/soul_core/intent_router.rb
lib/soul_core/workflow_runner.rb
lib/soul_core/workflow_session.rb
lib/soul_core/response_renderer.rb
docs/skills/WEATHER_REPORT.md
```

## Test

```bash
ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "home"
ruby bin/soul respond "no"

ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "somewhere else"
ruby bin/soul respond "London, UK"
ruby bin/soul respond "yes"

ruby bin/soul skill weather.report -- --location "London, UK" --detailed
ruby bin/soul skill weather.report -- --location "Toronto, Canada" --detailed
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Add Home or elsewhere weather location flow"
git push origin main
```
