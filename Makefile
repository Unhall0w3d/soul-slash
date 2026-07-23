.RECIPEPREFIX := >
SHELL := /usr/bin/env bash

# Soul/ public runtime Makefile
#
# Generic public dispatcher. Local runtime values belong in .env.

PROJECT_ROOT := $(CURDIR)
LOCAL_MAKEFILE ?= $(PROJECT_ROOT)/Makefile.local
-include $(LOCAL_MAKEFILE)

ENV_FILE ?= $(PROJECT_ROOT)/.env
LAN_HOST ?=
DASHBOARD_HTTPS_PORT ?= 8443
CONFIRM ?=
LLAMACPP_MODEL_FILE ?= Qwen3-8B-Q4_K_M.gguf
LLAMACPP_MODEL_URL ?= https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true
OLLAMA_MODEL ?= gemma4:12b-it-q4_K_M
GEMMA_SOURCE_MODEL ?= $(OLLAMA_MODEL)
GEMMA_API_MODEL ?= soul-local-chat
GEMMA_PORT ?= 8082
AMD_SERVER ?=
AMD_MODEL ?=
AMD_SERVER_SHA256 ?=
AMD_MODEL_SHA256 ?=
AMD_MODEL_ALIAS ?=
AMD_PORT ?=8082
ALIAS_DIGEST ?=
EXPECTED_DIGEST ?=
MUSIC_ROOT ?= $(HOME)/.local/share/soul/music
MUSIC_MODEL_MANIFEST ?= $(PROJECT_ROOT)/config/music_vulkan_models.json
MUSIC_LEGACY_MANIFEST ?= $(PROJECT_ROOT)/config/music_pilot_models.json
MUSIC_DIT_MODEL ?= acestep-v15-turbo
MUSIC_LM_MODEL ?= acestep-5Hz-lm-0.6B
MUSIC_DURATION ?= 30
MUSIC_VULKAN_MANIFEST ?= $(PROJECT_ROOT)/config/music_vulkan_models.json
MUSIC_TRANSCRIPTION_MANIFEST ?= $(PROJECT_ROOT)/config/music_transcription_models.json
MUSIC_TRANSCRIPTION_MODEL ?= ggml-small.en.bin
MUSIC_REFERENCE_PYTHON ?= 3.14
MUSIC_REFERENCE_YTDLP_VERSION ?= 2026.7.4
MUSIC_REFERENCE_ESSENTIA_VERSION ?= 2.1b6.dev1438
MUSIC_REFERENCE_ENRICHMENT_MANIFEST ?= $(PROJECT_ROOT)/config/music_reference_enrichment_models.json
MUSIC_REFERENCE_MODEL_CACHE ?=
VISUAL_ROOT ?= $(HOME)/.local/share/soul/visual
VISUAL_MODEL_MANIFEST ?= $(PROJECT_ROOT)/config/visual_studio_models.json
VISUAL_MOTION_ROOT ?= $(HOME)/.local/share/soul/visual-motion
VISUAL_MOTION_MANIFEST ?= $(PROJECT_ROOT)/config/visual_motion_models.json
VISUAL_MOTION_INPUT ?=
VISUAL_NATIVE_ROOT ?= $(HOME)/.local/share/soul/visual-native
VISUAL_NATIVE_MANIFEST ?= $(PROJECT_ROOT)/config/visual_native_models.json

.PHONY: help defaults-show supported-stack-check check setup setup-llamacpp setup-ollama setup-music music-check music-pilot-plan music-model-download music-pilot-run music-vulkan-check music-vulkan-setup-plan music-vulkan-setup music-vulkan-download-plan music-vulkan-download music-vulkan-run-plan music-vulkan-run verify-music-core-vulkan visual-check visual-runtime-plan visual-runtime-install visual-model-download-plan visual-model-download visual-motion-check visual-motion-runtime-plan visual-motion-runtime-install visual-motion-model-download-plan visual-motion-model-download visual-motion-pilot-plan visual-motion-pilot-run visual-native-check visual-native-runtime-plan visual-native-runtime-install visual-native-model-download-plan visual-native-model-download verify-visual-motion-qualification verify-visual-native-video music-transcription-plan music-transcription-install music-reference-tooling-check music-reference-tooling-plan music-reference-tooling-install music-reference-enrichment-check music-reference-enrichment-plan music-reference-enrichment-install music-projects music-resources music-project-create music-project-inspect music-generate-preview music-generate-execute music-cancel-preview music-cancel-execute verify-music-a2 verify-music-vocal-analysis verify-music-references verify-music-reference-analysis verify-music-reference-synthesis verify-music-lite-edit verify-music-publication-package verify-character-identity detect test-runtime test-fast test-think test-soul doctor env-show download-model start-llamacpp foreground-llamacpp dashboard dashboard-reset-admin dashboard-service-plan dashboard-service-install dashboard-service-status dashboard-service-logs dashboard-service-uninstall verify-web-knowledge verify-model-runtime-controls model-runtime-amd-plan model-runtime-amd-install model-runtime-amd-status model-runtime-amd-uninstall model-runtime-gemma-plan model-runtime-gemma-install model-runtime-gemma-status model-runtime-gemma-uninstall model-runtime-startup-plan model-runtime-startup-install model-runtime-startup-status model-runtime-startup-uninstall model-runtime-startup-reconcile model-runtime-identity-plan model-runtime-identity-execute private-memory-plan private-memory-execute verify-private-memory clean-runtime chmod-scripts fix-mtimes

