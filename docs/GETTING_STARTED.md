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

`make check` normalizes the executable bit on tracked `scripts/soul-*.sh`
helpers before checking tools. `make detect`, `make setup`, and the related
runtime targets perform the same repository-local normalization before they
run.

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

Inspect the supported model defaults and local override points:

```bash
make defaults-show
```

For persistent machine-local substitutions, copy the tracked example to the
ignored local include:

```bash
cp config/model_overrides.example.mk Makefile.local
```

Edit `Makefile.local`, never the public defaults, for exact local model choices.
One-off `make VARIABLE=value target` assignments take precedence over both.

## 3. Choose a runtime provider

Soul/ uses a local model runtime through an OpenAI-compatible API.

### Optional dashboard model controls

Soul can manually load or unload one existing, explicitly configured `systemd --user` model service. This is opt-in and does not install, enable, or download anything:

```text
SOUL_MODEL_RUNTIME_CONTROL=1
SOUL_MODEL_RUNTIME_SERVICE=llama-server.service
SOUL_MODEL_RUNTIME_SLOTS_URL=http://127.0.0.1:8082/slots
SOUL_MODEL_RUNTIME_PROFILE=nvidia-fallback
```

After the single-profile controls work, an optional ignored profile inventory
can expose up to four services for manual, preview-gated switching:

```bash
cp Soul/config/model_runtime_profiles.example.yaml Soul/config/model_runtime_profiles.local.yaml
```

Then add this to the private `.env`:

```text
SOUL_MODEL_RUNTIME_PROFILES_FILE=Soul/config/model_runtime_profiles.local.yaml
```

Every profile must use the same configured loopback endpoint, slots endpoint,
and model alias. The profile file contains only IDs, labels, and allowlisted user
service names; machine paths and model arguments remain in private systemd unit
configuration. A listed service that is not installed appears unavailable and
cannot be selected. Switching is always manual and separately confirmed.

### Recommended AMD Daily Core: Gemma through Ollama/Vulkan

The supported AMD profile is Gemma 4 12B Instruct Q4_K_M through the local
Ollama-compatible service. Install Ollama and the exact reviewed model first,
record the local executable and model digests, then preview the inactive unit:

```bash
make model-runtime-gemma-plan \
  OLLAMA_SHA256=<recorded-ollama-sha256> \
  GEMMA_MODEL_DIGEST=<recorded-local-model-digest>
```

After reviewing the JSON plan, repeat those inputs and add:

```bash
make model-runtime-gemma-install \
  OLLAMA_SHA256=<recorded-ollama-sha256> \
  GEMMA_MODEL_DIGEST=<recorded-local-model-digest> \
  CONFIRM=INSTALL_INACTIVE_GEMMA_OLLAMA_UNIT
make model-runtime-gemma-status
```

The action installs an inactive, unenabled user unit. It does not stop another
runtime or select Gemma automatically. Use the dashboard's digest-bound runtime
or Core switch after adding `amd-gemma` to the private profile inventory.

### Legacy/custom inactive AMD llama.cpp unit

The generic AMD llama.cpp deployment remains available for migration and custom
model experiments, but it is not Soul's supported Daily Core. After separately
validating a Vulkan binary and model, preview an inactive unit with explicit
local paths and recorded digests:

```bash
make model-runtime-amd-plan \
  AMD_SERVER=/path/to/versioned-vulkan/llama-server \
  AMD_MODEL=/path/to/model.gguf \
  AMD_SERVER_SHA256=<recorded-sha256> \
  AMD_MODEL_SHA256=<recorded-sha256> \
  AMD_MODEL_ALIAS=<same-alias-as-the-current-provider>
```

After reviewing the JSON plan:

```bash
make model-runtime-amd-install \
  AMD_SERVER=/path/to/versioned-vulkan/llama-server \
  AMD_MODEL=/path/to/model.gguf \
  AMD_SERVER_SHA256=<recorded-sha256> \
  AMD_MODEL_SHA256=<recorded-sha256> \
  AMD_MODEL_ALIAS=<same-alias-as-the-current-provider> \
  CONFIRM=INSTALL_INACTIVE_AMD_MODEL_UNIT
```

