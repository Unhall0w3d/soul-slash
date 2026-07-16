.RECIPEPREFIX := >
SHELL := /usr/bin/env bash

# Soul/ public runtime Makefile
#
# Generic public dispatcher. Local runtime values belong in .env.

PROJECT_ROOT := $(CURDIR)
ENV_FILE ?= $(PROJECT_ROOT)/.env
LAN_HOST ?=
DASHBOARD_HTTPS_PORT ?= 8443
CONFIRM ?=
AMD_SERVER ?=
AMD_MODEL ?=
AMD_SERVER_SHA256 ?=
AMD_MODEL_SHA256 ?=
AMD_MODEL_ALIAS ?=
AMD_PORT ?=8082

.PHONY: help check setup setup-llamacpp setup-ollama detect test-runtime test-fast test-think test-soul doctor env-show download-model start-llamacpp foreground-llamacpp dashboard dashboard-reset-admin dashboard-service-plan dashboard-service-install dashboard-service-status dashboard-service-logs dashboard-service-uninstall verify-model-runtime-controls model-runtime-amd-plan model-runtime-amd-install model-runtime-amd-status model-runtime-amd-uninstall model-runtime-startup-plan model-runtime-startup-install model-runtime-startup-status model-runtime-startup-uninstall model-runtime-startup-reconcile clean-runtime chmod-scripts fix-mtimes

help:
> @echo "Soul/ public setup Makefile"
> @echo
> @echo "Common targets:"
> @echo "  make check             Check required/recommended local tools only"
> @echo "  make detect            Detect runtime binaries, endpoints, .env, and local models"
> @echo "  make setup             Detect providers and guide setup"
> @echo "  make setup-llamacpp    Configure llama.cpp server provider"
> @echo "  make setup-ollama      Configure Ollama provider"
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
> @echo "  make verify-model-runtime-controls  Test leases and preview-gated model controls"
> @echo "  make model-runtime-amd-plan AMD_SERVER=... AMD_MODEL=... AMD_SERVER_SHA256=... AMD_MODEL_SHA256=... AMD_MODEL_ALIAS=..."
> @echo "  make model-runtime-amd-install ... CONFIRM=INSTALL_INACTIVE_AMD_MODEL_UNIT"
> @echo "  make model-runtime-amd-status"
> @echo "  make model-runtime-amd-uninstall CONFIRM=REMOVE_INACTIVE_AMD_MODEL_UNIT"
> @echo "  make model-runtime-startup-plan"
> @echo "  make model-runtime-startup-install CONFIRM=INSTALL_SELECTED_MODEL_STARTUP"
> @echo "  make model-runtime-startup-status"
> @echo "  make model-runtime-startup-reconcile  Verify/start the selected profile once"
> @echo "  make model-runtime-startup-uninstall CONFIRM=REMOVE_SELECTED_MODEL_STARTUP"
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
> @scripts/soul-setup-llamacpp.sh

setup-ollama: chmod-scripts
> @scripts/soul-setup-ollama.sh

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

verify-model-runtime-controls:
> @ruby scripts/verify-model-runtime-portability.rb
> @ruby scripts/verify-model-runtime-profile-switching.rb
> @ruby scripts/verify-model-runtime-profile-deployment.rb
> @ruby scripts/verify-model-runtime-selected-startup.rb

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

clean-runtime:
> @rm -rf run tmp
> @echo "Removed local runtime directories: run tmp"
