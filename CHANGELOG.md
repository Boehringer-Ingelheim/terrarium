# Changelog

## [Unreleased]

## [4.8.4] 2026-10-26 — Maintenance-line security release: Node 24 LTS, emSign CA remediation, Go 1.26

4.8 is the line for Ruby, kitchen-terraform and InSpec users. Everyone
else should use 4.9.6. This patch release ships the same security fixes as
4.9.6, for two upstream incidents:

- **The Node.js October 2026 security release**, which includes Node2Shell
  (CVE-2026-111497).
- **The eMudhra/emSign intermediate CA compromise.** The private keys of
  eight eMudhra intermediates can be recovered from their public
  certificates. Mozilla-derived stores trusted them through a cross-signature
  by *emSign ECC Root CA - G3*, and some older stores also through Sectigo's
  *AAA Certificate Services*.

The OS update alone is not enough. pip, certifi, uv, Node, several vendor
CLIs and, on this line, several Ruby gems carry their own root stores, and
every one of them was refreshed. The 4.8.4 date above is a placeholder until
the tag.

### Security (INFIAAS-11916)

- **Node.js 24.14.0 → 24.22.1.** This fixes CVE-2026-111497 and nine other
  CVEs, and drops *emSign ECC Root CA - G3* from Node's built-in roots. The
  Node major is unchanged.
  - npm is now pinned to 11.20.0 (`NPM_VERSION`); Node bundles 11.19.1.
  - New `NPM_BUNDLED_PATCHES`: `undici` 6.29.1, `ip-address` 10.7.5,
    `brace-expansion` 5.0.12 and `postcss-selector-parser` 7.1.7. These are
    swapped into npm's own `node_modules` by the new `npm_patch_bundled`
    helper (from master, INFIAAS-9587), because npm 11.20.0 still bundles the
    vulnerable versions.
- **OS trust store:** `ca-certificates` 2026.2.92_v9.0.319-90.3.el9_8
  (RHSA-2026:88459). The base images move to UBI 9.8 and Rocky 9.8; Rocky
  9.3 had been EOL since 9.4.
- **Python:**
  - CPython 3.13.12 → 3.13.17. Its ensurepip seeds pip 26.2.2.
    `PYTHON_VERSION` is now in the image ENV, so `10_python.bats` really
    checks the interpreter. Before, it compared against an empty string.
  - pip → 26.2.2 for the pyenv interpreter and the `/opt/openstack` venv,
    pinned exactly via the new `PIP_VERSION` build-arg (build-time only, never
    ENV). Neither pip was ever upgraded before. pip always loads its vendored
    certifi, so OS fixes do not reach it.
  - certifi:
    - `/tmp/.venv`: 2025.7.14 → 2026.10.23, now an explicit floor in
      `pyproject.toml`.
    - `/opt/openstack`: 2026.10.23 via the new `OPENSTACK_OVERRIDES`.
  - uv 0.11.15 → 0.13.5 in `/tmp/.venv`, and 0.13.5 in `~/.local/bin`.
  - pipenv 2024.4.1 → 2026.10.3. Its patched pip was 24.3.1.
  - virtualenv 20.36.1 → 21.14.13, which seeds pip 26.2.2.
  - The uv download cache is no longer shipped in `~/.cache/uv` (from master,
    INFIAAS-9587). It held a second, stale botocore CA bundle.
- **Go 1.21.13 → 1.26.10** (user toolchain at `/usr/local/go`). Go 1.21 has
  been EOL since 2024-08. The prebuilt Go tools are unaffected.
- **Ruby gem CA bundles (4.8 only).** aws-sdk-core 3.234.0, excon 0.112.0,
  httpclient 2.9.0 (two bundles) and ms_rest 0.7.6 ship their own frozen
  Mozilla bundles, and all of them still trusted the compromised
  intermediates. httpclient and ms_rest have no newer release, so the new
  `link_system_ca_bundle` helper relinks each bundle to
  `/etc/pki/tls/certs/ca-bundle.crt`. The gems now trust exactly what the OS
  trusts. The gem versions are unchanged.
- **Findings in components we pin**, cleared where the fix stays inside this
  line's rules (security fixes only, no major tool moves; the release-gate
  scan found them):
  - oc 4.19.0 → 4.19.51 and kubectl 1.35.3 → 1.35.9 (newest patches).
  - helm 3.20.1 → 3.22.0, sops 3.12.2 → 3.13.3, tenv 4.11.1 → 4.15.1,
    yq 4.52.4 → 4.54.1, trivy 0.69.3 → 0.76.1.
  - OpenTofu 1.11.5 → 1.11.14 (newest 1.11.z).
  - `/opt/openstack` (OpenStack constraints stay 2025.1): urllib3 2.8.0,
    cryptography 50.0.2, requests 2.34.2, idna 3.18 and msgpack 1.2.1 via
    `OPENSTACK_OVERRIDES`. `pip check` passes.
  - `/tmp/.venv`: PyJWT 2.13.0 → 2.15.1 (critical), urllib3 2.7.0 → 2.8.0,
    oauthlib 3.3.1 → 4.0.0, cryptography 46.0.7 → 47.0.0, filelock 3.25.2 →
    4.2.4.
