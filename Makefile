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
VOICE_TRANSCRIPTION_ROOT ?= $(MUSIC_ROOT)
VOICE_TRANSCRIPTION_MANIFEST ?= $(MUSIC_TRANSCRIPTION_MANIFEST)
VOICE_TRANSCRIPTION_MODEL ?= $(MUSIC_TRANSCRIPTION_MODEL)
VOICE_SYNTHESIS_ROOT ?= $(HOME)/.local/share/soul/voice/runtime
VOICE_SYNTHESIS_MANIFEST ?= $(PROJECT_ROOT)/config/voice_synthesis_models.json
VOICE_SYNTHESIS_REQUIREMENTS ?= $(PROJECT_ROOT)/config/voice_synthesis_requirements.txt
VOICE_SYNTHESIS_AUDITION_DIR ?= /tmp/soul-voice-audition
VOICE_EXPRESSIVE_ROOT ?= $(HOME)/.local/share/soul/voice/expressive
VOICE_EXPRESSIVE_MANIFEST ?= $(PROJECT_ROOT)/config/voice_expressive_models.json
VOICE_EXPRESSIVE_REQUIREMENTS ?= $(PROJECT_ROOT)/config/voice_expressive_requirements.txt
VOICE_PRESENCE_ROOT ?= $(HOME)/.local/share/soul/voice/presence
VOICE_PRESENCE_MANIFEST ?= $(PROJECT_ROOT)/config/voice_presence_models.json
VOICE_PRESENCE_REQUIREMENTS ?= $(PROJECT_ROOT)/config/voice_presence_requirements.txt
VOICE_PRESENCE_SOURCE ?= effect_output.soul-rnnoise
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
KNOWLEDGE_REFLECTION_INPUT ?=
BACKUP_HOME ?= $(HOME)
FLEET_SUBNET ?=

