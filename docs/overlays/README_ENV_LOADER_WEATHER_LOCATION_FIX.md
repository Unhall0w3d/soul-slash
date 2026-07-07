# Soul/ Env Loader + Weather Location Fix Overlay

This overlay fixes weather default-location handling.

## Problem

`.env` contained:

```env
SOUL_WEATHER_LOCATION=Syracuse, NY
SOUL_WEATHER_UNITS=fahrenheit
```

but plain Ruby commands such as:

```bash
ruby bin/soul do "what is the weather like today"
```

did not load `.env`.

So `IntentRouter` could not see `SOUL_WEATHER_LOCATION` and created a `needs_location` workflow.

Then:

```bash
ruby bin/soul respond "no"
```

hit an unsupported `needs_location` workflow status.

A tidy little two-bug parade. Charming.

## Fix

Adds:

```text
lib/soul_core/env_loader.rb
```

Updates:

```text
lib/soul_core/app.rb
lib/soul_core/workflow_session.rb
docs/skills/WEATHER_REPORT.md
```

The Ruby CLI now loads `.env` automatically at startup.

`needs_location` weather workflows can now be cancelled cleanly or answered with a location:

```bash
ruby bin/soul respond "Syracuse, NY"
```

## Apply

```bash
unzip ~/Downloads/soul_env_loader_weather_location_fix_overlay.zip
```

## Test

With `.env` containing:

```env
SOUL_WEATHER_LOCATION=Syracuse, NY
SOUL_WEATHER_UNITS=fahrenheit
```

Run:

```bash
ruby bin/soul doctor
ruby bin/soul intent "what is the weather like today"
ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "no"
```

Expected:

- `doctor` shows weather_location as Syracuse, NY
- intent includes location from `.env`
- workflow runs the brief weather report
- `respond "no"` closes as complete

Also test no-location cancellation by temporarily moving `.env` aside or removing the weather location:

```bash
ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "no"
```

Expected:

```text
Weather workflow cancelled. No location was provided, so no weather report was run.
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Load env defaults and handle weather location responses"
git push origin main
```