help:
> @echo "Soul/ public setup Makefile"
> @echo
> @echo "Common targets:"
> @echo "  make check             Check required/recommended local tools only"
> @echo "  make detect            Detect runtime binaries, endpoints, .env, and local models"
> @echo "  make setup             Detect providers and guide setup"
> @echo "  make defaults-show     Show public model/runtime defaults and override points"
> @echo "  make supported-stack-check  Inspect all supported creative runtime lanes"
> @echo "  make setup-llamacpp    Configure llama.cpp server provider"
> @echo "  make setup-ollama      Configure Ollama provider"
> @echo "  make music-check       Check optional Music pilot tools (including uv)"
> @echo "  make music-pilot-plan  Preview pinned ACE-Step environment and model downloads"
> @echo "  make setup-music EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_MUSIC_PILOT"
> @echo "  make music-model-download EXPECTED_DIGEST=... CONFIRM=DOWNLOAD_SOUL_MUSIC_MODELS"
> @echo "  make music-pilot-run MUSIC_DURATION=30  Run one bounded foreground pilot"
> @echo "  make music-vulkan-setup-plan  Preview the pinned AMD Vulkan ACE-Step runtime"
> @echo "  make music-vulkan-download-plan  Preview the exact 4B LM / 2B Turbo GGUF set"
> @echo "  make music-vulkan-run-plan MUSIC_INPUT=/path/request.json  Preview one AMD pilot"
> @echo "  make visual-check      Inspect the optional bounded FLUX.2 Vulkan lane"
> @echo "  make visual-runtime-plan  Preview the pinned stable-diffusion.cpp Vulkan build"
> @echo "  make visual-model-download-plan  Preview exact FLUX.2 Klein model bytes"
> @echo "  make visual-motion-check  Inspect the isolated Wan 2.2 motion qualification lane"
> @echo "  make visual-motion-runtime-plan  Preview the pinned motion Vulkan build"
> @echo "  make visual-motion-model-download-plan  Preview exact Wan 2.2 pilot model bytes"
> @echo "  make visual-motion-pilot-plan VISUAL_MOTION_INPUT=/path/request.json"
> @echo "  make visual-native-check  Inspect the optional FastWan text-to-video lane"
> @echo "  make visual-native-model-download-plan  Preview exact FastWan model bytes"
> @echo "  make music-transcription-plan  Preview the optional pinned CPU vocal-analysis install"
> @echo "  make music-transcription-install EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_MUSIC_TRANSCRIPTION"
> @echo "  make music-reference-enrichment-plan  Preview pinned rich reference-analysis models"
> @echo "  make music-reference-enrichment-install EXPECTED_DIGEST=... CONFIRM=INSTALL_MUSIC_REFERENCE_ENRICHMENT"
> @echo "  make verify-music-reference-synthesis  Test reference synthesis retry approval and fusion gates"
> @echo "  make verify-music-lite-edit  Test immutable-source start/end trimming and receipts"
> @echo "  make verify-music-publication-package  Test local YouTube upload packages"
> @echo "  make music-projects    List private Music Studio projects"
> @echo "  make music-resources   Inspect AMD/NVIDIA/CPU Music resource lanes"
> @echo "  make music-project-create MUSIC_INPUT=/path/project.json"
> @echo "  make music-generate-preview MUSIC_PROJECT_ID=music_..."
> @echo "  make music-generate-execute MUSIC_PROJECT_ID=... MUSIC_CANDIDATE_ID=... EXPECTED_DIGEST=... CONFIRM=START_MUSIC_GENERATION"
> @echo "  make test-runtime      Test configured OpenAI-compatible runtime"
> @echo "  make test-fast         Test FAST/no_think request mode"
> @echo "  make test-think        Test THINK request mode"
> @echo "  make doctor            Run Soul/ doctor"
> @echo "  make test-soul         Run basic Soul/ CLI checks"
> @echo
> @echo "Dashboard targets:"
> @echo "  make dashboard         Run the authenticated dashboard in the foreground"
> @echo "  make dashboard-reset-admin  Reset admin access to the forced-change bootstrap gate"
> @echo "  make dashboard-service-plan LAN_HOST=<assigned-ip>"
> @echo "  make dashboard-service-install LAN_HOST=<assigned-ip> CONFIRM=INSTALL_SOUL_LAN_SERVICES"
> @echo "  make dashboard-service-status"
> @echo "  make dashboard-service-logs"
> @echo "  make dashboard-service-uninstall CONFIRM=REMOVE_SOUL_LAN_SERVICES"
> @echo "  make verify-web-knowledge  Test bounded lookup, SearXNG research, reflection, and chat streaming"
> @echo "  make verify-model-runtime-controls  Test leases and preview-gated model controls"
> @echo "  make verify-character-identity  Test character assets, palette, contrast, and unchanged mark geometry"
> @echo "  make model-runtime-amd-plan AMD_SERVER=... AMD_MODEL=... AMD_SERVER_SHA256=... AMD_MODEL_SHA256=... AMD_MODEL_ALIAS=..."
> @echo "  make model-runtime-amd-install ... CONFIRM=INSTALL_INACTIVE_AMD_MODEL_UNIT"
> @echo "  make model-runtime-amd-status"
> @echo "  make model-runtime-amd-uninstall CONFIRM=REMOVE_INACTIVE_AMD_MODEL_UNIT"
> @echo "  make model-runtime-gemma-plan OLLAMA_SHA256=... GEMMA_MODEL_DIGEST=..."
> @echo "  make model-runtime-gemma-install ... CONFIRM=INSTALL_INACTIVE_GEMMA_OLLAMA_UNIT"
> @echo "  make model-runtime-gemma-status"
> @echo "  make model-runtime-startup-plan"
> @echo "  make model-runtime-startup-install CONFIRM=INSTALL_SELECTED_MODEL_STARTUP"
> @echo "  make model-runtime-startup-status"
> @echo "  make model-runtime-startup-reconcile  Verify/start the selected profile once"
> @echo "  make model-runtime-startup-uninstall CONFIRM=REMOVE_SELECTED_MODEL_STARTUP"
> @echo "  make model-runtime-identity-plan  Preview neutral local API alias migration"
> @echo "  make model-runtime-identity-execute ALIAS_DIGEST=... CONFIRM=MIGRATE_MODEL_ALIAS_TO_SOUL_LOCAL_CHAT"
> @echo
> @echo "llama.cpp helper targets:"
> @echo "  make download-model    Download/validate configured GGUF model"
> @echo "  make start-llamacpp    Start llama.cpp using .env settings"
> @echo "  make foreground-llamacpp  Alias for start-llamacpp"
> @echo
> @echo "Maintenance:"
> @echo "  make env-show          Show local Soul/ runtime config"
> @echo "  make fix-mtimes        Touch repo files if ZIP timestamps caused Make clock-skew warnings"
> @echo
> @echo "Docs:"
> @echo "  docs/GETTING_STARTED.md"
> @echo "  docs/RUNTIME_PROVIDERS.md"
> @echo "  docs/REQUIREMENTS.md"