This writes only `~/.config/systemd/user/soul-model-amd.service`, reloads the
user manager, and verifies the unit is inactive and unenabled. It never starts
AMD or stops the current runtime. Check or remove it with:

```bash
make model-runtime-amd-status
make model-runtime-amd-uninstall CONFIRM=REMOVE_INACTIVE_AMD_MODEL_UNIT
```

Removal refuses to stop an active unit. This legacy path must not be added to a
production profile inventory without a new model-acceptance review. See
`docs/soul/MODEL_RUNTIME_PORTABILITY_2B_AMD_UNIT_BRIEF.md`.

The llama.cpp service must expose `/slots`. The authenticated dashboard blocks unload or switching while Soul has an active provider lease, llama.cpp has an active slot, or idle state cannot be proven. See `docs/soul/AMD_VULKAN_MODEL_RUNTIME_MIGRATION.md` for the reversible AMD/NVIDIA profile design.

### Start the last selected model profile at login

After multi-profile switching and both user units have been reviewed, replace a
single model's autostart with Soul's bounded selected-profile startup policy:

```bash
make model-runtime-startup-plan
make model-runtime-startup-install CONFIRM=INSTALL_SELECTED_MODEL_STARTUP
make model-runtime-startup-status
```

No reboot is required. Installation enables one systemd user oneshot and
disables the legacy `llama-server.service` startup link without using `--now`,
so it does not stop or restart the active model. On a future user-manager start,
the oneshot reads Soul's last human-confirmed profile selection, starts at most
that one allowlisted model service, and exits. It blocks rather than stopping an
unexpected active service.

To verify the policy against the current session without restarting a model:

```bash
make model-runtime-startup-reconcile
```

If the selected profile is already active, this is a mutation-free success.
Removal is separately confirmed and restores legacy NVIDIA autostart:

```bash
make model-runtime-startup-uninstall CONFIRM=REMOVE_SELECTED_MODEL_STARTUP
```

See `docs/soul/MODEL_RUNTIME_PORTABILITY_2D_SELECTED_STARTUP_BRIEF.md` for the
exact persistence exception and failure behavior.

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

Stable local API alias:

```text
soul-local-chat
```

This alias is the provider contract. The actual model identity is tracked
separately by the selected runtime profile and may change when profiles switch.

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

Default reviewed Ollama model:

```text
gemma4:12b-it-q4_K_M
```

Use `OLLAMA_MODEL=<exact-tag>` on the Make invocation or in ignored
`Makefile.local` to select another installed tag. The supported Soul Daily Core
remains the reviewed Gemma profile described earlier; another tag is a local
experiment until separately accepted.

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

## 11. Start the dashboard

```bash
make dashboard
```

Open `http://127.0.0.1:4567/` locally. The dashboard includes Chat, grouped
Self Improvement surfaces (Skill Studio, Self Assessment, and Self
Augmentation), grouped Creative Studios (Music and Visual), Administration
(Project Timeline, Backup & Recovery, and Guided Maintenance), and Review
Center. Project Timeline initializes its ignored
owner-local working ledger from the neutral public seed on first use; see
`docs/guides/PROJECT_TIMELINE.md`.
This command binds to loopback, runs in the foreground, and stops with Ctrl+C.

First-run dashboard access uses the fixed administrator username `admin` and bootstrap password `soul123`. The bootstrap session cannot load dashboard data. Replace it with a private password of 12–128 characters when prompted. Soul stores only the salted derived credential under ignored `Soul/runtime/dashboard_auth/` storage.

If the administrator password is lost, stop the dashboard and explicitly restore the bootstrap gate:

```bash
make dashboard-reset-admin
```

This revokes active sessions and again requires password replacement. It does not start the dashboard.

Use an ignored local `.env` or an invocation-only override for a different port:

```bash
ruby bin/soul dashboard --set dashboard.port=4568
```

