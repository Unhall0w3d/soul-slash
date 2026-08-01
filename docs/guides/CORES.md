# Soul Cores

Soul's Cores are reviewed runtime arrangements, not different personalities or
copies of the application. Internal IDs remain stable so existing local state
continues to work, while the Dashboard uses the current names below.

| Core | Internal ID | Chat | AMD lane |
| --- | --- | --- | --- |
| Soul Core | `daily` | Gemma on AMD | occupied by chat |
| Soul-Lite Core | `amd-free` | Qwen on NVIDIA | free for the Operator |
| Creative Core | `music` | Qwen on NVIDIA | available to bounded creative runtimes |
| Free Core | `free` | unloaded | free |
| Dev Core | `dev` | Qwen on NVIDIA | GPT-OSS 20B resident for development work |

Free Core deliberately makes the rest of the authenticated Dashboard inert and
blurred. Choose another Core from its selection window to resume. It does not
silently load a fallback model.

Dev Core uses the reviewed local Ollama/Vulkan artifact `gpt-oss:20b`, bound to
its configured SHA-256 digest. A scoped Dev request from Soul Core temporarily
moves chat to Soul-Lite, performs one bounded request, unloads GPT-OSS, and
restores Soul Core. A scoped request from Soul-Lite leaves Qwen in place. Dev
work never preempts Creative Core or another active AMD-generation lease.

## Optional Dev runtime setup

The public repository contains no machine-specific model paths or private
state. Inspect the inactive, loopback-only unit before installing it:

```sh
make model-runtime-dev-plan OLLAMA_SHA256=<installed-ollama-binary-sha256>
make model-runtime-dev-install OLLAMA_SHA256=<same-digest> \
  CONFIRM=INSTALL_INACTIVE_DEV_OLLAMA_UNIT
make model-runtime-dev-status
```

The default reviewed model is `gpt-oss:20b`; `DEV_SOURCE_MODEL`,
`DEV_API_MODEL`, `DEV_MODEL_DIGEST`, and `DEV_PORT` are explicit overrides.
An override must name an already reviewed local Ollama artifact and supply its
exact digest. Installation creates an inactive, unenabled user unit; selecting
Dev Core or accepting a scoped Dev action is what starts it.

Mistral configuration is retained only as an explicit fallback for the brief
draft/review commands. It is never selected silently after a local failure.