defaults-show:
> @echo "Soul/ supported defaults (override on the command line or in ignored Makefile.local)"
> @echo "  NVIDIA chat GGUF:       $(LLAMACPP_MODEL_FILE)"
> @echo "  AMD chat Ollama tag:    $(OLLAMA_MODEL)"
> @echo "  Stable API alias:       $(GEMMA_API_MODEL)"
> @echo "  Music manifest:         $(MUSIC_VULKAN_MANIFEST)"
> @echo "  Still-image manifest:   $(VISUAL_MODEL_MANIFEST)"
> @echo "  Image-motion manifest:  $(VISUAL_MOTION_MANIFEST)"
> @echo "  Native-video manifest:  $(VISUAL_NATIVE_MANIFEST)"
> @echo "  Transcription model:    $(MUSIC_TRANSCRIPTION_MODEL)"
> @echo
> @echo "Model manifests bind repository, revision, exact filename, size, and SHA-256."
> @echo "Use a reviewed custom manifest to substitute creative models safely."

supported-stack-check: check music-vulkan-check visual-check visual-motion-check visual-native-check

chmod-scripts:
> @chmod +x scripts/soul-*.sh

fix-mtimes:
> @find . -path ./.git -prune -o -type f -exec touch {} +
> @echo "Touched repository files. If Make warned about future timestamps, it should stop whining now."

check: chmod-scripts
> @scripts/soul-runtime-check.sh

detect: chmod-scripts
> @scripts/soul-runtime-detect.sh

setup: chmod-scripts
> @scripts/soul-runtime-detect.sh --setup

setup-llamacpp: chmod-scripts
> @SOUL_MODEL_FILE="$(LLAMACPP_MODEL_FILE)" SOUL_MODEL_URL="$(LLAMACPP_MODEL_URL)" scripts/soul-setup-llamacpp.sh

setup-ollama: chmod-scripts
> @SOUL_OLLAMA_MODEL="$(OLLAMA_MODEL)" scripts/soul-setup-ollama.sh

music-check:
> @ruby scripts/soul-music-pilot check --manifest "$(MUSIC_LEGACY_MANIFEST)" --root "$(MUSIC_ROOT)" --dit-model "$(MUSIC_DIT_MODEL)" --lm-model "$(MUSIC_LM_MODEL)"

music-pilot-plan:
> @ruby scripts/soul-music-pilot plan --manifest "$(MUSIC_LEGACY_MANIFEST)" --root "$(MUSIC_ROOT)" --dit-model "$(MUSIC_DIT_MODEL)" --lm-model "$(MUSIC_LM_MODEL)"

setup-music:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-pilot-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_MUSIC_PILOT" || { echo "Exact confirmation INSTALL_SOUL_MUSIC_PILOT is required."; exit 2; }
> @ruby scripts/soul-music-pilot setup --manifest "$(MUSIC_LEGACY_MANIFEST)" --root "$(MUSIC_ROOT)" --dit-model "$(MUSIC_DIT_MODEL)" --lm-model "$(MUSIC_LM_MODEL)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

