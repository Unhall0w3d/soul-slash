.RECIPEPREFIX := >
SHELL := /usr/bin/env bash

# Soul/ public runtime Makefile
#
# Generic public dispatcher. Local runtime values belong in .env.

PROJECT_ROOT := $(CURDIR)
ENV_FILE ?= $(PROJECT_ROOT)/.env

.PHONY: help check setup setup-llamacpp setup-ollama detect test-runtime test-fast test-think test-soul doctor env-show download-model start-llamacpp foreground-llamacpp clean-runtime chmod-scripts fix-mtimes

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

clean-runtime:
> @rm -rf run tmp
> @echo "Removed local runtime directories: run tmp"