Do not commit operator-specific hostnames, addresses, credentials, model aliases, or filesystem paths.

Do not widen Soul's bind host for LAN access. The reviewed persistent path below
keeps Soul loopback-only and places Caddy at the explicit HTTPS boundary.

## 12. Optional persistent LAN dashboard

The reviewed Linux deployment keeps Soul on loopback and uses Caddy for HTTPS on one exact LAN address. Complete the first-login password change above before installing it.

1. Install Caddy using your distribution's trusted package source. On Arch/CachyOS: `sudo pacman -S caddy`.
2. Give this user a boot-started systemd user manager, if it does not already have one: `sudo loginctl enable-linger "$USER"`.
3. Give the host a stable LAN IPv4 address, preferably with a DHCP reservation.
4. Preview without writing anything:

   ```bash
   make dashboard-service-plan LAN_HOST=<assigned-lan-ip>
   ```

   If the operator has already created a private DNS record for that exact
   address, the reviewed public authority may use it without changing the
   listener bind:

   ```bash
   make dashboard-service-plan \
     LAN_HOST=<assigned-lan-ip> \
     DASHBOARD_PUBLIC_HOST=<private-dns-name>
   ```

5. After reviewing the plan, install exactly the two approved user services:

   ```bash
   make dashboard-service-install \
     LAN_HOST=<assigned-lan-ip> \
     DASHBOARD_PUBLIC_HOST=<private-dns-name> \
     CONFIRM=INSTALL_SOUL_LAN_SERVICES
   ```

   Omit `DASHBOARD_PUBLIC_HOST` from both commands to retain the assigned-IP
   HTTPS origin.

6. If UFW denies incoming traffic, add a rule limited to the trusted LAN and exact host rather than allowing the port globally:

   ```bash
   sudo ufw allow from <trusted-lan-cidr> to <assigned-lan-ip> port 8443 proto tcp comment 'Soul dashboard LAN HTTPS'
   ```

7. Copy only `~/.local/share/caddy/pki/authorities/local/root.crt` to each selected device, install it as a trusted CA, and verify the browser shows no certificate warning at the exact planned URL. Never copy Caddy's private CA key.
8. Verify login, refresh, and logout from the client device. Check local service state with `make dashboard-service-status` and logs with `make dashboard-service-logs`.

Soul does not change the firewall, router, DHCP, client trust store, or Internet exposure automatically. Full security boundaries and rollback instructions are in `docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md`.

## 13. Try intent routing

```bash
ruby bin/soul intent "run a file cleanup in Downloads"
ruby bin/soul intent "restore the last downloads cleanup"
```

## 14. Try the cleanup workflow

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

## 15. Reflection

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

## 16. Common Make targets

```text
make help             Show available targets
make check            Normalize tracked script modes, then check local tools
make detect           Detect runtimes, endpoints, config, and local GGUF models
make defaults-show    Show supported model defaults and override points
make supported-stack-check  Inspect every supported creative runtime lane
make setup            Normalize tracked script modes, then guide runtime setup
make setup-llamacpp   Configure llama.cpp provider
make setup-ollama     Configure Ollama provider
make music-check      Check optional Music pilot tools; does not install
make music-pilot-plan Preview pinned environment and exact checkpoint bytes
make setup-music      Install only after plan digest and exact confirmation
make music-model-download  Download verified weights after a separate gate
make music-pilot-run  Run one foreground 30/90/180-second feasibility pilot
make music-vulkan-setup-plan  Preview the production AMD Vulkan music runtime
make music-vulkan-download-plan  Preview exact production music model bytes
make music-transcription-plan  Preview optional pinned CPU vocal analysis
make music-transcription-install  Install it after digest and exact confirmation
make voice-transcription-check  Verify Chat push-to-talk dependencies
make voice-transcription-plan  Preview the shared pinned CPU transcription install
make voice-synthesis-check  Verify bounded local Chat speech dependencies
make voice-synthesis-plan  Preview the pinned Supertonic 3 install
make voice-synthesis-audition  Render the reviewed feminine/masculine comparisons
make music-reference-tooling-check  Inspect optional URL-analysis tools
make music-reference-tooling-plan  Preview the pinned local tooling environment
make music-reference-tooling-install  Install after digest and exact confirmation
make visual-check     Inspect the optional Visual Studio still-image lane
make visual-runtime-plan  Preview the pinned Vulkan image runtime
make visual-model-download-plan  Preview exact FLUX.2 Klein model bytes
make visual-motion-check  Inspect the Wan 2.2 image-guided motion lane
make visual-native-check  Inspect the FastWan 2.2 native-video lane
make visual-motion-model-download-plan  Preview exact Wan model bytes
make visual-native-model-download-plan  Preview exact FastWan model bytes
make verify-music-publication-package  Test exact local upload packaging
make test-runtime     Test configured runtime
make test-fast        Test FAST/no_think request mode
make test-think       Test THINK request mode
make test-soul        Run basic Soul/ CLI checks
make doctor           Run Soul/ doctor
make env-show         Show local runtime config
make fix-mtimes       Touch repo files if ZIP timestamps caused Make clock-skew warnings
```