.PHONY: help defaults-show supported-stack-check check setup setup-llamacpp setup-ollama setup-music music-check music-pilot-plan music-model-download music-pilot-run music-vulkan-check music-vulkan-setup-plan music-vulkan-setup music-vulkan-download-plan music-vulkan-download music-vulkan-run-plan music-vulkan-run verify-music-core-vulkan visual-check visual-runtime-plan visual-runtime-install visual-model-download-plan visual-model-download visual-motion-check visual-motion-runtime-plan visual-motion-runtime-install visual-motion-model-download-plan visual-motion-model-download visual-motion-pilot-plan visual-motion-pilot-run visual-native-check visual-native-runtime-plan visual-native-runtime-install visual-native-model-download-plan visual-native-model-download verify-visual-motion-qualification verify-visual-native-video music-transcription-plan music-transcription-install voice-transcription-check voice-transcription-plan voice-transcription-install verify-voice-transcription voice-synthesis-check voice-synthesis-plan voice-synthesis-install voice-synthesis-audition verify-voice-synthesis notification-audio-build verify-notification-cues verify-project-timeline verify-chat-progress-summaries backup-config-plan backup-configure verify-backup-administration music-reference-tooling-check music-reference-tooling-plan music-reference-tooling-install music-reference-enrichment-check music-reference-enrichment-plan music-reference-enrichment-install music-projects music-resources music-project-create music-project-inspect music-generate-preview music-generate-execute music-cancel-preview music-cancel-execute verify-music-a2 verify-music-vocal-analysis verify-music-references verify-music-reference-analysis verify-music-reference-synthesis verify-music-lite-edit verify-music-publication-package verify-youtube-authenticated-upload verify-youtube-description-sync verify-character-identity knowledge-vault-status knowledge-vault-search knowledge-vault-init-preview knowledge-vault-init knowledge-vault-memory-export-preview knowledge-vault-memory-export knowledge-vault-memory-import-preview knowledge-vault-memory-import knowledge-vault-reflection-preview knowledge-vault-reflection-execute verify-knowledge-vault verify-knowledge-reflection local-search local-search-core-eval verify-local-search detect test-runtime test-fast test-think test-soul doctor env-show download-model start-llamacpp foreground-llamacpp dashboard dashboard-reset-admin dashboard-service-plan dashboard-service-install dashboard-service-status dashboard-service-logs dashboard-service-uninstall verify-web-knowledge verify-model-runtime-controls model-runtime-amd-plan model-runtime-amd-install model-runtime-amd-status model-runtime-amd-uninstall model-runtime-gemma-plan model-runtime-gemma-install model-runtime-gemma-status model-runtime-gemma-uninstall model-runtime-startup-plan model-runtime-startup-install model-runtime-startup-status model-runtime-startup-uninstall model-runtime-startup-reconcile model-runtime-identity-plan model-runtime-identity-execute private-memory-plan private-memory-execute verify-private-memory clean-runtime chmod-scripts fix-mtimes verify-maintenance-foreground-execution verify-maintenance-desktop-handoff maintenance-handoff-check maintenance-handoff-plan maintenance-handoff-install
.PHONY: verify-maintenance-reboot-restore verify-maintenance-passwordless-authority maintenance-authority-plan maintenance-authority-status maintenance-authority-install maintenance-authority-uninstall verify-maintenance-fleet-status verify-maintenance-device-control verify-maintenance-fleet-discovery verify-maintenance-fleet-dhcp-identity verify-apple-mobile-fleet-inventory apple-mobile-inventory-check verify-crucible-fedora-status verify-crucible-maintenance-control crucible-maintenance-authority-plan crucible-maintenance-authority-status crucible-maintenance-authority-install fleet-discovery-check fleet-discovery-scan maintenance-resume-plan maintenance-resume-install maintenance-resume-status maintenance-resume-uninstall fleet-status-schedule-plan fleet-status-schedule-install fleet-status-schedule-status fleet-status-schedule-uninstall

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
> @echo "  make voice-transcription-check  Verify bounded Chat push-to-talk dependencies"
> @echo "  make voice-transcription-plan  Preview the shared pinned CPU transcription install"
> @echo "  make voice-transcription-install EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_MUSIC_TRANSCRIPTION"
> @echo "  make voice-synthesis-check  Verify bounded local Chat speech dependencies"
> @echo "  make voice-synthesis-plan  Preview the pinned Supertonic 3 install"
> @echo "  make voice-synthesis-install EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_VOICE_SYNTHESIS"
> @echo "  make voice-synthesis-audition  Render F1/F3/F5 and M1/M3/M5 comparison clips"
> @echo "  make voice-expressive-check  Verify the bounded Chatterbox expressive runtime"
> @echo "  make voice-expressive-plan  Preview the pinned expressive runtime install"
> @echo "  make voice-expressive-install EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_EXPRESSIVE_VOICE"
> @echo "  make voice-noise-filter-plan  Preview a system-wide RNNoise virtual microphone"
> @echo "  make voice-noise-filter-install EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_RNNOISE_FILTER"
> @echo "  make voice-presence-plan  Preview the local Hey Soul wake runtime and app entry"
> @echo "  make voice-presence-install EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_VOICE_PRESENCE"
> @echo "  make voice-presence-launch  Open visible persistent voice (close window to stop)"
> @echo "  make verify-notification-cues  Verify static cues and Presence-aware spoken notices"
> @echo "  make verify-project-timeline  Verify the shared Dashboard/Chat implementation ledger"
> @echo "  make verify-chat-progress-summaries  Verify durable bounded Chat progress summaries"
> @echo "  make backup-config-plan  Preview portable owner backup manifests"
> @echo "  make backup-configure EXPECTED_DIGEST=... CONFIRM=CONFIGURE_SOUL_BACKUP_MANIFESTS"
> @echo "  make verify-backup-administration  Verify capture, retention, and staged restore gates"
> @echo "  make verify-crucible-backup-replication  Verify bounded off-device initialize/copy/check gates"
> @echo "  make knowledge-vault-status  Inspect the optional external Markdown vault"
> @echo "  make knowledge-vault-init-preview  Preview the portable starter structure"
> @echo "  make knowledge-vault-init EXPECTED_DIGEST=... CONFIRM=INITIALIZE_KNOWLEDGE_VAULT"
> @echo "  make knowledge-vault-search KNOWLEDGE_QUERY='local models'"
> @echo "  make local-search LOCAL_SEARCH_QUERY='backrooms prompts'"
> @echo "  make local-search-core-eval LOCAL_SEARCH_CORE=daily  Test only the active Core"
> @echo "  make knowledge-vault-reflection-preview KNOWLEDGE_REFLECTION_INPUT=/path/candidate.json"
> @echo "  make knowledge-vault-reflection-execute KNOWLEDGE_REFLECTION_INPUT=... EXPECTED_DIGEST=... CONFIRM=WRITE_KNOWLEDGE_VAULT_NOTE"
> @echo "  make verify-knowledge-reflection  Test explicit conversation-to-vault proposals and exact writes"
> @echo "  make music-reference-enrichment-plan  Preview pinned rich reference-analysis models"
> @echo "  make music-reference-enrichment-install EXPECTED_DIGEST=... CONFIRM=INSTALL_MUSIC_REFERENCE_ENRICHMENT"
> @echo "  make verify-music-reference-synthesis  Test reference synthesis retry approval and fusion gates"
> @echo "  make verify-music-lite-edit  Test immutable-source start/end trimming and receipts"
> @echo "  make verify-music-publication-package  Test local YouTube upload packages"
> @echo "  make verify-youtube-authenticated-upload  Test OAuth and exact YouTube upload gates without Google"
> @echo "  make verify-youtube-description-sync  Test exact NOC Thoughts description-link gates without Google"
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
> @echo "  make maintenance-handoff-check"
> @echo "  make maintenance-handoff-plan"
> @echo "  make maintenance-handoff-install EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_MAINTENANCE_HANDOFF"
> @echo "  make maintenance-resume-plan"
> @echo "  make maintenance-resume-install CONFIRM=INSTALL_SOUL_MAINTENANCE_RESUME"
> @echo "  make maintenance-authority-plan"
> @echo "  make maintenance-authority-install EXPECTED_DIGEST=... CONFIRM=INSTALL_SOUL_MAINTENANCE_AUTHORITY"
> @echo "  make maintenance-resume-status"
> @echo "  make verify-maintenance-desktop-handoff"
> @echo "  make verify-maintenance-fleet-status"
> @echo "  make verify-apple-mobile-fleet-inventory"
> @echo "  make apple-mobile-inventory-check  Check optional usbmuxd/libimobiledevice support"
> @echo "  make verify-crucible-fedora-status"
> @echo "  make verify-crucible-maintenance-control"
> @echo "  make crucible-maintenance-authority-plan"
> @echo "  make crucible-maintenance-authority-status"
> @echo "  make crucible-maintenance-authority-install EXPECTED_DIGEST=... CONFIRM=INSTALL_CRUCIBLE_MAINTENANCE_AUTHORITY"
> @echo "  make verify-maintenance-fleet-dhcp-identity"
> @echo "  make verify-maintenance-device-control"
> @echo "  make fleet-discovery-check  Verify optional bounded subnet discovery prerequisites"
> @echo "  make fleet-discovery-scan FLEET_SUBNET=192.168.1.0/24  Run one non-persisted private-LAN scan"
> @echo "  make fleet-status-schedule-plan"
> @echo "  make fleet-status-schedule-install CONFIRM=INSTALL_SOUL_FLEET_STATUS_TIMER"
> @echo "  make fleet-status-schedule-status"
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