music-model-download:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-pilot-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "DOWNLOAD_SOUL_MUSIC_MODELS" || { echo "Exact confirmation DOWNLOAD_SOUL_MUSIC_MODELS is required."; exit 2; }
> @ruby scripts/soul-music-pilot download --manifest "$(MUSIC_LEGACY_MANIFEST)" --root "$(MUSIC_ROOT)" --dit-model "$(MUSIC_DIT_MODEL)" --lm-model "$(MUSIC_LM_MODEL)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

music-pilot-run:
> @ruby scripts/soul-music-pilot run --manifest "$(MUSIC_LEGACY_MANIFEST)" --root "$(MUSIC_ROOT)" --dit-model "$(MUSIC_DIT_MODEL)" --lm-model "$(MUSIC_LM_MODEL)" --duration "$(MUSIC_DURATION)"

music-vulkan-check:
> @ruby scripts/soul-music-vulkan-pilot check --manifest "$(MUSIC_VULKAN_MANIFEST)" --root "$(MUSIC_ROOT)"

music-vulkan-setup-plan:
> @ruby scripts/soul-music-vulkan-pilot plan --action setup --manifest "$(MUSIC_VULKAN_MANIFEST)" --root "$(MUSIC_ROOT)"

music-vulkan-setup:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-vulkan-setup-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_MUSIC_VULKAN_RUNTIME" || { echo "Exact confirmation INSTALL_MUSIC_VULKAN_RUNTIME is required."; exit 2; }
> @ruby scripts/soul-music-vulkan-pilot setup --action setup --manifest "$(MUSIC_VULKAN_MANIFEST)" --root "$(MUSIC_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

music-vulkan-download-plan:
> @ruby scripts/soul-music-vulkan-pilot plan --action download --manifest "$(MUSIC_VULKAN_MANIFEST)" --root "$(MUSIC_ROOT)"

music-vulkan-download:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-vulkan-download-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "DOWNLOAD_MUSIC_VULKAN_MODELS" || { echo "Exact confirmation DOWNLOAD_MUSIC_VULKAN_MODELS is required."; exit 2; }
> @ruby scripts/soul-music-vulkan-pilot download --action download --manifest "$(MUSIC_VULKAN_MANIFEST)" --root "$(MUSIC_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

music-vulkan-run-plan:
> @test -n "$(MUSIC_INPUT)" || { echo "MUSIC_INPUT=/path/to/request.json is required."; exit 2; }
> @ruby scripts/soul-music-vulkan-pilot plan --action run --request "$(MUSIC_INPUT)" --manifest "$(MUSIC_VULKAN_MANIFEST)" --root "$(MUSIC_ROOT)" $(if $(MUSIC_RETRY_LM_SEED),--retry-lm-seed "$(MUSIC_RETRY_LM_SEED)",)

music-vulkan-run:
> @test -n "$(MUSIC_INPUT)" || { echo "MUSIC_INPUT=/path/to/request.json is required."; exit 2; }
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-vulkan-run-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "RUN_MUSIC_VULKAN_PILOT" || { echo "Exact confirmation RUN_MUSIC_VULKAN_PILOT is required."; exit 2; }
> @ruby scripts/soul-music-vulkan-pilot run --action run --request "$(MUSIC_INPUT)" --manifest "$(MUSIC_VULKAN_MANIFEST)" --root "$(MUSIC_ROOT)" $(if $(MUSIC_RETRY_LM_SEED),--retry-lm-seed "$(MUSIC_RETRY_LM_SEED)",) --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

verify-music-core-vulkan:
> @ruby scripts/verify-music-core-vulkan-feasibility.rb

visual-check:
> @ruby scripts/soul-visual-runtime check --manifest "$(VISUAL_MODEL_MANIFEST)" --root "$(VISUAL_ROOT)"

visual-runtime-plan:
> @ruby scripts/soul-visual-runtime plan --action setup --manifest "$(VISUAL_MODEL_MANIFEST)" --root "$(VISUAL_ROOT)"

visual-runtime-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run visual-runtime-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_VISUAL_VULKAN_RUNTIME" || { echo "Exact confirmation INSTALL_VISUAL_VULKAN_RUNTIME is required."; exit 2; }
> @ruby scripts/soul-visual-runtime setup --manifest "$(VISUAL_MODEL_MANIFEST)" --root "$(VISUAL_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

visual-model-download-plan:
> @ruby scripts/soul-visual-runtime plan --action download --manifest "$(VISUAL_MODEL_MANIFEST)" --root "$(VISUAL_ROOT)"

visual-model-download:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run visual-model-download-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "DOWNLOAD_VISUAL_VULKAN_MODELS" || { echo "Exact confirmation DOWNLOAD_VISUAL_VULKAN_MODELS is required."; exit 2; }
> @ruby scripts/soul-visual-runtime download --manifest "$(VISUAL_MODEL_MANIFEST)" --root "$(VISUAL_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

visual-motion-check:
> @ruby scripts/soul-visual-motion-runtime check --manifest "$(VISUAL_MOTION_MANIFEST)" --root "$(VISUAL_MOTION_ROOT)"

