# Weather Event Classification Fix

This overlay fixes a weather event classification bug.

## Problem

Toronto returned:

```text
condition: Slight rain showers
```

but the notable forecast signal said:

```text
snow or snow showers possible
```

That was caused by classifying Open-Meteo weather codes `71..86` as snow.

Open-Meteo weather-code groups used by Soul/ are:

```text
71..77  snow/snow grains
80..82  rain showers
85..86  snow showers
```

So `80..82` should not be treated as snow.

## Apply

```bash
unzip ~/Downloads/soul_weather_event_classification_fix_overlay.zip
ruby scripts/fix-weather-event-classification.rb
```

## Test

```bash
ruby bin/soul skill weather.report -- --location "Toronto, Canada" --detailed
```

Expected:

- `Slight rain showers` should not produce a snow-related notable signal.
- Rain shower or precipitation wording may still appear if precipitation thresholds are notable.

## Suggested commit

```bash
git status --short
git add .
git commit -m "Fix weather event classification"
git push origin main
```