- **`.trivyignore.yaml` re-derived for the 4.8 package set** (amd64 scan,
  1109 entries, all expiring 2026-12-31, each scoped to an exact path or
  purl). Besides the vendor-only rules shared with 4.9.6, it lists what this
  line deliberately keeps, with a statement saying so:
  - **Tools that follow the ODS terraform-2408 agent:** the default
    Terraform 1.9.4 (tenv installs whatever a project pins), terraform-docs
    v0.18.0, packer 1.11.2, tflint 0.52.0, age 1.2.0 and go-task 3.38.0.
  - **Ruby 3.3.4 and its default gems.** A patch bump would break projects
    that pin `.ruby-version` 3.3.4.
  - **The kitchen-terraform/InSpec gem set** (`Gemfile.lock`). excon,
    rubyzip and mongo need a major or a minor inside the InSpec stack.
  - **`/tmp/.venv` cryptography 47.0.0 and PyNaCl 1.5.0**, held by
    azure-cli 2.75.0. The RPM `az` 2.91.0 resolves first on PATH.
  - **terraform-config-inspect v0.2.0**, the fork's newest release.

  All of these are lifted by moving to terrarium 4.9.
- **New in-image test: `docker/tests/15_ca_distrust.bats`** (from master). It
  checks that every CA store rejects all 16 compromised certificates (8 keys ×
  2 issuers) when the attacker's cross-signature is supplied. The stores are
  the system bundle and its extractions, OpenSSL's default store, every
  certifi, every pip we install, the pip that new venvs get, both uv
  binaries, Node's roots, and every PEM CA file on disk that carries any of
  the four roots. On this candidate it is green, 15/15.
- **Vendor CLIs re-fetched at their newest releases:** Google Cloud CLI
  590.0.1 removed the distrusted roots, and AWS CLI 2.38.5 removed AAA from
  its bundle.