visual-motion-runtime-plan:
> @ruby scripts/soul-visual-motion-runtime plan --action setup --manifest "$(VISUAL_MOTION_MANIFEST)" --root "$(VISUAL_MOTION_ROOT)"

visual-motion-runtime-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run visual-motion-runtime-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_VISUAL_MOTION_VULKAN_RUNTIME" || { echo "Exact confirmation INSTALL_VISUAL_MOTION_VULKAN_RUNTIME is required."; exit 2; }
> @ruby scripts/soul-visual-motion-runtime setup --manifest "$(VISUAL_MOTION_MANIFEST)" --root "$(VISUAL_MOTION_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

visual-motion-model-download-plan:
> @ruby scripts/soul-visual-motion-runtime plan --action download --manifest "$(VISUAL_MOTION_MANIFEST)" --root "$(VISUAL_MOTION_ROOT)"

visual-motion-model-download:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run visual-motion-model-download-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "DOWNLOAD_VISUAL_MOTION_MODELS" || { echo "Exact confirmation DOWNLOAD_VISUAL_MOTION_MODELS is required."; exit 2; }
> @ruby scripts/soul-visual-motion-runtime download --manifest "$(VISUAL_MOTION_MANIFEST)" --root "$(VISUAL_MOTION_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

visual-motion-pilot-plan:
> @test -n "$(VISUAL_MOTION_INPUT)" || { echo "VISUAL_MOTION_INPUT=/path/request.json is required."; exit 2; }
> @ruby scripts/soul-visual-motion-runtime plan --action run --request "$(VISUAL_MOTION_INPUT)" --manifest "$(VISUAL_MOTION_MANIFEST)" --root "$(VISUAL_MOTION_ROOT)"

visual-motion-pilot-run:
> @test -n "$(VISUAL_MOTION_INPUT)" -a -n "$(EXPECTED_DIGEST)" || { echo "VISUAL_MOTION_INPUT and EXPECTED_DIGEST are required."; exit 2; }
> @test "$(CONFIRM)" = "RUN_VISUAL_MOTION_PILOT" || { echo "Exact confirmation RUN_VISUAL_MOTION_PILOT is required."; exit 2; }
> @ruby scripts/soul-visual-motion-runtime run --request "$(VISUAL_MOTION_INPUT)" --manifest "$(VISUAL_MOTION_MANIFEST)" --root "$(VISUAL_MOTION_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

verify-visual-motion-qualification:
> @ruby scripts/verify-visual-motion-qualification.rb

visual-native-check:
> @ruby scripts/soul-visual-motion-runtime check --manifest "$(VISUAL_NATIVE_MANIFEST)" --root "$(VISUAL_NATIVE_ROOT)"

visual-native-runtime-plan:
> @ruby scripts/soul-visual-motion-runtime plan --action setup --manifest "$(VISUAL_NATIVE_MANIFEST)" --root "$(VISUAL_NATIVE_ROOT)"

visual-native-runtime-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run visual-native-runtime-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_VISUAL_MOTION_VULKAN_RUNTIME" || { echo "Exact confirmation INSTALL_VISUAL_MOTION_VULKAN_RUNTIME is required."; exit 2; }
> @ruby scripts/soul-visual-motion-runtime setup --manifest "$(VISUAL_NATIVE_MANIFEST)" --root "$(VISUAL_NATIVE_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

visual-native-model-download-plan:
> @ruby scripts/soul-visual-motion-runtime plan --action download --manifest "$(VISUAL_NATIVE_MANIFEST)" --root "$(VISUAL_NATIVE_ROOT)"

visual-native-model-download:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run visual-native-model-download-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "DOWNLOAD_VISUAL_MOTION_MODELS" || { echo "Exact confirmation DOWNLOAD_VISUAL_MOTION_MODELS is required."; exit 2; }
> @ruby scripts/soul-visual-motion-runtime download --manifest "$(VISUAL_NATIVE_MANIFEST)" --root "$(VISUAL_NATIVE_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

verify-visual-native-video:
> @ruby scripts/verify-visual-studio-native-video.rb

verify-music-publication-package:
> @ruby scripts/verify-music-publication-package.rb

music-transcription-plan:
> @ruby scripts/soul-music-transcription plan --manifest "$(MUSIC_TRANSCRIPTION_MANIFEST)" --root "$(MUSIC_ROOT)" --model "$(MUSIC_TRANSCRIPTION_MODEL)"

music-transcription-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-transcription-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_MUSIC_TRANSCRIPTION" || { echo "Exact confirmation INSTALL_SOUL_MUSIC_TRANSCRIPTION is required."; exit 2; }
> @ruby scripts/soul-music-transcription install --manifest "$(MUSIC_TRANSCRIPTION_MANIFEST)" --root "$(MUSIC_ROOT)" --model "$(MUSIC_TRANSCRIPTION_MODEL)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

music-reference-tooling-check:
> @ruby scripts/soul-music-reference-tooling check --root "$(PROJECT_ROOT)" --python "$(MUSIC_REFERENCE_PYTHON)" --yt-dlp-version "$(MUSIC_REFERENCE_YTDLP_VERSION)" --essentia-version "$(MUSIC_REFERENCE_ESSENTIA_VERSION)"

