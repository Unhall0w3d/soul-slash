# Weather Report Skill

`weather.report` is a read-only network skill for current weather and optional 3-day outlooks.

It uses Open-Meteo endpoints:

- Geocoding API
- Weather Forecast API
- Air Quality API

No API key is required for the default Open-Meteo flow.

## Geocoding behavior

The skill accepts human-style locations such as:

```text
Syracuse, NY
Buffalo, New York
Rochester, NY
Albany, NY
```

For US city/state inputs, the skill normalizes the query, maps state abbreviations to full state names, retries city-only lookup, and filters with `countryCode=US` when appropriate.

This is necessary because provider geocoding APIs do not always treat `"City, ST"` as a useful raw search string. Naturally, computers remain deeply offended by commas.

If geocoding still fails, the skill returns `geocoding_attempts` in the JSON output so the failure has evidence.

## Direct skill usage

Brief report:

```bash
ruby bin/soul skill weather.report -- --location "Syracuse, NY"
```

Detailed report:

```bash
ruby bin/soul skill weather.report -- --location "Syracuse, NY" --detailed
```

## Workflow usage

Start the workflow:

```bash
ruby bin/soul do "what is the weather today in Syracuse, NY"
```

Soul/ will return:

- condition
- temperature
- humidity
- US AQI air quality

Then it asks whether you want the detailed report.

Detailed report:

```bash
ruby bin/soul respond "yes"
```

Close without detail:

```bash
ruby bin/soul respond "no"
```

## Default location

After confirming the direct skill works for your location, you can set a default location in `.env`:

```env
SOUL_WEATHER_LOCATION=Syracuse, NY
SOUL_WEATHER_UNITS=fahrenheit
```

Then this works without naming the city every time:

```bash
ruby bin/soul do "what is the weather like today"
```

## Completion language

The weather workflow uses `complete` as the final state. It should not call the task successful just because an API returned data. The verification fields show what actually worked:

- `geocoding_ok`
- `weather_fetch_ok`
- `air_quality_fetch_ok`
- `complete`

No green lights without gauges.
