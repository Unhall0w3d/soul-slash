# Portable Typed Configuration

Phase 12A defines the configuration contract shared by Soul's CLI, conversation runtime, in-process application API, and foreground dashboard.

## Resolution precedence

Every known setting resolves in this order:

```text
invocation-scoped CLI override
→ process environment
→ ignored project-local .env
→ tracked safe default
```

CLI overrides use canonical dotted keys and apply only to the current configuration command. Secret values cannot be passed through CLI arguments. Process environment and `.env` use the documented environment names or compatibility aliases.

Within one source layer, the primary environment name wins over an alias. A higher source layer always wins over a lower layer, so a process alias wins over a primary name in `.env`.

## Local setup

Copy the tracked template and edit the ignored local copy:

```text
cp .env.example .env
chmod 600 .env
```

At minimum, set a model for one local provider:

```text
SOUL_LOCAL_OPENAI_MODEL=your-server-model-id
```

or:

```text
SOUL_OLLAMA_MODEL=your-installed-ollama-model
```

No owner's model alias, IP address, hostname, credential, or filesystem path is required by the public repository.

## Inspection commands

```text
ruby bin/soul config show
ruby bin/soul config show --json
ruby bin/soul config explain conversation.timeout_seconds
ruby bin/soul config validate
ruby bin/soul config validate --json
```

An invocation-only non-secret override is available for inspection and interface testing:

```text
ruby bin/soul config explain dashboard.port --set dashboard.port=9000
```

These commands are read-only. They do not edit `.env`, probe providers, start models, open a listener, or persist an override.

## Typed setting groups

Phase 12A covers:

```text
conversation.*
artifact.*
providers.local_openai.*
providers.ollama.*
providers.cloud_openai.*
dashboard.bind_host
dashboard.port
dashboard.public_origin
```

Each setting exposes:

```text
canonical key
effective redacted value
source and source key
type and accepted values or range
behavioral effect
privacy or risk impact
restart requirement
recommended default
secret classification
```

The schema is implemented in `lib/soul_core/configuration_schema.rb`. Unknown environment variables are not enumerated or returned through configuration inspection.

## Secrets and cloud configuration

Cloud credentials belong only in the process environment or ignored `.env`:

```text
SOUL_CLOUD_OPENAI_BASE_URL=https://provider.example/v1
SOUL_CLOUD_OPENAI_MODEL=provider-model-id
SOUL_CLOUD_OPENAI_API_KEY=secret-value
```

Public configuration responses return only whether the key is configured and the marker `[REDACTED]`. They never return the secret value.

A credential does not authorize cloud use. Cloud conversation remains disabled unless explicitly enabled:

```text
SOUL_ALLOW_CLOUD_CONVERSATION=true
```

Existing privacy, artifact, and approval gates still apply after that opt-in.

## Compatibility names

Current compatibility names remain accepted:

```text
OPENAI_BASE_URL
SOUL_OPENAI_BASE_URL
SOUL_LOCAL_MODEL
SOUL_MODEL_ALIAS
OLLAMA_MODEL
```

Inspection reports the actual source key so operators can migrate toward the primary names without losing compatibility.

## `.env` safety

The typed reader:

- reads only one explicit file below the project root;
- rejects symlinks and non-regular files;
- caps input at 64 KiB and 512 lines;
- requires UTF-8 and valid uppercase environment names;
- rejects duplicate and malformed entries without partially applying values;
- treats shell syntax, interpolation, and command substitution as literal text;
- never mutates the caller's process environment.

Missing `.env` is normal and resolves from process values and safe defaults.

## Dashboard settings

Phase 12A introduced the dashboard settings later consumed by the approved Phase 12C foreground command:

```text
SOUL_DASHBOARD_BIND_HOST=127.0.0.1
SOUL_DASHBOARD_PORT=4567
SOUL_DASHBOARD_PUBLIC_ORIGIN=
```

The bind host accepts loopback only. `dashboard.public_origin` accepts either an empty value or one exact HTTPS origin; it expands Host/Origin and secure-cookie validation for an approved reverse proxy but never widens Soul's listener. Resolving or inspecting these settings does not open a listener; only an explicit dashboard command or separately installed reviewed service starts the server.

## Migration boundary

Configuration inspection, Chat, the application facade, and the dashboard consume the typed resolver. Legacy commands may retain existing environment access during bounded migration, but new interface code must not add another configuration format.
