# Soul/ Weather International Failure Fix Overlay

This overlay fixes the international weather crash and failed-weather rendering.

## Root cause

`Soul/skills/weather/report.rb` used:

```ruby
US_STATES.value
```

but Ruby Hash uses:

```ruby
US_STATES.values
```

That typo crashed any location with a non-US region/country hint like:

```text
London, UK
Toronto, Canada
```

A typo took down the world. Software remains an international embarrassment.

## Fixes

- Changes `US_STATES.value` to `US_STATES.values`.
- Keeps country alias mapping such as `UK -> GB` and `Canada -> CA`.
- Adds failed-weather rendering so failed reports do not display empty weather fields.
- Failed weather reports no longer offer a detailed follow-up.
- `respond` against a failed workflow now gives a useful failure message.

## Apply

```bash
unzip ~/Downloads/soul_weather_international_failure_fix_overlay.zip
chmod +x Soul/skills/weather/report.rb
```

## Test

```bash
ruby bin/soul skill weather.report -- --location "London, UK" --detailed
ruby bin/soul skill weather.report -- --location "Toronto, Canada" --detailed

ruby bin/soul do "what is the weather like today"
ruby bin/soul respond "somewhere else"
ruby bin/soul respond "London, UK"
ruby bin/soul respond "yes"
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Fix international weather geocoding and failure rendering"
git push origin main
```