verify-youtube-authenticated-upload:
> @ruby scripts/verify-youtube-authenticated-upload-a0.rb

verify-youtube-description-sync:
> @ruby scripts/verify-youtube-description-sync-a0.rb

music-transcription-plan:
> @ruby scripts/soul-music-transcription plan --manifest "$(MUSIC_TRANSCRIPTION_MANIFEST)" --root "$(MUSIC_ROOT)" --model "$(MUSIC_TRANSCRIPTION_MODEL)"

music-transcription-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run music-transcription-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_MUSIC_TRANSCRIPTION" || { echo "Exact confirmation INSTALL_SOUL_MUSIC_TRANSCRIPTION is required."; exit 2; }
> @ruby scripts/soul-music-transcription install --manifest "$(MUSIC_TRANSCRIPTION_MANIFEST)" --root "$(MUSIC_ROOT)" --model "$(MUSIC_TRANSCRIPTION_MODEL)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

voice-transcription-check:
> @ruby scripts/soul-voice-transcription check --manifest "$(VOICE_TRANSCRIPTION_MANIFEST)" --root "$(VOICE_TRANSCRIPTION_ROOT)" --model "$(VOICE_TRANSCRIPTION_MODEL)"

voice-transcription-plan:
> @ruby scripts/soul-music-transcription plan --manifest "$(VOICE_TRANSCRIPTION_MANIFEST)" --root "$(VOICE_TRANSCRIPTION_ROOT)" --model "$(VOICE_TRANSCRIPTION_MODEL)"

