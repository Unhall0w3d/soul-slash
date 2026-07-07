# Getting Started

This guide describes the intended public setup path for Soul/.

The current repository is still evolving. Some automation is not implemented yet. This document defines the setup contract that the public Makefile and setup scripts will follow.

## 1. Clone the repository

```bash
git clone https://github.com/Unhall0w3d/soul-slash.git
cd soul-slash
```

## 2. Install requirements

Required:

- Ruby
- Git
- Make
- curl
- unzip
- either llama.cpp server or Ollama

Recommended:

- jq
- zip

## 3. Choose a runtime provider

Soul/ supports two local runtime providers at the API layer:

- llama.cpp server
- Ollama

### Choose llama.cpp if

You want direct GGUF control, Hugging Face GGUF downloads, and explicit runtime flags.

### Choose Ollama if

You want a simpler local model manager and are comfortable using Ollama model names.

## 4. Create local configuration

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env`.

### llama.cpp example

```env
SOUL_RUNTIME_PROVIDER=llamacpp
SOUL_OPENAI_BASE_URL=http://127.0.0.1:8082/v1
SOUL_MODEL_ALIAS=soul-qwen3-8b-q4
SOUL_MODEL_DIR=./models
SOUL_MODEL_FILE=Qwen3-8B-Q4_K_M.gguf
SOUL_MODEL_URL=https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true
```

### Ollama example

```env
SOUL_RUNTIME_PROVIDER=ollama
SOUL_OPENAI_BASE_URL=http://127.0.0.1:11434/v1
SOUL_MODEL_ALIAS=qwen3:8b
SOUL_OLLAMA_MODEL=qwen3:8b
```

## 5. Start your runtime

### llama.cpp

Install or build llama.cpp so `llama-server` is available.

A future setup script will automate this, but the public contract is:

```text
llama-server must expose an OpenAI-compatible endpoint.
```

Tested default endpoint:

```text
http://127.0.0.1:8082/v1
```

### Ollama

Install Ollama, then pull a model:

```bash
ollama pull qwen3:8b
```

Ollama's OpenAI-compatible endpoint is normally:

```text
http://127.0.0.1:11434/v1
```

## 6. Validate Soul/

Run:

```bash
ruby bin/soul doctor
ruby bin/soul skills
ruby bin/soul skill system.status
```

Then test intent routing:

```bash
ruby bin/soul intent "run a file cleanup in Downloads"
ruby bin/soul intent "restore the last downloads cleanup"
```

## 7. Try the cleanup workflow

Create a harmless fixture that does not include protected project terms such as `soul` or `Aletheia`:

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

## 8. Reflection

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

## Current public setup status

This document is step 1.

Next public setup work:

1. Replace the machine-specific Makefile with public runtime setup targets.
2. Add provider detection scripts.
3. Add runtime validation scripts.
4. Update README quick start to call the new Make targets.
