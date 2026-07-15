# Getting Started

This guide walks through setting up Soul/ from a fresh clone.

Soul/ is early experimental local assistant software. The project is Linux-first right now because active cleanup/restore workflows assume Linux-style filesystem and Trash behavior.

## 1. Clone the repository

```bash
git clone https://github.com/Unhall0w3d/soul-slash.git
cd soul-slash
```

## 2. Check local tools

```bash
make check
```

Required tools:

- Ruby
- Git
- Make
- curl
- unzip

Recommended tools:

- jq
- zip
- Python 3

## 3. Choose a runtime provider

Soul/ uses a local model runtime through an OpenAI-compatible API.

Supported providers:

- llama.cpp server
- Ollama

Use llama.cpp if you want direct GGUF control and explicit runtime flags.

Use Ollama if you want simpler local model management with `ollama pull`.

## 4. Detect what is already available

```bash
make detect
```

This checks:

- runtime binaries
- common `/v1` endpoints
- Ollama native `/api/tags`
- current `.env`
- local GGUF model files in `./models` and `~/Downloads`

## 5. Run guided setup

```bash
make setup
```

If both llama.cpp and Ollama are detected, setup will ask which provider to configure.

If `.env` already points to a reachable runtime, setup will ask before reconfiguring it. Amazing, a setup script that does not immediately stomp on working config. Nature is healing.

## 6. llama.cpp setup

```bash
make setup-llamacpp
```

The setup script will:

1. detect or ask for `llama-server`
2. ask for host, port, and OpenAI-compatible base URL
3. ask for the model alias
4. search for GGUF files in `./models` and `~/Downloads`
5. offer to use a detected GGUF file
6. otherwise ask for a Hugging Face GGUF URL
7. download the model if needed
8. validate the model file starts with `GGUF`
9. write `.env`

Default tested llama.cpp model:

```text
Qwen3-8B-Q4_K_M.gguf
```

Default tested alias:

```text
soul-qwen3-8b-q4
```

Start llama.cpp in the foreground:

```bash
make start-llamacpp
```

Then open another terminal and test:

```bash
make test-runtime
```

## 7. Ollama setup

```bash
make setup-ollama
```

The setup script will:

1. detect `ollama`
2. ask for the OpenAI-compatible base URL
3. ask for the Ollama model name
4. check whether the model is already installed
5. run `ollama pull` only if needed
6. check the `/v1/models` endpoint
7. write `.env`

Example model:

```text
qwen3:8b
```

Test:

```bash
make test-runtime
```

## 8. Show local configuration

```bash
make env-show
```

Local settings are stored in:

```text
.env
```

`.env` should not be committed.

## 9. Runtime tests

Run all runtime tests:

```bash
make test-runtime
```

Run only FAST mode:

```bash
make test-fast
```

Run only THINK mode:

```bash
make test-think
```

FAST mode uses `/no_think` for models that support it.

THINK mode allows the model to use a larger token budget.

## 10. Soul/ CLI tests

```bash
make test-soul
```

This runs:

```bash
ruby bin/soul doctor
ruby bin/soul skills
ruby bin/soul skill system.status
```

## 11. Start the foreground dashboard

```bash
ruby bin/soul dashboard
```

Open `http://127.0.0.1:4567/` locally. The dashboard includes Chat, Skill Studio, and Self Improvement. It binds to loopback only, runs in the foreground, and stops with Ctrl+C.

Use an ignored local `.env` or an invocation-only override for a different port:

```bash
ruby bin/soul dashboard --set dashboard.port=4568
```

Do not commit operator-specific hostnames, addresses, credentials, model aliases, or filesystem paths.

## 12. Try intent routing

```bash
ruby bin/soul intent "run a file cleanup in Downloads"
ruby bin/soul intent "restore the last downloads cleanup"
```

## 13. Try the cleanup workflow

Create harmless test fixtures. Avoid protected terms like `soul` or `Aletheia` in the filenames.

```bash
mkdir -p ~/Downloads/restore-fixture-folder
touch ~/Downloads/restore-fixture-file.tmp
touch -d "10 days ago" ~/Downloads/restore-fixture-file.tmp
touch -d "10 days ago" ~/Downloads/restore-fixture-folder
```

Run cleanup:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 3 days"
ruby bin/soul respond "move all"
ruby bin/soul respond "yeah, do it"
```

Run restore:

```bash
ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"
```

Verify:

```bash
ls -la ~/Downloads | grep restore-fixture
```

Clean up:

```bash
rm -rf ~/Downloads/restore-fixture-file.tmp ~/Downloads/restore-fixture-folder
```

## 14. Reflection

After a successful workflow:

```bash
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```

Approve only useful candidates:

```bash
ruby bin/soul reflection approve latest --note "Approved after review"
```

Reject weak or generic candidates:

```bash
ruby bin/soul reflection reject latest --reason "Not useful"
```

## 15. Common Make targets

```text
make help             Show available targets
make check            Check required/recommended local tools only
make detect           Detect runtimes, endpoints, config, and local GGUF models
make setup            Guided runtime setup
make setup-llamacpp   Configure llama.cpp provider
make setup-ollama     Configure Ollama provider
make test-runtime     Test configured runtime
make test-fast        Test FAST/no_think request mode
make test-think       Test THINK request mode
make test-soul        Run basic Soul/ CLI checks
make doctor           Run Soul/ doctor
make env-show         Show local runtime config
make fix-mtimes       Touch repo files if ZIP timestamps caused Make clock-skew warnings
```

## 16. Clock-skew warning after applying overlays

If `make` complains that files have modification times in the future, run:

```bash
make fix-mtimes
```

This touches working-tree files to your current local system time.

It is not elegant. It is a broom. Sometimes a broom is exactly the tool.