voice-transcription-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run voice-transcription-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_MUSIC_TRANSCRIPTION" || { echo "Exact confirmation INSTALL_SOUL_MUSIC_TRANSCRIPTION is required."; exit 2; }
> @ruby scripts/soul-music-transcription install --manifest "$(VOICE_TRANSCRIPTION_MANIFEST)" --root "$(VOICE_TRANSCRIPTION_ROOT)" --model "$(VOICE_TRANSCRIPTION_MODEL)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

verify-voice-transcription:
> @ruby scripts/verify-voice-transcription-a0.rb

voice-synthesis-check:
> @ruby scripts/soul-voice-synthesis check --manifest "$(VOICE_SYNTHESIS_MANIFEST)" --requirements "$(VOICE_SYNTHESIS_REQUIREMENTS)" --root "$(VOICE_SYNTHESIS_ROOT)"

voice-synthesis-plan:
> @ruby scripts/soul-voice-synthesis plan --manifest "$(VOICE_SYNTHESIS_MANIFEST)" --requirements "$(VOICE_SYNTHESIS_REQUIREMENTS)" --root "$(VOICE_SYNTHESIS_ROOT)"

voice-synthesis-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run voice-synthesis-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_VOICE_SYNTHESIS" || { echo "Exact confirmation INSTALL_SOUL_VOICE_SYNTHESIS is required."; exit 2; }
> @ruby scripts/soul-voice-synthesis install --manifest "$(VOICE_SYNTHESIS_MANIFEST)" --requirements "$(VOICE_SYNTHESIS_REQUIREMENTS)" --root "$(VOICE_SYNTHESIS_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

voice-synthesis-audition:
> @ruby scripts/soul-voice-synthesis audition --manifest "$(VOICE_SYNTHESIS_MANIFEST)" --requirements "$(VOICE_SYNTHESIS_REQUIREMENTS)" --root "$(VOICE_SYNTHESIS_ROOT)" --output "$(VOICE_SYNTHESIS_AUDITION_DIR)"

verify-voice-synthesis:
> @ruby scripts/verify-voice-synthesis-a0.rb

voice-expressive-check:
> @ruby scripts/soul-voice-expressive check --manifest "$(VOICE_EXPRESSIVE_MANIFEST)" --requirements "$(VOICE_EXPRESSIVE_REQUIREMENTS)" --root "$(VOICE_EXPRESSIVE_ROOT)"

voice-expressive-plan:
> @ruby scripts/soul-voice-expressive plan --manifest "$(VOICE_EXPRESSIVE_MANIFEST)" --requirements "$(VOICE_EXPRESSIVE_REQUIREMENTS)" --root "$(VOICE_EXPRESSIVE_ROOT)"

voice-expressive-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run voice-expressive-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_EXPRESSIVE_VOICE" || { echo "Exact confirmation INSTALL_SOUL_EXPRESSIVE_VOICE is required."; exit 2; }
> @ruby scripts/soul-voice-expressive install --manifest "$(VOICE_EXPRESSIVE_MANIFEST)" --requirements "$(VOICE_EXPRESSIVE_REQUIREMENTS)" --root "$(VOICE_EXPRESSIVE_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

verify-voice-expressive:
> @ruby scripts/verify-voice-synthesis-a1-expressive.rb

voice-noise-filter-check:
> @ruby scripts/soul-voice-noise-filter check

voice-noise-filter-plan:
> @ruby scripts/soul-voice-noise-filter plan

voice-noise-filter-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run voice-noise-filter-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_RNNOISE_FILTER" || { echo "Exact confirmation INSTALL_SOUL_RNNOISE_FILTER is required."; exit 2; }
> @ruby scripts/soul-voice-noise-filter --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)" install

verify-voice-noise-filter:
> @ruby scripts/verify-voice-noise-filter-a1.rb

voice-presence-check:
> @ruby scripts/soul-voice-presence-runtime check --manifest "$(VOICE_PRESENCE_MANIFEST)" --requirements "$(VOICE_PRESENCE_REQUIREMENTS)" --root "$(VOICE_PRESENCE_ROOT)"

voice-presence-plan:
> @ruby scripts/soul-voice-presence-runtime plan --manifest "$(VOICE_PRESENCE_MANIFEST)" --requirements "$(VOICE_PRESENCE_REQUIREMENTS)" --root "$(VOICE_PRESENCE_ROOT)"

