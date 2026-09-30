# Makefile — vendor key management + Docker build/test helpers
# Usage:
#   make                # shows help
#   make docker-build   # build runtime image
#   make docker-test    # build test stage then run bats tests in a disposable container
#   make docker-test-exec CONTAINER_NAME=terrarium  # run bats inside an existing container

# Ensure bash; fail fast and on broken pipelines for every recipe.
SHELL := /usr/bin/env bash
SHELLFLAGS := -eu -o pipefail -c

# ---------------- Configuration ----------------
# Keys management
KEYS_SCRIPT ?= docker/vendor-keys/refresh-vendor-keys.sh
# Optional: where to stash shell-style pins
ENV_FILE    ?= docker/vendor-keys/vendor-keys.env

# Docker build/test
DOCKERFILE       ?= docker/Dockerfile.terrarium
DOCKER_CONTEXT   ?= docker
IMAGE            ?= terrarium
TAG              ?= latest
# Dockerfile stage that runs tests
TEST_STAGE       ?= test
# Tag for test-stage image: $(IMAGE):$(TEST_TAG)
TEST_TAG         ?= test
# Used by docker-test-exec and as a default name
CONTAINER_NAME   ?= terrarium
# Host folder for JUnit/XML reports
TEST_REPORT_DIR  ?= test-reports
# In-container path to your bats tests
BATS_TEST_PATH   ?= /home/terrarium/tests

# Docker cache control
# Usage: make docker-build NO_CACHE=1
#        make docker-build-test NO_CACHE=1
NO_CACHE         ?= 0

# CPU count (Linux, macOS, generic fallback)
NPROC := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