music-reference-tooling-plan:
> @ruby scripts/soul-music-reference-tooling plan --root "$(PROJECT_ROOT)" --python "$(MUSIC_REFERENCE_PYTHON)" --yt-dlp-version "$(MUSIC_REFERENCE_YTDLP_VERSION)" --essentia-version "$(MUSIC_REFERENCE_ESSENTIA_VERSION)"

music-reference-tooling-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-reference-tooling-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_MUSIC_REFERENCE_TOOLS" || { echo "Exact confirmation INSTALL_MUSIC_REFERENCE_TOOLS is required."; exit 2; }
> @ruby scripts/soul-music-reference-tooling install --root "$(PROJECT_ROOT)" --python "$(MUSIC_REFERENCE_PYTHON)" --yt-dlp-version "$(MUSIC_REFERENCE_YTDLP_VERSION)" --essentia-version "$(MUSIC_REFERENCE_ESSENTIA_VERSION)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

music-reference-enrichment-check:
> @ruby scripts/soul-music-reference-enrichment-tooling check --root "$(PROJECT_ROOT)" --manifest "$(MUSIC_REFERENCE_ENRICHMENT_MANIFEST)"

music-reference-enrichment-plan:
> @ruby scripts/soul-music-reference-enrichment-tooling plan --root "$(PROJECT_ROOT)" --manifest "$(MUSIC_REFERENCE_ENRICHMENT_MANIFEST)"

music-reference-enrichment-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-reference-enrichment-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_MUSIC_REFERENCE_ENRICHMENT" || { echo "Exact confirmation INSTALL_MUSIC_REFERENCE_ENRICHMENT is required."; exit 2; }
> @ruby scripts/soul-music-reference-enrichment-tooling install --root "$(PROJECT_ROOT)" --manifest "$(MUSIC_REFERENCE_ENRICHMENT_MANIFEST)" $(if $(strip $(MUSIC_REFERENCE_MODEL_CACHE)),--model-cache "$(MUSIC_REFERENCE_MODEL_CACHE)",) --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

music-projects:
> @ruby scripts/soul-music-studio projects list --music-root "$(MUSIC_ROOT)" --manifest "$(MUSIC_MODEL_MANIFEST)"

music-resources:
> @ruby scripts/soul-music-studio resources inspect --music-root "$(MUSIC_ROOT)" --manifest "$(MUSIC_MODEL_MANIFEST)"

music-project-create:
> @test -n "$(MUSIC_INPUT)" || { echo "MUSIC_INPUT=/path/to/project.json is required."; exit 2; }
> @ruby scripts/soul-music-studio projects create --input "$(MUSIC_INPUT)" --music-root "$(MUSIC_ROOT)" --manifest "$(MUSIC_MODEL_MANIFEST)"

music-project-inspect:
> @test -n "$(MUSIC_PROJECT_ID)" || { echo "MUSIC_PROJECT_ID is required."; exit 2; }
> @ruby scripts/soul-music-studio projects inspect --project-id "$(MUSIC_PROJECT_ID)" --music-root "$(MUSIC_ROOT)" --manifest "$(MUSIC_MODEL_MANIFEST)"

music-generate-preview:
> @test -n "$(MUSIC_PROJECT_ID)" || { echo "MUSIC_PROJECT_ID is required."; exit 2; }
> @ruby scripts/soul-music-studio generate preview --project-id "$(MUSIC_PROJECT_ID)" --music-root "$(MUSIC_ROOT)" --manifest "$(MUSIC_MODEL_MANIFEST)"

music-generate-execute:
> @test -n "$(MUSIC_PROJECT_ID)" -a -n "$(MUSIC_CANDIDATE_ID)" -a -n "$(EXPECTED_DIGEST)" || { echo "MUSIC_PROJECT_ID, MUSIC_CANDIDATE_ID, and EXPECTED_DIGEST are required."; exit 2; }
> @test "$(CONFIRM)" = "START_MUSIC_GENERATION" || { echo "Exact confirmation START_MUSIC_GENERATION is required."; exit 2; }
> @ruby scripts/soul-music-studio generate execute --project-id "$(MUSIC_PROJECT_ID)" --candidate-id "$(MUSIC_CANDIDATE_ID)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)" --music-root "$(MUSIC_ROOT)" --manifest "$(MUSIC_MODEL_MANIFEST)"

music-cancel-preview:
> @test -n "$(MUSIC_CANDIDATE_ID)" || { echo "MUSIC_CANDIDATE_ID is required."; exit 2; }
> @ruby scripts/soul-music-studio cancel preview --candidate-id "$(MUSIC_CANDIDATE_ID)" --music-root "$(MUSIC_ROOT)" --manifest "$(MUSIC_MODEL_MANIFEST)"