voice-presence-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run voice-presence-plan first, then provide its EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_VOICE_PRESENCE" || { echo "Exact confirmation INSTALL_SOUL_VOICE_PRESENCE is required."; exit 2; }
> @ruby scripts/soul-voice-presence-runtime install --manifest "$(VOICE_PRESENCE_MANIFEST)" --requirements "$(VOICE_PRESENCE_REQUIREMENTS)" --root "$(VOICE_PRESENCE_ROOT)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

voice-presence-launch:
> @SOUL_VOICE_PRESENCE_ROOT="$(VOICE_PRESENCE_ROOT)" SOUL_VOICE_PRESENCE_MANIFEST="$(VOICE_PRESENCE_MANIFEST)" SOUL_VOICE_PRESENCE_SOURCE="$(VOICE_PRESENCE_SOURCE)" scripts/soul-voice-presence

verify-voice-presence:
> @ruby scripts/verify-voice-presence-a2.rb
> @ruby scripts/verify-voice-presence-a3.rb

notification-audio-build:
> @ruby scripts/build-notification-audio

verify-notification-cues:
> @ruby scripts/verify-notification-cues-a1.rb

verify-project-timeline:
> @ruby scripts/verify-project-timeline-a1.rb

verify-chat-progress-summaries:
> @ruby scripts/verify-chat-progress-summaries-a1.rb

backup-config-plan:
> @ruby scripts/soul-backup-config plan --root "$(PROJECT_ROOT)" --home "$(BACKUP_HOME)"

backup-configure:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run backup-config-plan first, then provide EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "CONFIGURE_SOUL_BACKUP_MANIFESTS" || { echo "Exact confirmation CONFIGURE_SOUL_BACKUP_MANIFESTS is required."; exit 2; }
> @ruby scripts/soul-backup-config execute --root "$(PROJECT_ROOT)" --home "$(BACKUP_HOME)" --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

verify-backup-administration:
> @ruby scripts/verify-backup-administration-a2.rb

.PHONY: verify-crucible-backup-replication
verify-crucible-backup-replication:
> @ruby scripts/verify-crucible-backup-replication-a2.rb

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

knowledge-vault-status:
> @scripts/soul-knowledge-vault status

knowledge-vault-search:
> @test -n "$(KNOWLEDGE_QUERY)" || { echo "KNOWLEDGE_QUERY is required."; exit 2; }
> @scripts/soul-knowledge-vault search "$(KNOWLEDGE_QUERY)" "$(or $(KNOWLEDGE_LIMIT),10)"

knowledge-vault-init-preview:
> @scripts/soul-knowledge-vault initialize-preview

knowledge-vault-init:
> @test "$(CONFIRM)" = "INITIALIZE_KNOWLEDGE_VAULT" || { echo "Review the preview, then set CONFIRM=INITIALIZE_KNOWLEDGE_VAULT."; exit 2; }
> @test -n "$(EXPECTED_DIGEST)" || { echo "EXPECTED_DIGEST is required."; exit 2; }
> @CONFIRMATION="$(CONFIRM)" EXPECTED_DIGEST="$(EXPECTED_DIGEST)" scripts/soul-knowledge-vault initialize-execute

knowledge-vault-memory-export-preview:
> @scripts/soul-knowledge-vault memory-export-preview

knowledge-vault-memory-export:
> @test "$(CONFIRM)" = "EXPORT_APPROVED_MEMORY_TO_VAULT" || { echo "Review the preview, then set CONFIRM=EXPORT_APPROVED_MEMORY_TO_VAULT."; exit 2; }
> @test -n "$(EXPECTED_DIGEST)" || { echo "EXPECTED_DIGEST is required."; exit 2; }
> @CONFIRMATION="$(CONFIRM)" EXPECTED_DIGEST="$(EXPECTED_DIGEST)" scripts/soul-knowledge-vault memory-export-execute

knowledge-vault-memory-import-preview:
> @test -n "$(KNOWLEDGE_NOTE)" -a -n "$(KNOWLEDGE_LAYER)" || { echo "KNOWLEDGE_NOTE and KNOWLEDGE_LAYER are required."; exit 2; }
> @scripts/soul-knowledge-vault memory-import-preview "$(KNOWLEDGE_NOTE)" "$(KNOWLEDGE_LAYER)"

