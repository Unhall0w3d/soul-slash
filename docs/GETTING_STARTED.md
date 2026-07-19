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

Example generic Ollama model:

```text
qwen3:8b
```

The supported Soul Daily Core is the reviewed Gemma profile described earlier;
the generic setup path remains useful for clean clones and experiments.

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
Augmentation), grouped Creative Studios (Music and Visual), and Review Center.
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

5. After reviewing the plan, install exactly the two approved user services:

   ```bash
   make dashboard-service-install \
     LAN_HOST=<assigned-lan-ip> \
     CONFIRM=INSTALL_SOUL_LAN_SERVICES
   ```

6. If UFW denies incoming traffic, add a rule limited to the trusted LAN and exact host rather than allowing the port globally:

   ```bash
   sudo ufw allow from <trusted-lan-cidr> to <assigned-lan-ip> port 8443 proto tcp comment 'Soul dashboard LAN HTTPS'
   ```

7. Copy only `~/.local/share/caddy/pki/authorities/local/root.crt` to each selected device, install it as a trusted CA, and verify the browser shows no certificate warning at `https://<assigned-lan-ip>:8443/`. Never copy Caddy's private CA key.
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
make check            Check required/recommended local tools only
make detect           Detect runtimes, endpoints, config, and local GGUF models
make setup            Guided runtime setup
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
make music-reference-tooling-check  Inspect optional URL-analysis tools
make music-reference-tooling-plan  Preview the pinned local tooling environment
make music-reference-tooling-install  Install after digest and exact confirmation
make visual-check     Inspect the optional Visual Studio still-image lane
make visual-runtime-plan  Preview the pinned Vulkan image runtime
make visual-model-download-plan  Preview exact FLUX.2 Klein model bytes
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

The supported production lane generates private local stills with FLUX.2
Klein, exits after each render, and provides no background server. Generated
motion targets in the Makefile remain qualification tooling, not a production
dashboard feature. See `docs/guides/VISUAL_STUDIO.md`.

## 17. Clock-skew warning after applying overlays

If `make` complains that files have modification times in the future, run:

```bash
make fix-mtimes
```

This touches working-tree files to your current local system time.

It is not elegant. It is a broom. Sometimes a broom is exactly the tool.