music-cancel-execute:
> @test -n "$(MUSIC_CANDIDATE_ID)" -a -n "$(EXPECTED_DIGEST)" || { echo "MUSIC_CANDIDATE_ID and EXPECTED_DIGEST are required."; exit 2; }
> @test "$(CONFIRM)" = "CANCEL_MUSIC_GENERATION" || { echo "Exact confirmation CANCEL_MUSIC_GENERATION is required."; exit 2; }
> @ruby scripts/soul-music-studio cancel execute --candidate-id "$(MUSIC_CANDIDATE_ID)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)" --music-root "$(MUSIC_ROOT)" --manifest "$(MUSIC_MODEL_MANIFEST)"

verify-music-a2:
> @ruby scripts/verify-music-studio-a2.rb

test-runtime: chmod-scripts
> @scripts/soul-runtime-test.sh

test-fast: chmod-scripts
> @scripts/soul-runtime-test.sh --fast

test-think: chmod-scripts
> @scripts/soul-runtime-test.sh --think

test-soul:
> @ruby bin/soul doctor
> @ruby bin/soul skills
> @ruby bin/soul skill system.status

doctor:
> @ruby bin/soul doctor

env-show: chmod-scripts
> @scripts/soul-env-show.sh

download-model: chmod-scripts
> @scripts/soul-setup-llamacpp.sh --download-only

start-llamacpp: chmod-scripts
> @scripts/soul-start-llamacpp.sh

foreground-llamacpp: start-llamacpp

dashboard:
> @ruby bin/soul dashboard

dashboard-reset-admin:
> @ruby bin/soul dashboard --reset-admin-password

dashboard-service-plan:
> @test -n "$(LAN_HOST)" || { echo "LAN_HOST is required; use: make $@ LAN_HOST=<assigned-ip>"; exit 2; }
> @scripts/soul-dashboard-service plan --lan-host "$(LAN_HOST)" --https-port "$(DASHBOARD_HTTPS_PORT)"