knowledge-vault-memory-import:
> @test "$(CONFIRM)" = "IMPORT_VAULT_NOTE_AS_MEMORY_CANDIDATE" || { echo "Review the preview, then set CONFIRM=IMPORT_VAULT_NOTE_AS_MEMORY_CANDIDATE."; exit 2; }
> @test -n "$(EXPECTED_DIGEST)" -a -n "$(KNOWLEDGE_NOTE)" -a -n "$(KNOWLEDGE_LAYER)" || { echo "EXPECTED_DIGEST, KNOWLEDGE_NOTE, and KNOWLEDGE_LAYER are required."; exit 2; }
> @CONFIRMATION="$(CONFIRM)" EXPECTED_DIGEST="$(EXPECTED_DIGEST)" scripts/soul-knowledge-vault memory-import-execute "$(KNOWLEDGE_NOTE)" "$(KNOWLEDGE_LAYER)"

knowledge-vault-reflection-preview:
> @test -n "$(KNOWLEDGE_REFLECTION_INPUT)" || { echo "KNOWLEDGE_REFLECTION_INPUT is required; start from config/knowledge_reflection.example.json."; exit 2; }
> @scripts/soul-knowledge-vault reflection-preview "$(KNOWLEDGE_REFLECTION_INPUT)"

knowledge-vault-reflection-execute:
> @test "$(CONFIRM)" = "WRITE_KNOWLEDGE_VAULT_NOTE" || { echo "Review the preview, then set CONFIRM=WRITE_KNOWLEDGE_VAULT_NOTE."; exit 2; }
> @test -n "$(EXPECTED_DIGEST)" -a -n "$(KNOWLEDGE_REFLECTION_INPUT)" || { echo "EXPECTED_DIGEST and KNOWLEDGE_REFLECTION_INPUT are required."; exit 2; }
> @CONFIRMATION="$(CONFIRM)" EXPECTED_DIGEST="$(EXPECTED_DIGEST)" scripts/soul-knowledge-vault reflection-execute "$(KNOWLEDGE_REFLECTION_INPUT)"

verify-knowledge-vault:
> @ruby scripts/verify-knowledge-vault-a0.rb

local-search:
> @test -n "$(LOCAL_SEARCH_QUERY)" || { echo "LOCAL_SEARCH_QUERY is required."; exit 2; }
> @scripts/soul-local-search "$(LOCAL_SEARCH_QUERY)" "$(or $(LOCAL_SEARCH_LIMIT),10)" $(LOCAL_SEARCH_SOURCES)

local-search-core-eval:
> @ruby scripts/run-local-search-cross-core-eval.rb "$(LOCAL_SEARCH_CORE)"

verify-local-search:
> @ruby scripts/verify-local-search-a1.rb
> @ruby scripts/verify-local-search-a2.rb

verify-knowledge-reflection:
> @ruby scripts/verify-knowledge-reflection-a2.rb

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

verify-maintenance-rehearsal:
> @ruby scripts/verify-maintenance-rehearsal-a1.rb

verify-maintenance-foreground-execution:
> @ruby scripts/verify-maintenance-foreground-execution-a2.rb

verify-maintenance-desktop-handoff:
> @ruby scripts/verify-maintenance-desktop-handoff-a2b.rb

maintenance-handoff-check:
> @ruby scripts/soul-maintenance-handoff check

maintenance-handoff-plan:
> @ruby scripts/soul-maintenance-handoff plan

maintenance-handoff-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run maintenance-handoff-plan first, then provide EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_MAINTENANCE_HANDOFF" || { echo "Exact confirmation INSTALL_SOUL_MAINTENANCE_HANDOFF is required."; exit 2; }
> @ruby scripts/soul-maintenance-handoff install --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

verify-maintenance-reboot-restore:
> @ruby scripts/verify-maintenance-reboot-restore-a3.rb

verify-maintenance-passwordless-authority:
> @ruby scripts/verify-maintenance-passwordless-authority-a4.rb

maintenance-authority-plan:
> @ruby scripts/soul-maintenance-authority plan

maintenance-authority-status:
> @ruby scripts/soul-maintenance-authority status

maintenance-authority-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run maintenance-authority-plan first, then provide EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_SOUL_MAINTENANCE_AUTHORITY" || { echo "Exact confirmation INSTALL_SOUL_MAINTENANCE_AUTHORITY is required."; exit 2; }
> @ruby scripts/soul-maintenance-authority install --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

