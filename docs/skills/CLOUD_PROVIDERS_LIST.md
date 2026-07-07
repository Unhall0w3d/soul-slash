# cloud.providers.list

`cloud.providers.list` reports configured cloud LLM providers without making network calls.

It is read-only.

It does not test providers.

It does not ask for API keys.

It does not print API key values.

Marvelous. A cloud feature that refuses to touch the cloud. Humanity briefly learns restraint.

## Direct usage

```bash
ruby Soul/skills/cloud/providers/list.rb
```

Optional explicit config:

```bash
ruby Soul/skills/cloud/providers/list.rb --config Soul/config/cloud_providers.yaml
```

## Output

The skill returns JSON with:

```text
provider name
enabled
auth_mode
api_key_env
api_key_present
base_url
default_model
requires_credit_card
credit_card_policy
programmatic_key_acquisition
trust_level
roles
notes
status
```

## Provider statuses

```text
disabled
ready_for_no_key_smoke_test
blocked_missing_manual_api_key
ready_for_manual_key_smoke_test
configured
```

## Secret handling

The skill may report:

```text
api_key_present: true
```

or:

```text
api_key_present: false
```

It must never print the key value.

## Mistral

At this stage, Mistral should normally appear as:

```text
enabled: false
auth_mode: manual_api_key
api_key_env: MISTRAL_API_KEY
api_key_present: false
```

That is expected.

Mistral setup documentation belongs in the future `cloud.providers.test` overlay, not here.

## Verification

```bash
ruby scripts/verify-cloud-providers-list.rb
```