The original CUDA Music pilot remains available as compatibility evidence. Its
defaults are the reviewed 8 GiB pair:
`MUSIC_DIT_MODEL=acestep-v15-turbo` and
`MUSIC_LM_MODEL=acestep-5Hz-lm-0.6B`. Override either with an exact,
case-sensitive name present in `MUSIC_MODEL_MANIFEST`; unknown names stop
without downloading. ACE-Step checkpoints are directories rather than GGUF
files, so the exact checkpoint name is the equivalent of `SOUL_MODEL_FILE`.

Start by reviewing the plan:

```bash
make music-check
make music-pilot-plan
```

The plan prints the current digest and distinct confirmation phrases. Setup and
model download never run as part of `make setup`, and neither starts a service,
listener, worker, or background process. See
`docs/soul/MUSIC_STUDIO_A1_SETUP_BRIEF.md` before proceeding.

The production creative lanes use signed-off JSON manifests. Their Make
variables are `MUSIC_VULKAN_MANIFEST`, `VISUAL_MODEL_MANIFEST`,
`VISUAL_MOTION_MANIFEST`, `VISUAL_NATIVE_MANIFEST`, and
`MUSIC_TRANSCRIPTION_MANIFEST`. A custom model is supplied through a complete
custom manifest containing its repository, immutable revision, exact
case-sensitive filename, byte size, SHA-256, and compatible runtime profile.
Soul intentionally does not accept an arbitrary creative-model filename alone:
doing so would discard integrity and compatibility evidence.

The current production Music Core uses the separately reviewed AMD Vulkan
lane. Install it only after reviewing each exact plan:

```bash
make music-vulkan-setup-plan
make music-vulkan-setup \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_MUSIC_VULKAN_RUNTIME

make music-vulkan-download-plan
make music-vulkan-download \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=DOWNLOAD_MUSIC_VULKAN_MODELS
```

This lane uses the pinned ACE-Step 1.5 4B LM / 2B Turbo Q8_0 model set. Music
Studio loads it only for one bounded generation and removes successful WAV/LM
intermediates after publishing validated FLAC and MP3 artifacts. See
`docs/guides/MUSIC_STUDIO.md` for the current Operator flow.

Vocal analysis is a separate optional install. Its reviewed default is the
exact `ggml-small.en.bin` filename from `MUSIC_TRANSCRIPTION_MANIFEST`; a
different filename must match another manifest entry exactly. Review and run:

```bash
make music-transcription-plan
make music-transcription-install EXPECTED_DIGEST=<digest-from-plan> CONFIRM=INSTALL_SOUL_MUSIC_TRANSCRIPTION
```

This installs a pinned CPU-only whisper.cpp command and model. It does not
create or start a service. Music Studio invokes it only after an exact
per-candidate preview and confirmation; the process exits and releases its
memory after transcription, failure, cancellation, timeout, or an abandoned
dashboard stream. Machine-heard OK leads to human testing. Machine-heard BAD
leads to an Operator-triggered revision attempt. Neither result is approval.

