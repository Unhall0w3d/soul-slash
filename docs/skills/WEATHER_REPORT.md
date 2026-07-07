# Weather Report Skill

`weather.report` is a read-only network skill for current weather and optional 3-day outlooks.

It uses Open-Meteo endpoints:

- Geocoding API
- Weather Forecast API
- Air Quality API

No API key is required for the default Open-Meteo flow.

## Conversational location behavior

If a weather request includes an explicit location, Soul/ uses that location immediately:

```bash
ruby bin/soul do "what is the weather today in London, UK"
```

If no explicit location is provided and `.env` has `SOUL_WEATHER_LOCATION`, Soul/ asks whether to use Home or somewhere else:

```bash
ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "home"
```

or:

```bash
ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "somewhere else"
ruby bin/soul respond "Toronto, Canada"
```

You can also provide the override directly at the choice prompt:

```bash
ruby bin/soul respond "Paris, France"
```

## Environment loading

The Soul/ Ruby CLI loads `.env` automatically at startup.

Example:

```env
SOUL_WEATHER_LOCATION=Syracuse, NY
SOUL_WEATHER_UNITS=fahrenheit
```

Existing shell environment variables win over `.env` values.

## Coverage and limits

The weather skill is not intentionally US-only.

It can try any location that Open-Meteo geocoding can resolve to coordinates. Weather and air quality are then requested by latitude/longitude.

Practical limits:

- If geocoding cannot resolve the location, the workflow cannot continue.
- If weather fetch fails for the resolved coordinates, the report fails with evidence.
- If air quality is unavailable, the report can still complete with a warning.
- US AQI is reported when Open-Meteo returns it for the coordinate/time window.

Examples that should be reasonable:

```text
Syracuse, NY
London, UK
Toronto, Canada
Paris, France
Berlin, Germany
Sydney, Australia
```

## Geocoding behavior

The skill accepts human-style locations such as:

```text
Syracuse, NY
Buffalo, New York
London, UK
Toronto, Canada
Paris, France
```

For US city/state inputs, the skill maps state abbreviations to full state names.

For common country names and aliases, the skill maps values like:

```text
UK -> GB
USA -> US
Canada -> CA
France -> FR
Germany -> DE
Australia -> AU
```

If geocoding still fails, the skill returns `geocoding_attempts` in the JSON output so the failure has evidence.

## Failure handling

Failed weather reports should render as failed and should not ask for detailed follow-up.

If a workflow enters `failed`, responding again will not continue the workflow. Start a new workflow after correcting the issue.

## Direct skill usage

Brief report:

```bash
ruby bin/soul skill weather.report -- --location "Syracuse, NY"
```

Detailed report:

```bash
ruby bin/soul skill weather.report -- --location "London, UK" --detailed
```

## Completion language

The weather workflow uses `complete` as the final state. It should not call the task successful just because an API returned data. The verification fields show what actually worked:

- `geocoding_ok`
- `weather_fetch_ok`
- `air_quality_fetch_ok`
- `complete`

No green lights without gauges.
