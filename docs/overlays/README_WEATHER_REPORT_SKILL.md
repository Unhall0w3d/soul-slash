# Soul/ Weather Report Skill Overlay

This overlay adds the first weather report workflow.

## What it adds

```text
Soul/skills/weather/report.rb
docs/skills/WEATHER_REPORT.md
docs/overlays/README_WEATHER_REPORT_SKILL.md
```

## What it updates

```text
Soul/skills/registry.yaml
lib/soul_core/app.rb
lib/soul_core/intent_router.rb
lib/soul_core/llm_intent_classifier.rb
lib/soul_core/workflow_runner.rb
lib/soul_core/workflow_session.rb
lib/soul_core/response_renderer.rb
lib/soul_core/confirmation_parser.rb
lib/soul_core/reflection.rb
```

## Behavior

Brief workflow:

```bash
ruby bin/soul do "what is the weather today in Syracuse, NY"
```

Returns:

- condition
- temperature
- humidity
- air quality / US AQI

Then asks:

```text
Would you like the detailed report with a 3-day outlook and notable forecast signals?
```

Detailed follow-up:

```bash
ruby bin/soul respond "yes"
```

Close without detail:

```bash
ruby bin/soul respond "no"
```

Final state is `complete`, not `success`.

## Optional config

Add to `.env` if desired:

```env
SOUL_WEATHER_LOCATION=Syracuse, NY
SOUL_WEATHER_UNITS=fahrenheit
```

## Test

```bash
ruby bin/soul skills
ruby bin/soul intent "what is the weather today in Syracuse, NY"
ruby bin/soul skill weather.report -- --location "Syracuse, NY"
ruby bin/soul do "what is the weather today in Syracuse, NY"
ruby bin/soul respond "yes"
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Add weather report skill and workflow"
git push origin main
```