Chat push-to-talk shares this exact runtime. It additionally requires a current
browser with `getUserMedia` and `MediaRecorder`, system `ffmpeg`/`ffprobe`, and
a secure browser context. Loopback HTTP is accepted by browsers; an iPhone or
other LAN client should use the reviewed Caddy HTTPS origin and trust its local
CA. Check or install the shared runtime through the voice-named aliases:

```bash
make voice-transcription-check
make voice-transcription-plan
make voice-transcription-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_SOUL_MUSIC_TRANSCRIPTION
```

The recording is limited to sixty seconds and eight MiB and transcribed on CPU.
The Dashboard inserts the returned transcript and submits it once through the
ordinary Chat path; the recording, normalized WAV, and raw recognition output
are deleted before the transcription request returns. See
`docs/guides/VOICE_INPUT.md` for use and portable override details.

Chat speech output is a separate optional local install. Its default is
Supertonic 3 package `1.3.1`, model revision
`724fb5abbf5502583fb520898d45929e62f02c0b`, and feminine voice profile `F3`.
The code is MIT licensed; the model weights use OpenRAIL-M. Review and run:

```bash
make voice-synthesis-check
make voice-synthesis-plan
make voice-synthesis-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_SOUL_VOICE_SYNTHESIS
```

The installer uses an already installed Python 3.12 through `uv`, creates an
isolated user-local environment, verifies the pinned asset digests, and exits.
It does not create a TTS service. Each explicit per-message **Speak** click
starts one bounded CPU process; **Stop**, navigation, logout, or natural
completion disposes browser playback. The Chat selector hot-swaps between the
curated `F3` and provisional `M3` profiles per request without restarting or
changing Cores. Compare `F1`/`F3`/`F5` and `M1`/`M3`/`M5` with
`make voice-synthesis-audition`. See
`docs/guides/VOICE_OUTPUT.md` for selection, retention, and portable overrides.

YouTube reference analysis is another optional, separately reviewed path. It
uses system yt-dlp when available and a project-local Python 3.14 environment
for exact default `essentia==2.1b6.dev1438`. If yt-dlp is unavailable, the same
environment receives the exact `yt-dlp==2026.7.4` fallback. Review the plan
before allowing the networked package installation:

```bash
make music-reference-tooling-check
make music-reference-tooling-plan
make music-reference-tooling-install EXPECTED_DIGEST=<digest-from-plan> CONFIRM=INSTALL_MUSIC_REFERENCE_TOOLS
```

This setup creates no service or listener and does not run when Soul starts.
Once installed, Music Studio first performs a metadata-only URL preview. The
separate `ANALYZE_MUSIC_REFERENCE` gate retrieves one bounded transient audio
source, extracts non-expressive evidence, writes a private candidate profile,
and removes source media and the analysis WAV at every terminal outcome.

Visual Studio is also optional and separately gated:

```bash
make visual-check
make visual-runtime-plan
make visual-runtime-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_VISUAL_VULKAN_RUNTIME

make visual-model-download-plan
make visual-model-download \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=DOWNLOAD_VISUAL_VULKAN_MODELS
```

The supported still lane generates private local imagery with FLUX.2 Klein.
The reviewed Wan 2.2 image-guided lane and FastWan 2.2 native text-to-video lane
create short immutable motion candidates. Each renderer exits after its
bounded operation; none creates a background model server. Install and download
each lane only through its separate preview digest and exact confirmation:

```bash
make visual-motion-runtime-plan
make visual-motion-runtime-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_VISUAL_MOTION_VULKAN_RUNTIME
make visual-motion-model-download-plan
make visual-motion-model-download \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=DOWNLOAD_VISUAL_MOTION_MODELS

make visual-native-runtime-plan
make visual-native-runtime-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_VISUAL_MOTION_VULKAN_RUNTIME
make visual-native-model-download-plan
make visual-native-model-download \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=DOWNLOAD_VISUAL_MOTION_MODELS
```