dashboard-service-install:
> @test -n "$(LAN_HOST)" || { echo "LAN_HOST is required; run dashboard-service-plan first."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_LAN_SERVICES" || { echo "Review the plan, then set CONFIRM=INSTALL_SOUL_LAN_SERVICES."; exit 2; }
> @scripts/soul-dashboard-service install --lan-host "$(LAN_HOST)" --https-port "$(DASHBOARD_HTTPS_PORT)" --confirmation "$(CONFIRM)"

dashboard-service-status:
> @scripts/soul-dashboard-service status

dashboard-service-logs:
> @journalctl --user -u soul-dashboard.service -u soul-dashboard-proxy.service --no-pager

dashboard-service-uninstall:
> @test "$(CONFIRM)" = "REMOVE_SOUL_LAN_SERVICES" || { echo "Set CONFIRM=REMOVE_SOUL_LAN_SERVICES to remove the two services."; exit 2; }
> @scripts/soul-dashboard-service uninstall --confirmation "$(CONFIRM)"

verify-web-knowledge:
> @ruby scripts/verify-responsive-chat-and-web-research.rb

verify-model-runtime-controls:
> @ruby scripts/verify-model-runtime-portability.rb
> @ruby scripts/verify-model-runtime-profile-switching.rb
> @ruby scripts/verify-core-orchestration.rb
> @ruby scripts/verify-model-runtime-profile-deployment.rb
> @ruby scripts/verify-ollama-model-runtime-deployment.rb
> @ruby scripts/verify-model-runtime-selected-startup.rb
> @ruby scripts/verify-model-runtime-identity-2e.rb

verify-character-identity:
> @ruby scripts/verify-character-identity-palette.rb

model-runtime-amd-plan:
> @test -n "$(AMD_SERVER)" -a -n "$(AMD_MODEL)" -a -n "$(AMD_SERVER_SHA256)" -a -n "$(AMD_MODEL_SHA256)" -a -n "$(AMD_MODEL_ALIAS)" || { echo "AMD_SERVER, AMD_MODEL, AMD_SERVER_SHA256, AMD_MODEL_SHA256, and AMD_MODEL_ALIAS are required."; exit 2; }
> @ruby scripts/soul-model-runtime-profile plan --server "$(AMD_SERVER)" --model "$(AMD_MODEL)" --server-sha256 "$(AMD_SERVER_SHA256)" --model-sha256 "$(AMD_MODEL_SHA256)" --model-alias "$(AMD_MODEL_ALIAS)" --port "$(AMD_PORT)"

model-runtime-amd-install:
> @test "$(CONFIRM)" = "INSTALL_INACTIVE_AMD_MODEL_UNIT" || { echo "Run model-runtime-amd-plan first, then set CONFIRM=INSTALL_INACTIVE_AMD_MODEL_UNIT."; exit 2; }
> @ruby scripts/soul-model-runtime-profile install --server "$(AMD_SERVER)" --model "$(AMD_MODEL)" --server-sha256 "$(AMD_SERVER_SHA256)" --model-sha256 "$(AMD_MODEL_SHA256)" --model-alias "$(AMD_MODEL_ALIAS)" --port "$(AMD_PORT)" --confirmation "$(CONFIRM)"

model-runtime-amd-status:
> @ruby scripts/soul-model-runtime-profile status

model-runtime-amd-uninstall:
> @test "$(CONFIRM)" = "REMOVE_INACTIVE_AMD_MODEL_UNIT" || { echo "Set CONFIRM=REMOVE_INACTIVE_AMD_MODEL_UNIT; active units are never stopped implicitly."; exit 2; }
> @ruby scripts/soul-model-runtime-profile uninstall --confirmation "$(CONFIRM)"

model-runtime-gemma-plan:
> @test -n "$(OLLAMA_SHA256)" -a -n "$(GEMMA_MODEL_DIGEST)" || { echo "OLLAMA_SHA256 and GEMMA_MODEL_DIGEST are required."; exit 2; }
> @ruby scripts/soul-model-runtime-gemma plan --ollama-sha256 "$(OLLAMA_SHA256)" --source-model "$(GEMMA_SOURCE_MODEL)" --api-model "$(GEMMA_API_MODEL)" --model-digest "$(GEMMA_MODEL_DIGEST)" --port "$(GEMMA_PORT)"

model-runtime-gemma-install:
> @test "$(CONFIRM)" = "INSTALL_INACTIVE_GEMMA_OLLAMA_UNIT" || { echo "Run model-runtime-gemma-plan first, then set CONFIRM=INSTALL_INACTIVE_GEMMA_OLLAMA_UNIT."; exit 2; }
> @ruby scripts/soul-model-runtime-gemma install --ollama-sha256 "$(OLLAMA_SHA256)" --source-model "$(GEMMA_SOURCE_MODEL)" --api-model "$(GEMMA_API_MODEL)" --model-digest "$(GEMMA_MODEL_DIGEST)" --port "$(GEMMA_PORT)" --confirmation "$(CONFIRM)"

model-runtime-gemma-status:
> @ruby scripts/soul-model-runtime-gemma status

model-runtime-gemma-uninstall:
> @test "$(CONFIRM)" = "REMOVE_INACTIVE_GEMMA_OLLAMA_UNIT" || { echo "Set CONFIRM=REMOVE_INACTIVE_GEMMA_OLLAMA_UNIT; active units are never stopped implicitly."; exit 2; }
> @ruby scripts/soul-model-runtime-gemma uninstall --confirmation "$(CONFIRM)"

model-runtime-startup-plan:
> @ruby scripts/soul-model-runtime-startup plan

model-runtime-startup-install:
> @test "$(CONFIRM)" = "INSTALL_SELECTED_MODEL_STARTUP" || { echo "Run model-runtime-startup-plan first, then set CONFIRM=INSTALL_SELECTED_MODEL_STARTUP."; exit 2; }
> @ruby scripts/soul-model-runtime-startup install --confirmation "$(CONFIRM)"

model-runtime-startup-status:
> @ruby scripts/soul-model-runtime-startup status

model-runtime-startup-reconcile:
> @ruby scripts/soul-model-runtime-start-selected --root "$(PROJECT_ROOT)"

model-runtime-startup-uninstall:
> @test "$(CONFIRM)" = "REMOVE_SELECTED_MODEL_STARTUP" || { echo "Set CONFIRM=REMOVE_SELECTED_MODEL_STARTUP to restore legacy NVIDIA startup."; exit 2; }
> @ruby scripts/soul-model-runtime-startup uninstall --confirmation "$(CONFIRM)"

model-runtime-identity-plan:
> @ruby scripts/soul-model-runtime-identity plan --root "$(PROJECT_ROOT)"

model-runtime-identity-execute:
> @test -n "$(ALIAS_DIGEST)" || { echo "Run model-runtime-identity-plan first, then provide ALIAS_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "MIGRATE_MODEL_ALIAS_TO_SOUL_LOCAL_CHAT" || { echo "Exact confirmation MIGRATE_MODEL_ALIAS_TO_SOUL_LOCAL_CHAT is required."; exit 2; }
> @ruby scripts/soul-model-runtime-identity execute --root "$(PROJECT_ROOT)" --expected-digest "$(ALIAS_DIGEST)" --confirmation "$(CONFIRM)"

private-memory-plan:
> @ruby scripts/soul-private-memory-migration preview

private-memory-execute:
> @test -n "$(MEMORY_DIGEST)" || { echo "Run private-memory-plan first, then provide MEMORY_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "COPY_PRIVATE_MEMORY_STATE" || { echo "Exact confirmation COPY_PRIVATE_MEMORY_STATE is required."; exit 2; }
> @ruby scripts/soul-private-memory-migration execute --expected-digest "$(MEMORY_DIGEST)" --confirmation "$(CONFIRM)"

verify-private-memory:
> @ruby scripts/verify-private-memory-separation.rb

clean-runtime:
> @rm -rf run tmp
> @echo "Removed local runtime directories: run tmp"

verify-music-studio-a3:
> @ruby scripts/verify-music-studio-a3.rb

verify-music-vocal-analysis:
> @ruby scripts/verify-music-studio-a3-vocal-analysis.rb

verify-music-references:
> @ruby scripts/verify-music-reference-library-a5.rb

verify-music-reference-analysis:
> @ruby scripts/verify-music-reference-analysis-a5.rb

verify-music-reference-synthesis:
> @ruby scripts/verify-music-reference-synthesis-a5.rb

verify-music-lite-edit:
> @ruby scripts/verify-music-lite-edit.rb