maintenance-authority-uninstall:
> @test "$(CONFIRM)" = "REMOVE_SOUL_MAINTENANCE_AUTHORITY" || { echo "Exact confirmation REMOVE_SOUL_MAINTENANCE_AUTHORITY is required."; exit 2; }
> @ruby scripts/soul-maintenance-authority uninstall --confirmation "$(CONFIRM)"

verify-maintenance-fleet-status:
> @ruby scripts/verify-maintenance-fleet-status-b1.rb

verify-apple-mobile-fleet-inventory:
> @ruby scripts/verify-apple-mobile-fleet-inventory-a1.rb

apple-mobile-inventory-check:
> @command -v idevice_id >/dev/null || { echo "Missing idevice_id; install libimobiledevice."; exit 2; }
> @command -v ideviceinfo >/dev/null || { echo "Missing ideviceinfo; install libimobiledevice."; exit 2; }
> @if command -v systemctl >/dev/null && systemctl is-active --quiet usbmuxd; then echo "usbmuxd is active."; else echo "usbmuxd is not currently active; it may socket-activate when a phone connects."; fi
> @echo "Apple mobile wired inventory dependencies are ready."

verify-crucible-fedora-status:
> @ruby scripts/verify-crucible-fedora-status-a0.rb

verify-crucible-maintenance-control:
> @ruby scripts/verify-crucible-maintenance-control-d1.rb

crucible-maintenance-authority-plan:
> @ruby scripts/soul-crucible-maintenance-authority plan

crucible-maintenance-authority-status:
> @ruby scripts/soul-crucible-maintenance-authority status

crucible-maintenance-authority-install:
> @test -n "$(EXPECTED_DIGEST)" || { echo "Run crucible-maintenance-authority-plan first, then provide EXPECTED_DIGEST."; exit 2; }
> @test "$(CONFIRM)" = "INSTALL_CRUCIBLE_MAINTENANCE_AUTHORITY" || { echo "Exact confirmation INSTALL_CRUCIBLE_MAINTENANCE_AUTHORITY is required."; exit 2; }
> @ruby scripts/soul-crucible-maintenance-authority install --expected-digest "$(EXPECTED_DIGEST)" --confirmation "$(CONFIRM)"

verify-maintenance-device-control:
> @ruby scripts/verify-maintenance-device-control-c1.rb

verify-maintenance-fleet-discovery:
> @ruby scripts/verify-maintenance-fleet-discovery-a1.rb

verify-maintenance-fleet-dhcp-identity:
> @ruby scripts/verify-maintenance-fleet-dhcp-identity-a3.rb

fleet-discovery-check:
> @ruby scripts/soul-maintenance-fleet-discovery status

fleet-discovery-scan:
> @test -n "$(FLEET_SUBNET)" || { echo "FLEET_SUBNET is required (private IPv4 /24 through /32)"; exit 2; }
> @ruby scripts/soul-maintenance-fleet-discovery scan --subnet "$(FLEET_SUBNET)"

fleet-status-schedule-plan:
> @ruby scripts/soul-maintenance-fleet-status-schedule plan

fleet-status-schedule-install:
> @ruby scripts/soul-maintenance-fleet-status-schedule install --confirmation "$(CONFIRM)"

fleet-status-schedule-status:
> @ruby scripts/soul-maintenance-fleet-status-schedule status

fleet-status-schedule-uninstall:
> @ruby scripts/soul-maintenance-fleet-status-schedule uninstall --confirmation "$(CONFIRM)"

maintenance-resume-plan:
> @ruby scripts/soul-maintenance-resume-service plan

maintenance-resume-install:
> @test "$(CONFIRM)" = "INSTALL_SOUL_MAINTENANCE_RESUME" || { echo "Review maintenance-resume-plan, then set CONFIRM=INSTALL_SOUL_MAINTENANCE_RESUME."; exit 2; }
> @ruby scripts/soul-maintenance-resume-service install --confirmation "$(CONFIRM)"

maintenance-resume-status:
> @ruby scripts/soul-maintenance-resume-service status

maintenance-resume-uninstall:
> @test "$(CONFIRM)" = "REMOVE_SOUL_MAINTENANCE_RESUME" || { echo "Set CONFIRM=REMOVE_SOUL_MAINTENANCE_RESUME to remove the one-shot unit."; exit 2; }
> @ruby scripts/soul-maintenance-resume-service uninstall --confirmation "$(CONFIRM)"