The native lane offers 4-, 8-, and 12-second 832×480 studies delivered at
24 fps. The 12-second profile bounds inference to 193 frames at 16 fps and
performs one local optical-interpolation pass to deliver 289 frames at 24 fps.
An accepted short scene may be repeated to the song duration; Soul does not
claim that repeated presentation is unique long-form generation. See
`docs/guides/VISUAL_STUDIO.md`.

## 17. Optional visible Voice Presence

After the bounded Chat microphone and responsive voice runtimes work, install
the local **Hey Soul** wake surface:

```bash
make voice-presence-plan
make voice-presence-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_SOUL_VOICE_PRESENCE
make voice-presence-launch
```

The window is the consent boundary: it opens the microphone path, shows
listening/thinking/speaking state through Soul's portrait, and closes every
child process when dismissed. It creates no system service. See
`docs/guides/VOICE_PRESENCE.md` for dependencies, authority, privacy, and
portable source overrides.

On Hyprland, one-shot screen understanding uses `grim` and `slurp`. Install
`tesseract` to add bounded literal-label corroboration for monitor/window
requests. OCR is optional and never becomes a resident process.

## 18. Optional Markdown Knowledge Vault

Soul can share one external directory of ordinary Markdown with the Operator.
Obsidian is optional: it can open the directory as a vault, while Soul reads
the files directly through bounded foreground operations.

Keep the personal path in the ignored `.env`:

```dotenv
SOUL_KNOWLEDGE_VAULT_PATH=~/Knowledge/soul-vault
```

Then inspect and initialize the portable structure:

```bash
make knowledge-vault-status
make knowledge-vault-init-preview
make knowledge-vault-init \
  EXPECTED_DIGEST=<digest-from-preview> \
  CONFIRM=INITIALIZE_KNOWLEDGE_VAULT
```

Knowledge Reflection does not silently mine conversations or decide that
something should become durable. For one explicit structured candidate, it
first reports whether the material belongs in the vault, the shared-memory
review flow, a Studio archive, the current conversation only, or nowhere.
Vault-eligible material receives a complete Markdown preview and duplicate
inventory before any write:

```bash
cp config/knowledge_reflection.example.json /tmp/soul-knowledge-candidate.json
# Edit the copy with the reviewed title, body, kind, evidence, and provenance.

make knowledge-vault-reflection-preview \
  KNOWLEDGE_REFLECTION_INPUT=/tmp/soul-knowledge-candidate.json
```

Only after reviewing that exact output:

```bash
make knowledge-vault-reflection-execute \
  KNOWLEDGE_REFLECTION_INPUT=/tmp/soul-knowledge-candidate.json \
  EXPECTED_DIGEST=<digest-from-preview> \
  CONFIRM=WRITE_KNOWLEDGE_VAULT_NOTE
```

Preferences, raw conversation, transient state, unverified claims, Studio
candidate evidence, and likely secrets cannot be redirected into the vault by
this gate. See `docs/guides/KNOWLEDGE_VAULT.md` for the full destination policy,
note-update flow, and runtime boundaries.

From Chat, the explicit request `Reflect on this conversation for reusable
knowledge.` may ask the configured local model for one candidate. Soul shows
the deterministic destination and, only for eligible vault material, the full
Markdown plus an exact `WRITE_KNOWLEDGE_VAULT_NOTE <candidate_id>
<preview_digest>` command. Casual discussion never invokes this planner.

No watcher, resident index, automatic synchronization, or automatic memory
promotion is installed. See
`docs/guides/KNOWLEDGE_VAULT.md` for bounded search, reviewed memory projection,
candidate import, Obsidian, and optional private Git use.

## 19. Clock-skew warning after applying overlays

If `make` complains that files have modification times in the future, run:

```bash
make fix-mtimes
```

This touches working-tree files to your current local system time.

It is not elegant. It is a broom. Sometimes a broom is exactly the tool.
