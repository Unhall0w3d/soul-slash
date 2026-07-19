# Requirements

Soul/ is early experimental local assistant software.

The project is currently Linux-first because the active filesystem workflows use Linux-style Trash behavior. The CLI and provider model are intended to become more portable over time, but the safest current assumption is Linux.

## Required

- Ruby
- Git
- Make
- curl
- unzip
- A local OpenAI-compatible model runtime

Supported runtime providers:

- llama.cpp server
- Ollama

## Recommended

- jq
- zip
- Python 3, useful for helper scripts and local packaging workflows
- A GPU-supported local model runtime where available

## Optional

- systemd user services for managing llama.cpp server on Linux
- NVIDIA, AMD, Metal, or CPU runtime acceleration depending on platform and provider
- GitHub CLI for repository publishing and PR workflows
- A reviewed self-hosted SearXNG endpoint for optional bounded public-web
  research; narrow DuckDuckGo Instant Answer lookup requires no key, and
  ordinary local conversation does not require either network path
- `uv` and FFmpeg for separately gated creative tooling. They are not required
  for base conversation or the dashboard.
- A reviewed AMD Vulkan device/runtime for the production Music Studio
  ACE-Step lane and Visual Studio FLUX.2 still-image lane. Hardware-specific
  model setup is always separate from base setup.
- NVIDIA CUDA remains the supported Qwen reserve/chat device for AMD-Free and
  Music Cores on the owner-reviewed topology. The older NVIDIA Music pilot is
  retained as compatibility evidence rather than the production path.
- The separately gated Music Studio vocal-analysis option installs its own
  pinned whisper.cpp command and English model. It uses bounded CPU time only
  when explicitly triggered and does not create a resident process or service.
- The separately gated music-reference option prefers an operating-system
  yt-dlp package and uses `uv` to install pinned Essentia in an ignored
  project-local environment. A pinned local yt-dlp is used only when no system
  command exists. FFmpeg remains a system prerequisite. These tools run only
  for an exact-confirmed foreground URL analysis and retain no source audio in
  analysis-only mode.

Optional Music tooling uses `uv` to create isolated environments without
changing the distribution-managed Python installation. Install `uv` through
the operating system package manager when available; then run `make
music-check`. Soul does not bootstrap `uv` by downloading and executing a
remote installer.

## Optional web knowledge paths

Soul separates orientation from research:

- `web.lookup` makes one bounded DuckDuckGo Instant Answer request for narrow
  definitions or known entities. An empty answer is normal and never becomes
  permission to invent retrieved evidence.
- `web.research` queries the explicitly configured SearXNG JSON endpoint,
  retrieves selected public HTTPS sources, and retains provenance for local
  synthesis, approval-gated artifacts, and review-only reflection candidates.

For a SearXNG container on another trusted LAN host, keep its address only in
the ignored `.env` and set:

```text
SOUL_WEB_SEARCH_PROVIDER=searxng
SOUL_WEB_SEARXNG_URL=http://YOUR-SEARXNG-HOST:PORT
SOUL_WEB_ALLOW_PRIVATE_SEARXNG=true
```

The private-network exception applies only to that exact configured SearXNG
authority. Search-result URLs and redirects remain public-HTTPS-only. Ensure
JSON output is enabled in SearXNG's `search.formats` configuration; otherwise
its API returns HTTP 403. See the official
[SearXNG Search API](https://docs.searxng.org/dev/search_api.html).

## Runtime provider support

Soul/ talks to model runtimes through an OpenAI-compatible API shape.

That means the project can support both llama.cpp server and Ollama at the API layer.

The setup workflows differ:

| Provider | API support | Model setup |
|---|---|---|
| llama.cpp | OpenAI-compatible local server | GGUF file, often downloaded from Hugging Face |
| Ollama | OpenAI-compatible local endpoint | Ollama model name, usually installed with `ollama pull` |

## Current tested llama.cpp defaults

```text
Endpoint: http://127.0.0.1:8082/v1
API alias: soul-local-chat
Model file: Qwen3-8B-Q4_K_M.gguf
Model source: Qwen/Qwen3-8B-GGUF on Hugging Face
Context size: 4096
Prediction budget: 2048
K/V cache: f16/f16
Flash attention: off
Reasoning format: deepseek
Jinja templates: enabled
```

These are tested defaults, not universal requirements.

## Current supported Ollama profile

```text
Endpoint: http://127.0.0.1:11434/v1
API alias: soul-local-chat
Model: Gemma 4 12B Instruct 2512 Q4_K_M
Accelerator: AMD Vulkan
```

Generic Ollama setup still accepts an explicit Ollama model name and uses
`ollama pull`; promotion into a supported Core requires a separate acceptance
review.

Do not assume an arbitrary Hugging Face GGUF URL can be used directly with Ollama without an intentional import/build step.
