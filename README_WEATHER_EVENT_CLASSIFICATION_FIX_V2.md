# Weather Event Classification Fix v2

This replaces the first patch script, which accidentally interpolated `#{day}` inside the patcher itself. Yes, the patch script briefly believed it was the weather skill. Software comedy, unpaid.

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

Correct grouping:

```text
71..77  snow / snow grains
80..82  rain showers
85..86  snow showers
```

## Apply

```bash
unzip ~/Downloads/soul_weather_event_classification_fix_v2_overlay.zip
chmod +x scripts/fix-weather-event-classification.rb
ruby scripts/fix-weather-event-classification.rb
```

## Test

```bash
ruby bin/soul skill weather.report -- --location "Toronto, Canada" --detailed
```

Expected:

- `Slight rain showers` should not produce a snow-related notable signal.
- If the precipitation threshold is notable, rain/precipitation wording may still appear.

## Suggested commit

```bash
git status --short
git add .
git commit -m "Fix weather event classification"
git push origin main
```