- **Residuals.** Each of these ships the vendor's newest release, or is
  unused. The bats suite lists and reports each one, with an expiry.
  - **Azure CLI RPM 2.91.0.** Its bundled certifi and pip
    (`/usr/lib64/az`) still trust the intermediates. The fix is merged on
    Azure's dev branch but not released
    ([Azure/azure-cli#34250](https://github.com/Azure/azure-cli/pull/34250),
    [#34275](https://github.com/Azure/azure-cli/pull/34275)).
    - Workaround: `uv run --directory /tmp az`, the fixed venv copy.
    - Or set `REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt`.
  - **AWS SAM CLI 1.170.0.** Its bundled certifi 2026.7.22 and botocore
    still trust them
    ([aws/aws-sam-cli#9359](https://github.com/aws/aws-sam-cli/pull/9359)).
    - Workaround: `AWS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt`.
  - **The `/tmp/.venv` botocore 1.39.x CA bundle.** It is an unused fallback,
    because botocore loads the fixed certifi first.

### Known issues

**Legacy quickstarter projects: `make init` fails while installing
`bigdecimal`**
([INFIAAS-11725](https://jira.biscrum.com/browse/INFIAAS-11725))

- **Symptom:** `make init` in a project generated from the legacy (AGE)
  Terraform quickstarter stops with `An error occurred while installing
  bigdecimal (…), and Bundler cannot continue.`
- **Cause:** the image ships no C compiler (since 4.8.1, by design), and the
  legacy quickstarter installs its Ruby gems into the project
  (`vendor/bundle`), which forces native gems to be compiled. The image itself
  is not broken: its pre-built gems at `/opt/bundle` are complete, and
  `kitchen` and `cinc-auditor` work out of the box.
- **Remediation, in order of preference:**
  1. **Migrate** to the current (CCG) OpenTofu quickstarter, which has no Ruby
     at all.
  2. **Apply the three-change quickstarter patch**
     ([rec-a-makefile.patch](https://bitbucket.biscrum.com/projects/CCG/repos/click.stack.ship.workflow.artifacts/browse/quickstarter/INFIAAS-11725-ruby-bundler-issue-with-old-qs-in-terrarium-4.8.1/rec-a-makefile.patch)):
     delete `.ruby-version`, make `install-ruby-gems` use the image's
     pre-built gems, and call the `kitchen` / `cinc-auditor` wrappers.
     `make init` then succeeds without a compiler, root or a rebuild.
  3. **Immediate unblock:** skip `make install-ruby-gems`; `kitchen` and
     `cinc-auditor` already work in the image.
- **Discouraged:** running the container as root and installing a compiler.
  It rebuilds hundreds of gems in every workspace, and leaves root-owned
  files that break the next non-root run.
- **Ownership:** keeping a generated project's toolchain current is the
  **project team's** responsibility. The legacy quickstarter still pins Ruby
  2.7.5, which has been end of life since March 2023.

### Changed (INFIAAS-11916)

- **On release tags, `latest` and `<major>-linux-<arch>` move only for the
  highest release.** The new `scripts/is-highest-release.sh` reuses
  `is-prerelease.sh` and compares the tag against the highest stable tag,
  local and remote. On a tag push it gates the multi-arch `latest` manifest
  (`main.yaml`, `release.yaml`) and the per-arch `latest-linux-<arch>` and
  `<major>-linux-<arch>` tags (`main.yaml`). Every `docker/metadata-action`
  step sets `flavor: latest=false`, so the action's default `latest=auto`
  cannot bypass the guard. 4.8.4 therefore cannot move `latest` away from
  4.9.x. `make guardrails` enforces the wiring.
  - Unchanged: on every **master push**, the per-arch `latest-linux-<arch>`
    tags track master.
  - No multi-arch `<major>` (e.g. `4`) tag is published, only
    `<major>-linux-<arch>`.
- **`make lint` is blocking, hadolint included.** The two config heredocs
  (the google-cloud repo and the tenv profile) are now static files under
  `docker/files/`. hadolint is pinned to v2.15.1 by digest.
- **`make guardrails` checks pin freshness** (`GO_VERSION`,
  `ROCKYLINUX_VERSION`, `UBI9_VERSION`), as on master.
- **`SECURITY.md`:** the supported versions are now the default branch plus
  the latest patch of the two most recent minor lines (4.9.x and 4.8.x). It
  also lists the published tags and how each one moves.

### Fixed (INFIAAS-11804, release pipeline)

- **Builds no longer fail on GitHub's anonymous API rate limit (INFIAAS-11804).**
  `tenv tofu install` looks up OpenTofu releases through `api.github.com`,
  which allows 60 anonymous requests per hour per IP. CI runners share IPs, so
  the `v4.9.1-pre` release failed on all three build attempts
  (`you are rate-limited by GitHub`). CI now passes the job's `GITHUB_TOKEN` as
  the BuildKit secret `tenv_github_token`, handed to that one command only. It
  is never a build-arg or `ENV`, so it is not in any layer, cache key or the
  image. Without the secret (forks, local builds) tenv runs anonymously, as
  before. Local builds can opt in with `TENV_GITHUB_TOKEN=… make docker-build-test`.

- **Least privilege for the build jobs that run tenv (INFIAAS-11804).** Because
  that token reaches third-party build tooling, no build job holds
  `contents: write` any more. `release.yaml` gains a `tag` job (creates the
  tag) and a `release-assets` job (attaches the SBOMs to a GitHub Release);
  the `release` build job is `contents: read`. The tenv RPM, previously
  installed straight from its URL, is now SHA-256-verified against the
  release's `checksums.txt` first. The old tag step's empty-tag check could
  never fire (it ran after the `v` prefix was added) and now does.

- **GHCR publishing restored (INFIAAS-11804).** Every publish since 2026-09-17
  (incl. the `v4.8.3` release, which was never published) failed with
  `sbom.spdx.json exceeds 41943040 bytes`. Cause: CI did not pin BuildKit, and
  `moby/buildkit:buildx-stable-1` moved from v0.31.2 to v0.32.2, which added an
  undocumented 40 MiB attestation cap ([moby/buildkit#7044]). Our SBOM has been
  ~66 MiB since at least 4.8.1; the image did not grow.

- **A pushed pre-release tag can no longer move `latest` (INFIAAS-11804, B4).**
  `main.yaml`'s tag-push manifest added `latest` for every `v*` tag. Both
  workflows now classify the tag with `scripts/is-prerelease.sh`, which replaces
  `release.yaml`'s unanchored `-(pre|alpha|beta|rc)` regex, and add `latest`
  only for a plain `vX.Y.Z`. An unrecognised tag fails the manifest job, and a
  new guardrail rejects any unconditional `value=latest`.

- **Released images are actually scanned (INFIAAS-11804).** `scan.yaml`'s
  `release: published` trigger scanned `latest-<arch>`, never fired for a
  `workflow_dispatch` cut (no GitHub Release), and raced the build for UI
  releases. `release.yaml` now calls `scan.yaml` (`workflow_call`,
  `image-tag` input) after its manifest job, so the exact published
  `<ver>-linux-<arch>` images are scanned. A release scan fails hard if the
  image can't be pulled, instead of silently falling back to a filesystem
  scan. Release results use their own SARIF category (`trivy-release-<arch>`).
  A table-format Trivy step prints the findings in the job log; it is
  informational, and the SARIF scan still gates.

### Changed (INFIAAS-11804, release pipeline)

- **4.8 maintenance line: `release/4.8` (INFIAAS-11916).** This branch is cut
  from `v4.8.3` and carries the INFIAAS-11804 publish fixes above (BuildKit pin,
  signed standalone SBOM, pre-release `latest` guard, release-tag scan, tenv
  token) plus the release Trivy gate (`.trivyignore.yaml`,
  `scripts/trivy-residuals.sh`), backported from `master`. PRs into
  `release/**` now run `main.yaml` (build & test) and `lint.yaml`, as PRs into
  `master` do (`scripts/tests/ci_triggers.bats`). The `.trivyignore.yaml`
  residuals are re-derived for the 4.8 package set (see Security above).

- **BuildKit pinned** to `v0.33.0@sha256:6c2fa84a…` in `main.yaml` and
  `release.yaml` (`setup-buildx-action` `driver-opts`). A new guardrail
  (`make guardrails` → "buildkit pinned") fails if any buildx setup is unpinned
  or tag-only; the "unpinned actions" check now also covers local composite
  actions under `.github/actions/`.
- **SBOM moved out of BuildKit** (`--sbom=false`). A full Syft SPDX SBOM per arch
  is generated after push (`scripts/publish-sbom.sh`, via the
  `.github/actions/publish-sbom` composite action), **attached to the image
  digest in GHCR** (`oras attach`, `application/spdx+json`), **signed keyless**
  with cosign, uploaded as the `sbom-<arch>` workflow artifact, and attached to
  the GitHub Release when one exists. Fails closed: no SBOM, no release manifest.
  Consumers reading `docker buildx imagetools inspect --format '{{json .SBOM}}'`
  must switch to `oras discover` — see SECURITY.md → SBOM. Image size is
  unaffected (the SBOM was never an image layer).
- `make sbom` scans **once** (was twice), accepts `SBOM_IMAGE=registry:<ref>`
  without a Docker daemon, and takes `SBOM_PLATFORM`. The checksum-verified Syft
  installer is now `make install-syft`, with a pinned SHA256 per arch
  (`SYFT_SHA256_AMD64` / `SYFT_SHA256_ARM64`, replacing `SYFT_SHA256`), so it
  also works on the arm64 runner.

### Added

- `scripts/tests/` — hermetic bats suite for CI scripts (`publish_sbom.bats`,
  `check_guardrails.bats`, `is_prerelease.bats`, `release_scan_wiring.bats`), run by `make test-scripts` / `make test-helpers` and
  in `lint.yaml` ("CI-script unit suite").

[moby/buildkit#7044]: https://github.com/moby/buildkit/issues/7044

## [4.8.3-pre] 2026-07-24 — Helper extraction, CI gates, installer decomposition — INFIAAS-11426

### Added

- **Named, unit-tested helper scripts.** The eight shell programs previously
  embedded as Dockerfile heredocs are now files under `docker/files/bin/`:
  `fetch`, `verify_gpg_signed_checksums`, `verify_gpg_detached`,
  `verify_sha256_from_url`, `verify_sha256_from_checksums`, `import_vendor_key`,
  `install_age`, `import_node_keyring`, plus the `kitchen` / `cinc-auditor`
  wrappers. Installed into the image with a single `COPY files/bin/`.
- **Hermetic unit-test tier** under `docker/tests/unit/` (bats-core only, no
  network, nothing outside `$BATS_TEST_TMPDIR`) covering every helper's success
  path and documented failure exits — 35 tests. Runnable via `make test-helpers`
  (host) or the new `helpers` build stage (`make docker-test-helpers`).
- **CI quality gates** (`.github/workflows/lint.yaml`): `make guardrails`
  (mechanical do-not-regress security counts + ratchet metrics), `make
  shellcheck` (severity=warning), `make check-keys-drift` (vendor-key pins vs the
  Dockerfile `ENV` block, fingerprints only), and the helper unit stage.
  `.hadolint.yaml` + `.shellcheckrc` added; hadolint runs informationally
  (blocked only by the two by-design config heredocs).
- `scripts/dockerfile-arg.sh` — single hardened replacement for the four
  duplicated inline `arg_val()` one-liners in the workflows; fails loudly on a
  missing/empty ARG.

### Changed

- **Dockerfile decomposition** — zero helper-writing heredocs remain (only the
  two by-design config heredocs); no `RUN` block exceeds 20 lines (the age/sops
  and Node keyring installers are now `install_age` and `import_node_keyring`).
- Absorbed Dependabot bumps: `faraday` 1.10.5 → 1.10.6, `jwt` 2.10.2 → 2.10.3.
- Repointed the remaining `ghcr.io/nichtraunzer/terrarium` image references in
  the docs/examples/devcontainer to `ghcr.io/boehringer-ingelheim/terrarium`.

### Removed

- Deleted five orphaned, unreferenced files under `docker/files/` (`bashrc`,
  `envs.sh`, `gitconfig_skel`, `prompt.sh`, `setup.sh`).

## [4.8.2-pre] 2026-07-22 — Migration to the Boehringer-Ingelheim GitHub org + Dependabot integration — INFIAAS-11425 / INFIAAS-11440

### Changed

- **Repository migrated** into the Boehringer-Ingelheim GitHub org; image
  references and CI updated accordingly (lowercased GHCR owner for the
  mixed-case org).
- **Release tags standardised** (INFIAAS-11425): v-prefixed git tags,
  v-less image tags in `release.yaml`.
- **Dependabot backlog integrated** (INFIAAS-11440) — bundler: `chef-config`,
  `chef-utils` 19.2.12 → 19.3.14; uv: `setuptools` 80.9.0 → 83.0.0, `uv`
  0.11.7 → 0.11.15, `urllib3` 2.6.3 → 2.7.0, `idna` 3.10 → 3.15, `pyjwt`
  2.12.0 → 2.13.0; github-actions: `checkout` → 7.0.1, `setup-buildx-action`
  → 4.2.0, `metadata-action` → 6.2.0, `docker-manifest-create-action` → 2.25.0,
  `harden-runner` → 2.20.0.

## [4.8.1] 2026-04-22 - Housekeeping PR  - PR #72

4.8.1-pre has been tested and appears to be in good shape for a release.

### Changed

- Disabled daily trivy scans to reduce CICD noise
- Cleaned up changelog to more accurately reflect versioning and releases

## [4.8.1-pre] 2026-04-21 — PGP vendor-key unification, tenv expired-key fix, Jenkins-agent tool alignment, Dependabot integration  - PR #71

### Added

- **Unified PGP vendor-key import** — single source of truth for HashiCorp, OpenTofu, AWS CLI, and Node release fingerprints via `docker/vendor-keys/refresh-vendor-keys.sh`. New `print-shell-env` subcommand emits a shell-sourceable `KEY="VAL"` pin file (for `make write-keys`); new `strict` subcommand compares freshly computed fingerprints against the env-pinned values and exits non-zero on drift (for `make check-keys` in CI).
- **OpenTofu vendored via tenv** — no separate install path; tenv handles both Terraform and OpenTofu.
- Dev-tooling OS packages added to the builder stage:
  - `ripgrep` — AI coding agents (Claude Code, Cursor) and `grep -r` power users expect `rg` for fast recursive search.
  - `util-linux-user` — provides `chsh`, required by the devcontainer `common-utils` feature to switch the default shell (e.g. to zsh).
  - `ca-certificates` — keep trust anchors up to date for curl/openssl fetches.
  - `libyaml-devel` — header package kept alongside `libyaml` so downstream images can rebuild native extensions (Ruby psych, Python PyYAML).
- Three new bats smoke tests in `docker/tests/01_common_dev_tools.bats` for the above — `ripgrep`, `chsh`, and the CA bundle.
- `make test` alias for `make docker-build-test` with updated README documentation.
- Local developer helper `scripts/build-test-local.ps1` for line-by-line PowerShell-extension testing.
- `uv` is pinned in `docker/pyproject.toml` as `uv~=0.11.6`; Dockerfile `UV_VERSION` wiring remains commented out / deferred.

### Fixed

- **Terrarium user and devtools group moved into builder stage** — the `terrarium` user (UID 1001), `devtools` group (GID 2001), and bats test helpers (bats-support/bats-assert) were previously created only in the `test` stage. The published image (`final`) shipped without a user entry in `/etc/passwd`, breaking downstream consumers. All three are now in the `builder` stage so the published `test` stage and any other downstream stages inherit them.
- **Removed empty `final` stage** — the empty `final` stage was removed, and the published image target is the `test` stage built from `builder`, with tests, user, and helpers baked in.
- Tests now ship in the published `test` image for runtime health checks — downstream consumers can run `bats /home/terrarium/tests` to verify the container after deployment.
- **`tenv` 4.9.3 → 4.11.1** — `tenv 4.11.0` introduced a fix for PGP signature checking that tolerates the expired HashiCorp release key. The old 4.9.3 pin failed at image-build time because the HashiCorp `.well-known` PGP key had entered the expired window and 4.9.3's `--skip-signature` did not short-circuit before the key was parsed. This unblocks `docker build`.
- `BUNDLED WITH` in `docker/Gemfile.lock` aligned with `BUNDLER_VERSION` so the builder-stage `bundle check` does not encounter lockfile metadata from a bundler version that is not actually installed in the image.

### Changed

- **Tool versions aligned to the ODS Jenkins agent baseline** ([terraform-2408](https://github.com/opendevstack/ods-quickstarters/blob/master/common/jenkins-agents/terraform-2408/docker/Dockerfile.ubi9)):
  - `AGE_VERSION` 1.3.1 → 1.2.0
  - `BUNDLER_VERSION` 4.0.9 → 2.5.17
  - `GO_VERSION` 1.26.1 → 1.21.13
  - `PACKER_VERSION` 1.15.0 → 1.11.2
  - `RUBY_VERSION` 3.4.9 → 3.3.4
  - `TASK_VERSION` 3.49.1 → 3.38.0
  - `TERRAFORM_DOCS_VERSION` v0.21.0 → v0.18.0
  - `TERRAFORM_VERSION` 1.14.7 → 1.9.4
  - `TFLINT_VERSION` 0.61.0 → 0.52.0
- GitHub Actions (addresses outstanding upstream Dependabot PRs):
  - `step-security/harden-runner` 2.16.1 → 2.19.0 — closes [nichtraunzer/terrarium#64](https://github.com/nichtraunzer/terrarium/pull/64).
  - `int128/docker-manifest-create-action` 2.17.0 → 2.18.0 — closes [nichtraunzer/terrarium#65](https://github.com/nichtraunzer/terrarium/pull/65).
  - `github/codeql-action` 4.35.1 → 4.35.2 — closes [nichtraunzer/terrarium#66](https://github.com/nichtraunzer/terrarium/pull/66).
- Ruby gems (via `bundle lock --update=<gem>`; addresses outstanding upstream Dependabot PRs):
  - `syslog` 0.1.2 → 0.4.0 — closes [nichtraunzer/terrarium#58](https://github.com/nichtraunzer/terrarium/pull/58).
  - `mixlib-install` 3.12.30 → 3.16.1 — closes [nichtraunzer/terrarium#67](https://github.com/nichtraunzer/terrarium/pull/67).
  - `irb` 1.14.0 → 1.17.0 — closes [nichtraunzer/terrarium#68](https://github.com/nichtraunzer/terrarium/pull/68).
  - `aws-sdk` 3.2.0 → 3.3.0 — closes [nichtraunzer/terrarium#69](https://github.com/nichtraunzer/terrarium/pull/69).
  - `test-kitchen` 3.6.0 → 3.9.1 — closes [nichtraunzer/terrarium#70](https://github.com/nichtraunzer/terrarium/pull/70).
- Other transitive bumps: `addressable` 2.9.0, `csv` 3.3.0 → 3.3.5, `mutex_m` 0.2.0 → 0.3.0.
- Python tooling: `uv` 0.11.6, `cryptography` 46.0.7.

### Docs

- README: test-layout filenames updated to match `docker/tests/` (`00_os.bats`, `01_common_dev_tools.bats`, `07_node_npm.bats`, `10_python.bats`, `30_cloud_platforms.bats`, `95_slimdown.bats`); dead `python_requirements` link replaced with `docker/pyproject.toml` + `docker/uv.lock` with a `uv lock` refresh hint.
- TOOLS_AND_LICENSES: pinned base-image rows to `ubi9/ubi:9.5` and `rockylinux:9.3` to match Dockerfile ARGs.
- Dockerfile: clarifying comment on the `test` stage explaining it is the deliberate publish target (bats suite intentionally ships in the image for consumer re-runs).

## [4.8.1-pre] - 2026-04-03 — Dockerfile hardening, image slimdown, CI improvements, test reorganisation - PR #61

### Image slimdown (~350 MB reduction)

- **Build-dep removal**: Compiler toolchain (gcc, gcc-c++, cpp, binutils, autoconf, automake, libtool, kernel-headers, `*-devel` packages) removed from final image after native extensions are compiled.
- **Documentation purge**: `/usr/share/doc`, `/usr/share/man`, `/usr/share/info` removed from final image.
- **dnf `tsflags=nodocs`**: Prevents future `dnf install` from adding documentation.
- **Locale cleanup**: Non-`en_US` locale data and stale locale archive template removed.
- **`.git` metadata stripped**: pyenv and rbenv `.git` directories removed in buildlang stage before COPY into builder.
- **GPG temp files cleaned**: `/opt/keys/tmp` removed after build-time signature verification.
- Retains make, git, openssl, curl, sudo, and all runtime libraries.

### Dockerfile refactoring

- **Centralised version ARGs**: All tool versions defined in a single alphabetically sorted global ARG block at the top of the Dockerfile. Builder ENV block now references `${VAR}` instead of hardcoded values.
- **Pinned base images**: `rockylinux:9.3` (buildlang), `ubi9/ubi:9.5` (builder) for build determinism.
- **Bundle cache reconciliation**: Builder stage runs non-frozen `bundle install` first (reconciles stale GHA cache), then `BUNDLE_FROZEN=true bundle check` as the integrity gate.
- Bumped Bundler 2.7.2 → 4.0.9.

### CI/CD improvements

- **Release workflow**: Added `release: [published]` event trigger. Conditional `latest` tag auto-detects pre-release tags (`-pre`, `-alpha`, `-beta`, `-rc`) and skips `latest` update.
- **Scan workflow**: Path-filtered `push`/`pull_request` triggers (`docker/**`, scan.yaml). Schedule changed from daily to weekly (Monday 06:00 UTC). Added `release: [published]` trigger.
- **GEMFILE_HASH cache-buster**: SHA256 of Gemfile.lock passed as build arg to invalidate stale GHA buildlang cache.
- **Pinned syft**: Makefile sbom target uses syft v1.42.3 with SHA256 checksum verification (replaces curl-pipe-sh installer).

### Test suite reorganisation

- `00_core.bats` → `00_os.bats` — scoped to OS family, devtools group, permissions, PATH, GNUPGHOME.
- New `01_common_dev_tools.bats` — make, git, openssl, curl, sudo, jq, parallel, Go.
- New `95_slimdown.bats` — negative assertions confirming build deps (gcc/g++/cpp) and docs are removed.
- Moved tests to logical homes: trivy → `20_infra.bats`, oc → `60_k8s.bats`, Go → `01_common_dev_tools.bats`.
- Added pip test to `10_python.bats`.
- All 55 original tests preserved; 12 new tests added (67 total).

### Upgraded

- cinc-auditor-bin 5.22.55 → 5.23.6 (with inspec/inspec-core 5.23.6)
- Gemfile.lock regenerated for Ruby 3.4.9 + Bundler 4.0.9

---

## [4.8.0] - 2026-03-23 — Rocky 9 tool upgrades, tfsec→Trivy, GCP CLI and Security Hardening ( PR #42 )

### Security

- **GitHub Actions hardened**: All actions pinned to immutable commit SHAs; mutable tags eliminated
- **GITHUB_TOKEN least privilege**: Workflow-level `permissions: contents: read` enforced; write permissions scoped to specific jobs
- **Context dumps removed**: Debug context gated behind `workflow_dispatch` input; `github.token` no longer serialized to logs
- **Secret isolation verified**: No secrets in global `env:` blocks; GITHUB_TOKEN scoped to login steps only
- **release.yaml reintegrated**: Manual release workflow with all security hardening applied
- **harden-runner**: `step-security/harden-runner` integrated in all workflow jobs (egress audit mode)
- **CODEOWNERS**: Review gates added for workflows, Dockerfile, and security config

### Breaking Changes

- **tfsec removed, replaced by Trivy** — if you reference `tfsec` in scripts/CI, replace with `trivy fs --scanners misconfig`
- **Consul removed** — no longer bundled; install separately if needed
- **Deprecated tool versions removed:** old Terraform 1.4.6, Bundler 2.4.13

### Added

- OpenTofu 1.11.5 via tenv (`OPENTOFU_VERSION` env var, `tenv tofu install/use`)
- Trivy 0.69.3 (IaC security scanner, replaces deprecated tfsec)
- GCP CLI (`gcloud`) via Google Cloud SDK yum repo
- `.github/CODEOWNERS` — require review for security-sensitive paths
- `.github/workflows/release.yaml` — manual release workflow with full hardening
- `TOOLS_AND_LICENSES.md` — tools and OSS license inventory for compliance visibility

### Upgraded

- Python 3.12.11 → 3.13.12 (via pyenv)
- Ruby 3.4.1 → 3.4.9 (via rbenv)
- Bundler 2.7.1 → 2.7.2
- Node.js 24.5.0 → 24.14.0
- Go 1.24.6 → 1.26.1
- tenv 1.2.0 → 4.9.3
- Terraform default 1.12.2 → 1.14.7
- Packer 1.14.1 → 1.15.0
- kubectl 1.33.3 → 1.35.3
- Helm 3.18.4 → 3.20.1
- sops 3.10.2 → 3.12.2 (repo moved from mozilla/sops to getsops/sops)
- age 1.1.0 → 1.3.1
- tflint 0.58.1 → 0.61.0
- terraform-docs v0.20.0 → v0.21.0
- starship 1.23.0 → 1.24.2
- zoxide 0.9.4 → 0.9.9
- bats-core 1.11.0 → 1.13.0
- yq 4.47.1 → 4.52.4
- Task 3.43.1 → 3.49.1

### Removed

- tfsec (EOL — use Trivy instead)
- Consul (no longer used internally)

---

## 2026-03-23 — refactor: move terraform/docker/ → docker/ ( PR #42 )

### Changed

- Moved all build artifacts from `terraform/docker/` to `docker/` to simplify
  the repo layout and remove the misleading `terraform/` prefix.
- Updated all references in Makefile, GitHub Actions workflows, dependabot config,
  .gitignore, README, and CHANGELOG.

---

## 2025-08-22 PR #46 Make Terrarium image UID‑agnostic via stable devtools group; fix Ruby toolchain permissions & PATH for Dev Containers

<https://github.com/nichtraunzer/terrarium/pull/46>

### Changed

- Image is now **UID‑agnostic** by introducing a stable `devtools` group (`DEVTOOLS_GID`, default `2001`) and applying setgid + group‑writable perms to `/opt/bundle` and `/opt/rbenv` (optional: `/opt/pyenv`, `/opt/tenv`).
- Toolchain PATH and `rbenv` init are loaded for **login and non‑login shells** via `/etc/profile.d/10-terrarium-path.sh` and `/etc/bashrc.d/10-terrarium-path.sh`.

### Added

- Cooperative `umask 0002` for dev shells to keep group‑writable files.

### Fixed

- `kitchen` / `cinc-auditor` reliably resolve on PATH; **no more Dev Container `postCreateCommand` chowns** required. Downstream users just add their user to `devtools` (`usermod -aG devtools <user>`).

## 2025-08-18 PR #44 feat(tools): added kubectl and helm with validation tests

<https://github.com/nichtraunzer/terrarium/pull/44>

### Added

- `kubectl` and `helm` installed with install validation tests.

### Changed

- Updated `Dockerfile.terrarium` and `kubectl` to version `1.33.3` and actually install.
- Updated `Dockerfile.terrarium` and `helm` to version `3.18.4` and actually install.
- `k8s` validation tests for `kubectl` and `helm`.

## 2025-08-08 PR #41 — feat(python): pyenv and uv are now installed (merged 2025‑08‑08)

### Added

- `uv` preinstalled for fast, deterministic Python workflows.
- `pyenv` to build and select CPython; patch‑exact pin via `PYTHON_VERSION` (default `3.12.11`).
- New Bats test `tests/10_python.bats` to verify `python`, `pyenv`, and `uv`.

### Changed

- `Dockerfile.terrarium` now produces Python via `pyenv` and puts pyenv shims first in `PATH`.
- Extra compile deps added to ensure a full‑featured CPython build (e.g. `bzip2‑devel`, `xz‑devel`, `tk‑devel`, etc.).
- Moved the basic Python existence check out of `00_core.bats` (covered by `10_python.bats`).

### Removed

- Reliance on system RPMs (`python3.12*`) baked into the image.

---

## 2025-07-29 PR #40 — feat(ci): add Bats test‑suite for basic successful tool installation checks (merged 2025‑07‑28)

### Added

- Comprehensive Bats smoke/regression suite under `terraform/docker/tests/`:
  - `00_core.bats`, `20_infra.bats`, `30_aws.bats`, `40_terraform.bats`, `50_ruby_ecosystem.bats`, `60_k8s.bats`, `90_extras.bats`.
- Test helper libraries vendored (`bats-support`, `bats-assert`) plus `tests/test_helper/common.bash`.
- New multi‑stage `Dockerfile.terrarium` **test** target that runs the suite and emits a JUnit report at build time.
- CI updated so builds target t Yeah so it's still old it is still old and new in sequence yet he **test** stage across all matrix architectures; failures block image publishing.

### Changed

- CI/workflows refinements (e.g., ARM runner selection, manifest creation, checkout v4) and improved tagging/diagnostics.
- README updated to describe the Bats testing approach.

### Dependencies

- Bumped `rexml` (indirect) to `3.3.9`.

---

## 2024-10-18 Update Tools

- ruby 3.3.4
- bundler
- inspec and cinc-auditor-bin
- nodejs
- update Gemfile & rebuild Gemfile.lock
- update terraform-docs
- hashicorp tools (e.g. terraform 1.9.4)
- replaced tfenv with tenv (tenv also supports tofu, terragrunt)
- added xorriso, yq, golang & go-task (experimental support for terratest)
- default python version is 3.12
- update python requirements
- update base OS

---

## 2023-04-28 Update Tools

- ruby 3.2.2
- bundler
- kitchen-terraform
- inspec and cinc-auditor-bin
- hashicorp tools
- nodejs
- default python version is 3.11
- python requirements
- added tflint

---

## 2022-03-15 Initial release