# Pretty output (no color in dumb terminals)
GREEN  := \033[32m
YELLOW := \033[33m
RED    := \033[31m
BOLD   := \033[1m
RESET  := \033[0m

.DEFAULT_GOAL := help

# ---------------- Internal helpers ----------------
define assert_docker
	command -v docker >/dev/null 2>&1 || { printf "$(RED)Error: docker is not installed or not in PATH$(RESET)\n" >&2; exit 127; }
	docker info >/dev/null 2>&1 || { printf "$(RED)Error: cannot talk to docker daemon. Is it running?$(RESET)\n" >&2; exit 1; }
endef

# $(call assert_file, path)
define assert_file
	test -f "$(1)" || { printf "$(RED)Error: missing file: $(1)$(RESET)\n" >&2; exit 1; }
endef

.PHONY: help verify-keys print-keys write-keys check-keys docker-build docker-build-test docker-test docker-test-exec test sbom install-syft guardrails lint shellcheck hadolint test-helpers test-scripts docker-test-helpers check-keys-drift

# Files shellcheck lints (kept in sync with .github/workflows/lint.yaml)
SHELLCHECK_TARGETS ?= scripts/*.sh scripts/tests/fixtures/bin/* docker/vendor-keys/*.sh docker/files/bin/*
# Docker images for linters (no host install required; matches CI)
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable
HADOLINT_IMAGE   ?= hadolint/hadolint:latest

# ================== Quality gates ==================
guardrails: ## Mechanical do-not-regress + ratchet assertions on the Dockerfile
	@bash scripts/check-guardrails.sh "$(DOCKERFILE)"

check-keys-drift: ## Fail if vendor-key pins in $(ENV_FILE) drift from the Dockerfile ENV block (fingerprints only)
	@bash scripts/check-vendor-key-drift.sh "$(DOCKERFILE)" "$(ENV_FILE)"

shellcheck: ## Run shellcheck (severity=warning) over shell sources via stdin (bind-mount-free)
	@$(assert_docker)
	@printf "$(YELLOW)shellcheck: $(SHELLCHECK_TARGETS)$(RESET)\n"
	@# Pre-pull the image. The loop below captures `2>&1` so that shellcheck's own
	@# errors surface, which also captures Docker's pull progress (written to
	@# stderr). On a cold cache that non-empty output is indistinguishable from
	@# findings, so the first file checked always fails. CI runners are always cold.
	@docker image inspect $(SHELLCHECK_IMAGE) >/dev/null 2>&1 || docker pull -q $(SHELLCHECK_IMAGE) >/dev/null
	@rc=0; found=0; \
	 for f in $(SHELLCHECK_TARGETS); do \
	   [ -f "$$f" ] || continue; found=1; \
	   case "$$f" in *.md|*.env) continue;; esac; \
	   out=$$(docker run --rm -i $(SHELLCHECK_IMAGE) --severity=warning --external-sources - < "$$f" 2>&1); \
	   if [ -n "$$out" ]; then printf "$(RED)%s$(RESET)\n%s\n" "$$f" "$$out"; rc=1; \
	   else printf "ok: %s\n" "$$f"; fi; \
	 done; \
	 [ "$$found" = 1 ] || printf "$(YELLOW)no shell files to check$(RESET)\n"; \
	 exit $$rc

hadolint: ## Run hadolint on the terrarium Dockerfile via stdin (ignores sourced from .hadolint.yaml)
	@$(assert_docker)
	@printf "$(YELLOW)hadolint: $(DOCKERFILE)$(RESET)\n"
	@ign=$$(awk '/^ignored:/{f=1;next} f&&/^[[:space:]]*-[[:space:]]/{gsub(/[^A-Za-z0-9]/,"",$$2);printf "%s%s",s,$$2;s=","} f&&/^[^[:space:]-]/{f=0}' .hadolint.yaml 2>/dev/null); \
	 docker run --rm -i -e HADOLINT_IGNORE="$$ign" -e HADOLINT_FAILURE_THRESHOLD=error $(HADOLINT_IMAGE) hadolint - < "$(DOCKERFILE)"

lint: guardrails shellcheck hadolint ## Run all host-side lint gates (guardrails + shellcheck + hadolint)

# ================== Helper unit tests ==================
UNIT_TEST_DIR   ?= docker/tests/unit
# CI-script tests (scripts/*.sh). Host-only: the `helpers` stage builds from
# ./docker and cannot see scripts/, so lint.yaml runs `make test-scripts`.
SCRIPT_TEST_DIR ?= scripts/tests

define assert_bats
	command -v bats >/dev/null 2>&1 || { printf "$(RED)Error: bats not found on PATH. Install bats-core or use 'make docker-test-helpers'.$(RESET)\n" >&2; exit 127; }
endef

test-helpers: ## Run the hermetic helper AND CI-script unit suites on the host (needs bats + jq; no Docker, no network)
	@$(assert_bats)
	@printf "$(YELLOW)Running unit suites: $(UNIT_TEST_DIR) $(SCRIPT_TEST_DIR)$(RESET)\n"
	@bats "$(UNIT_TEST_DIR)" "$(SCRIPT_TEST_DIR)"

test-scripts: ## Run only the CI-script unit suite ($(SCRIPT_TEST_DIR)) on the host (needs bats + jq)
	@$(assert_bats)
	@printf "$(YELLOW)Running CI-script unit suite: $(SCRIPT_TEST_DIR)$(RESET)\n"
	@bats "$(SCRIPT_TEST_DIR)"

docker-test-helpers: ## Build the 'helpers' stage, which runs the unit suite hermetically in the image
	@$(assert_docker)
	@$(call assert_file,$(DOCKERFILE))
	@printf "$(YELLOW)Building 'helpers' stage (runs $(UNIT_TEST_DIR))...$(RESET)\n"
	@DOCKER_BUILDKIT=1 docker build \
		$(DOCKER_BUILD_OPTS) \
		--target helpers \
		-f "$(DOCKERFILE)" $(DOCKER_CONTEXT)
	@printf "$(GREEN)helpers stage green$(RESET)\n"

# ================== Meta ==================
help: ## Show this help (default)
	@printf "\n  $(BOLD)Targets$(RESET):\n"
	@grep -hE '^[a-zA-Z0-9_\/\.\-]+:.*##' $(MAKEFILE_LIST) \
	| awk 'BEGIN{FS=":.*##"} {printf "    %-22s %s\n", $$1, $$2}'
	@printf "\n  $(BOLD)Configurable vars$(RESET): IMAGE=%s TAG=%s DOCKERFILE=%s TEST_STAGE=%s TEST_REPORT_DIR=%s\n\n" \
	"$(IMAGE)" "$(TAG)" "$(DOCKERFILE)" "$(TEST_STAGE)" "$(TEST_REPORT_DIR)"

# ================== Vendor keys ==================
verify-keys: ## Re-fetch keys and show current fingerprints (+ diff vs env pins if provided)
	@$(call assert_file,$(KEYS_SCRIPT))
	@"$(KEYS_SCRIPT)" >/dev/null
	@printf "$(GREEN)OK: refresh completed$(RESET)\n"

print-keys: ## Print fresh key fingerprints (and show diff vs pins if $(ENV_FILE) exists)
	@$(call assert_file,$(KEYS_SCRIPT))
	@"$(KEYS_SCRIPT)"

write-keys: ## Write shell-style pins to $(ENV_FILE) for CI use (source it later)
	@$(call assert_file,$(KEYS_SCRIPT))
	@mkdir -p "$(dir $(ENV_FILE))"
	@"$(KEYS_SCRIPT)" print-shell-env >"$(ENV_FILE)"
	@printf "$(GREEN)Wrote $(ENV_FILE)$(RESET)\n"

check-keys: ## CI check: fail if computed fingerprints differ from pins in $(ENV_FILE)
	@$(call assert_file,$(KEYS_SCRIPT))
	@set -euo pipefail; \
	if [[ -f "$(ENV_FILE)" ]]; then \
	  set -a; source "$(ENV_FILE)"; set +a; \
	fi; \
	"$(KEYS_SCRIPT)" strict

# ================== Docker ==================
#
# Compose common build options and conditionally add --no-cache
DOCKER_BUILD_OPTS_BASE := --pull --progress=plain
# INFIAAS-11804: optional read-only GitHub token for tenv's api.github.com calls
# (60 anonymous requests/hour/IP). Passed as a BuildKit secret only when set, so
# it never becomes a build-arg or image layer. Example:
#   TENV_GITHUB_TOKEN="$(gh auth token)" make docker-build-test
ifneq ($(strip $(TENV_GITHUB_TOKEN)),)
  DOCKER_BUILD_OPTS_BASE += --secret id=tenv_github_token,env=TENV_GITHUB_TOKEN
endif
ifeq ($(NO_CACHE),1)
  DOCKER_BUILD_OPTS := $(DOCKER_BUILD_OPTS_BASE) --no-cache
else
  DOCKER_BUILD_OPTS := $(DOCKER_BUILD_OPTS_BASE)
endif

docker-build: ## Build the runtime image: $(IMAGE):$(TAG) from $(DOCKERFILE)
	@$(assert_docker)
	@$(call assert_file,$(DOCKERFILE))
	@printf "$(YELLOW)Building $(IMAGE):$(TAG) with $(DOCKERFILE)...$(RESET)\n"
	@DOCKER_BUILDKIT=1 docker build \
		$(DOCKER_BUILD_OPTS) \
		-t "$(IMAGE):$(TAG)" \
		-f "$(DOCKERFILE)" $(DOCKER_CONTEXT)
	@printf "$(GREEN)Built $(IMAGE):$(TAG)$(RESET)\n"

test: docker-build-test ## Alias: build the test stage (runs bats at build-time); fails if bats fails

docker-build-test: ## Build the test stage (runs bats at build-time) -> $(IMAGE):$(TEST_TAG); fails if bats fails
	@$(assert_docker)
	@$(call assert_file,$(DOCKERFILE))
	@printf "$(YELLOW)Building test stage '$(TEST_STAGE)' as $(IMAGE):$(TEST_TAG)...$(RESET)\n"
	@DOCKER_BUILDKIT=1 docker build \
		$(DOCKER_BUILD_OPTS) \
		--target "$(TEST_STAGE)" \
		-t "$(IMAGE):$(TEST_TAG)" \
		-f "$(DOCKERFILE)" $(DOCKER_CONTEXT)
	@printf "$(GREEN)Test stage built: $(IMAGE):$(TEST_TAG)$(RESET)\n"

docker-test: docker-build-test ## Build test stage then run bats in a disposable container; JUnit -> $(TEST_REPORT_DIR)
	@$(assert_docker)
	@mkdir -p "$(TEST_REPORT_DIR)"
	@docker rm -f "$(CONTAINER_NAME)-test-run" >/dev/null 2>&1 || true
	@printf "$(YELLOW)Running bats in container from $(IMAGE):$(TEST_TAG) ...$(RESET)\n"
	@docker run --rm --name "$(CONTAINER_NAME)-test-run" \
		-v "$(PWD)/$(TEST_REPORT_DIR)":/reports \
		"$(IMAGE):$(TEST_TAG)" \
		bash -lc 'if ! command -v bats >/dev/null; then echo "bats not found in image"; exit 127; fi; \
		          bats --report-formatter junit "$(BATS_TEST_PATH)" --output /reports --jobs $(NPROC)'
	@printf "$(GREEN)Tests complete. Reports at: $(TEST_REPORT_DIR)$(RESET)\n"

docker-test-exec: ## Run bats *inside an already-running* container $(CONTAINER_NAME); copies reports to $(TEST_REPORT_DIR)
	@$(assert_docker)
	@docker ps --format '{{.Names}}' | grep -xq '$(CONTAINER_NAME)' || { \
	  printf "$(RED)Error: container '$(CONTAINER_NAME)' is not running. Start it or set CONTAINER_NAME=...$(RESET)\n" >&2; exit 1; }
	@docker exec -i "$(CONTAINER_NAME)" bash -lc 'if ! command -v bats >/dev/null; then echo "bats not found in container"; exit 127; fi; \
		mkdir -p /reports; bats --report-formatter junit "$(BATS_TEST_PATH)" --output /reports --jobs $(NPROC)'
	@mkdir -p "$(TEST_REPORT_DIR)"
	@docker cp "$(CONTAINER_NAME):/reports" "$(TEST_REPORT_DIR)" >/dev/null 2>&1 || true
	@printf "$(GREEN)Tests complete. Reports copied to $(TEST_REPORT_DIR)/reports$(RESET)\n"

# ================== SBOM ==================
SBOM_IMAGE ?= $(IMAGE):$(TAG)
SBOM_DIR   ?= artifacts

# Optional --platform for a multi-arch tag. Prefer scanning a per-arch digest.
SBOM_PLATFORM ?=

# Syft: pinned version + per-arch SHA256 for reproducible, tamper-evident installs.
# CI installs it on both amd64 and arm64 runners (scripts/publish-sbom.sh).
# To upgrade: update SYFT_VERSION and both SHA256s from the checksums file at
#   https://github.com/anchore/syft/releases/download/v<VERSION>/syft_<VERSION>_checksums.txt
SYFT_VERSION      ?= 1.42.3
SYFT_SHA256_AMD64 ?= 0d6be741479eddd2c8644a288990c04f3df0d609bbc1599a005532a9dff63509
SYFT_SHA256_ARM64 ?= dc630590c953347789d08f8ebf57c7d8094db89100785fcd94b1cddeac791804
SYFT_BIN_DIR      ?= /usr/local/bin

install-syft: ## Install the pinned, checksum-verified Syft into $(SYFT_BIN_DIR) (no-op if that version is on PATH)
	@set -e; PATH="$(SYFT_BIN_DIR):$$PATH"; \
	 if command -v syft >/dev/null 2>&1 && syft version 2>/dev/null | grep -qE '^Version:[[:space:]]+$(SYFT_VERSION)$$'; then \
	   printf "syft v$(SYFT_VERSION) already installed: %s\n" "$$(command -v syft)"; exit 0; \
	 fi; \
	 case "$$(uname -m)" in \
	   x86_64|amd64)  arch=amd64; sum="$(SYFT_SHA256_AMD64)" ;; \
	   aarch64|arm64) arch=arm64; sum="$(SYFT_SHA256_ARM64)" ;; \
	   *) printf "$(RED)Error: no pinned syft checksum for architecture %s$(RESET)\n" "$$(uname -m)" >&2; exit 1 ;; \
	 esac; \
	 printf "$(YELLOW)Installing syft v$(SYFT_VERSION) (linux_$$arch) with checksum verification...$(RESET)\n"; \
	 tmpdir=$$(mktemp -d); trap 'rm -rf "$$tmpdir"' EXIT; \
	 curl -sSfL --retry 3 -o "$$tmpdir/syft.tar.gz" \
	   "https://github.com/anchore/syft/releases/download/v$(SYFT_VERSION)/syft_$(SYFT_VERSION)_linux_$$arch.tar.gz" \
	   || { printf "$(RED)Error: download of syft v$(SYFT_VERSION) (linux_$$arch) failed$(RESET)\n" >&2; exit 1; }; \
	 printf '%s  %s\n' "$$sum" "$$tmpdir/syft.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
	   || { printf "$(RED)Error: SHA256 checksum verification failed for syft v$(SYFT_VERSION) (linux_$$arch)$(RESET)\n" >&2; exit 127; }; \
	 tar -xzf "$$tmpdir/syft.tar.gz" -C "$$tmpdir" syft; \
	 mkdir -p "$(SYFT_BIN_DIR)"; install -m 0755 "$$tmpdir/syft" "$(SYFT_BIN_DIR)/syft"; \
	 printf "$(GREEN)Installed syft v$(SYFT_VERSION) to $(SYFT_BIN_DIR)$(RESET)\n"

sbom: install-syft ## SBOM for $(SBOM_IMAGE) in ONE Syft scan (SPDX JSON + table); SBOM_IMAGE=registry:<ref> needs no Docker
ifeq ($(filter registry:%,$(SBOM_IMAGE)),)
	@$(assert_docker)
endif
	@mkdir -p "$(SBOM_DIR)"
	@printf "$(YELLOW)Generating SBOM for $(SBOM_IMAGE)...$(RESET)\n"
	@PATH="$(SYFT_BIN_DIR):$$PATH" syft scan "$(SBOM_IMAGE)" $(if $(SBOM_PLATFORM),--platform "$(SBOM_PLATFORM)") \
		-o spdx-json="$(SBOM_DIR)/sbom-syft.json" -o syft-table="$(SBOM_DIR)/sbom-syft.txt"
	@printf "$(GREEN)SBOM written to $(SBOM_DIR)/sbom-syft.json (SPDX) and $(SBOM_DIR)/sbom-syft.txt (table)$(RESET)\n"

