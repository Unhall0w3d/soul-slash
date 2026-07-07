# Soul/ Weather Geocoding Fix Overlay

This overlay fixes `weather.report` geocoding for human-style city/state inputs like:

```text
Syracuse, NY
Buffalo, New York
Rochester, NY
```

## Problem

The first weather skill passed the raw location string directly to Open-Meteo geocoding.

For inputs like:

```text
Syracuse, NY
```

that could return no result because the provider geocoder does not reliably treat `City, ST` as the best search term.

Tiny comma, big failure. Software remains a majestic clown parade.

## Fix

The skill now:

- parses city/state hints
- maps US state abbreviations to full state names
- retries normalized geocoding variants
- uses `countryCode=US` when a US state hint is detected
- scores candidates by city, admin/state, country, and population
- returns `geocoding_attempts` in failures and successful reports

## Apply

```bash
unzip ~/Downloads/soul_weather_geocoding_fix_overlay.zip
chmod +x Soul/skills/weather/report.rb
```

## Test

```bash
ruby bin/soul skill weather.report -- --location "Syracuse, NY"
ruby bin/soul skill weather.report -- --location "Syracuse, NY" --detailed
ruby bin/soul do "what is the weather today in Syracuse, NY"
ruby bin/soul respond "yes"
```

Only after the direct skill works should you add a default location to `.env`:

```env
SOUL_WEATHER_LOCATION=Syracuse, NY
SOUL_WEATHER_UNITS=fahrenheit
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Fix weather geocoding for city state inputs"
git push origin main
```
