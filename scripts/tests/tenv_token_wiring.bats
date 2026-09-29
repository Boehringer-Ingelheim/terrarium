#!/usr/bin/env bats
# Structural tests for the tenv GitHub-token wiring (INFIAAS-11804).
#
# `tenv tofu install` resolves OpenTofu releases through api.github.com, which
# allows 60 anonymous requests/hour/IP; shared CI runner IPs hit that and failed
# the v4.9.1-pre release. CI now hands the job's GITHUB_TOKEN to that one
# command as a BuildKit secret. Because tenv is third-party code, the jobs that
# pass the token must not hold contents:write (repo/tag tampering), and the
# tenv RPM must be verified before it runs. These tests pin those properties.
# Hermetic: reads repo files only (grep/awk).

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  WF="$ROOT/.github/workflows"
  MAIN="$WF/main.yaml"
  REL="$WF/release.yaml"
  DF="$ROOT/docker/Dockerfile.terrarium"
  MK="$ROOT/Makefile"
}

# step <file> <step-name regex>: print one workflow step (its `- name:` line and
# everything indented deeper).
step() {
  awk -v re="$2" '
    !ins && $0 ~ "- name: " re { ins=1; match($0, /^ */); ind=RLENGTH; print; next }
    ins { match($0, /^ */); if ($0 !~ /^ *$/ && RLENGTH <= ind) exit; print }
  ' "$1"
}

# job <file> <job-id>: print one job block (the `  <id>:` line under `jobs:`
# and everything indented deeper, until the next job). Searching only after
# `jobs:` matters: release.yaml also has `  release:` as an `on:` trigger.
job() {
  awk -v id="$2" '
    /^jobs:/ { injobs=1; next }
    injobs && !inj && $0 ~ "^  " id ":[[:space:]]*$" { inj=1; print; next }
    inj && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { exit }
    inj && /^[^ #]/ { exit }
    inj { print }
  ' "$1"
}

# job_ids <file>: list the job ids under `jobs:`.
job_ids() {
  awk '/^jobs:/ {j=1; next} j && /^[^ #]/ {j=0} j && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {sub(/:.*/, ""); sub(/^  /, ""); print}' "$1"
}

# tenv_run: print the Dockerfile RUN instruction that installs tenv.
tenv_run() {
  awk '
    /^RUN / { buf=""; inrun=1 }
    inrun { buf = buf $0 "\n" }
    inrun && $0 !~ /\\[ \t]*$/ { inrun=0; if (buf ~ /tenv tofu install/) { printf "%s", buf; exit } }
  ' "$DF"
}

# ── workflows: the token reaches every build ─────────────────────────────────

@test "workflows: every docker buildx build passes the tenv_github_token secret" {
  for f in "$MAIN" "$REL"; do
    builds=$(grep -c 'docker buildx build' "$f")
    secrets=$(grep -c -- '--secret id=tenv_github_token,env=TENV_GITHUB_TOKEN \\' "$f")
    [ "$builds" -eq 2 ] || { echo "$f: expected 2 buildx builds, got $builds" >&2; return 1; }
    [ "$secrets" -eq "$builds" ] || { echo "$f: $secrets secrets for $builds builds" >&2; return 1; }
  done
}

@test "workflows: each build step sources TENV_GITHUB_TOKEN from the job's GITHUB_TOKEN" {
  for f in "$MAIN" "$REL"; do
    for s in 'Build & run tests' 'Build & push final image'; do
      b="$(step "$f" "$s")"
      [[ "$b" == *'--secret id=tenv_github_token,env=TENV_GITHUB_TOKEN'* ]] || { echo "$f/$s: no --secret" >&2; return 1; }
      [[ "$b" == *'TENV_GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}'* ]] || { echo "$f/$s: no env" >&2; return 1; }
    done
  done
  [ "$(grep -chE '^ +TENV_GITHUB_TOKEN:' "$MAIN" "$REL" | awk '{s+=$1} END {print s}')" -eq 4 ]
}

@test "workflows and Makefile: the token is never used as a --build-arg" {
  run grep -nE -- '--build-arg .*GITHUB_TOKEN' "$MAIN" "$REL" "$MK"
  [ "$status" -ne 0 ]
}

# ── workflows: least privilege for the jobs that hand the token to tenv ──────

@test "permissions: no job that runs a build holds contents:write" {
  for f in "$MAIN" "$REL"; do
    for id in $(job_ids "$f"); do
      b="$(job "$f" "$id")"
      [[ "$b" == *'docker buildx build'* ]] || continue
      [[ "$b" == *'contents: read'* ]] || { echo "$f/$id: builds without contents: read" >&2; return 1; }
      [[ "$b" != *'contents: write'* ]] || { echo "$f/$id: builds WITH contents: write" >&2; return 1; }
    done
  done
}

@test "permissions: in release.yaml only the tag and release-assets jobs hold contents:write" {
  holders=""
  for id in $(job_ids "$REL"); do
    [[ "$(job "$REL" "$id")" == *'contents: write'* ]] && holders+="$id "
  done
  [ "$holders" = "tag release-assets " ] || { echo "contents:write holders: '$holders'" >&2; return 1; }
}

@test "release.yaml: the tag job creates the tag; the build checks it out and never pushes git refs" {
  t="$(job "$REL" tag)"
  [[ "$t" == *'git push origin "refs/tags/${TAG}"'* ]]
  [[ "$t" == *'echo "tag=${TAG}" >> "$GITHUB_OUTPUT"'* ]]
  [[ "$t" != *'docker buildx build'* ]]
  r="$(job "$REL" release)"
  [[ "$r" == *'needs: [tag]'* ]]
  [[ "$r" == *'ref: refs/tags/${{ needs.tag.outputs.tag }}'* ]]
  # no git ref writes as commands (comments may mention "git tag")
  run grep -nE '^[[:space:]]+(git (push|tag)|.*&& *git (push|tag))\b' <<<"$r"
  [ "$status" -ne 0 ]
}

@test "release.yaml: SBOMs are attached by release-assets, after the builds, from the run's artifacts" {
  a="$(job "$REL" release-assets)"
  [[ "$a" == *'needs: [tag, release]'* ]]
  [[ "$a" == *'permissions: { contents: write, actions: read }'* ]]
  [[ "$a" == *'gh run download "$RUN_ID" --name "sbom-${ARCH}"'* ]]
  [[ "$a" == *'gh release upload "$TAG"'* ]]
  # dispatch cuts have no GitHub Release: skip cleanly, never fail
  [[ "$a" == *'No GitHub Release for ${TAG} (dispatch cut)'* ]]
  [[ "$a" != *'docker buildx build'* ]]
  # and the build job no longer uploads to the Release itself
  [[ "$(job "$REL" release)" != *'gh release upload'* ]]
}

# ── Dockerfile ───────────────────────────────────────────────────────────────

@test "Dockerfile: the tenv RUN mounts the secret, optional (forks and local builds still work)" {
  r="$(tenv_run)"
  [ -n "$r" ]
  [[ "$r" == 'RUN --mount=type=secret,id=tenv_github_token,required=false '* ]]
}

@test "Dockerfile: only the tofu install receives the token; anonymous fallback when absent" {
  r="$(tenv_run)"
  [[ "$r" == *'if [ -s /run/secrets/tenv_github_token ]; then'* ]]
  [[ "$r" == *'TENV_GITHUB_TOKEN="$(cat /run/secrets/tenv_github_token)" tenv tofu install ${OPENTOFU_VERSION}; \'* ]]
  [[ "$r" == *'else tenv tofu install ${OPENTOFU_VERSION}; fi'* ]]
  # the secret file is touched twice (the -s test and one cat), and the token
  # is not exported to the other commands in the RUN
  [ "$(grep -o '/run/secrets/tenv_github_token' <<<"$r" | wc -l)" -eq 2 ]
  [[ "$r" != *'export TENV_GITHUB_TOKEN'* ]]
}

@test "Dockerfile: the token is never an ARG or ENV (not in layers, cache key or image)" {
  run grep -nE '^(ARG|ENV)\b.*GITHUB_TOKEN' "$DF"
  [ "$status" -ne 0 ]
  run grep -nE '^[[:space:]]+(TENV_)?GITHUB_TOKEN=\$\{' "$DF"
  [ "$status" -ne 0 ]
}

@test "Dockerfile: the token is never echoed or traced" {
  r="$(tenv_run)"
  # no line that prints (echo/printf) also touches the token or the secret file
  run grep -E '(echo|printf).*(TENV_GITHUB_TOKEN|/run/secrets/tenv_github_token)' <<<"$r"
  [ "$status" -ne 0 ]
  # no shell tracing, and the secret is only ever read into the env assignment
  [[ "$r" != *'set -x'* ]]
  [ "$(grep -c 'cat /run/secrets/tenv_github_token' <<<"$r")" -eq 1 ]
  grep -qF 'TENV_GITHUB_TOKEN="$(cat /run/secrets/tenv_github_token)" tenv tofu install' <<<"$r"
}

@test "Dockerfile: the tenv RPM is SHA-256-verified before it is installed" {
  r="$(tenv_run)"
  # never installed straight from a URL
  [[ "$r" != *'dnf -y install "https://'* ]]
  # fetch -> verify against the release checksums -> install the verified file
  f=$(grep -n 'fetch -o "$TENV_RPM"' <<<"$r" | cut -d: -f1)
  v=$(grep -n 'verify_sha256_from_checksums "${TENV_BASE}/tenv_v${TENV_VERSION}_checksums.txt" "$TENV_RPM"' <<<"$r" | cut -d: -f1)
  i=$(grep -n 'dnf -y install "$TENV_RPM"' <<<"$r" | cut -d: -f1)
  [ -n "$f" ] && [ -n "$v" ] && [ -n "$i" ]
  [ "$f" -lt "$v" ] && [ "$v" -lt "$i" ]
}

# ── Makefile ─────────────────────────────────────────────────────────────────

@test "Makefile: the secret is only added when TENV_GITHUB_TOKEN is set" {
  run grep -n -A1 'ifneq ($(strip $(TENV_GITHUB_TOKEN)),)' "$MK"
  [ "$status" -eq 0 ]
  [[ "$output" == *'DOCKER_BUILD_OPTS_BASE += --secret id=tenv_github_token,env=TENV_GITHUB_TOKEN'* ]]
}

# ── self-tests of the helpers ────────────────────────────────────────────────

@test "negative: a build without the secret flag is detected" {
  t="$BATS_TEST_TMPDIR/main.yaml"
  sed '0,/--secret id=tenv_github_token,env=TENV_GITHUB_TOKEN \\/{//d}' "$MAIN" > "$t"
  builds=$(grep -c 'docker buildx build' "$t")
  secrets=$(grep -c -- '--secret id=tenv_github_token,env=TENV_GITHUB_TOKEN \\' "$t")
  [ "$secrets" -lt "$builds" ]
}

@test "helpers: job_ids sees every job (guards a silently empty loop)" {
  [ "$(job_ids "$MAIN" | tr '\n' ' ')" = "build manifest " ]
  [ "$(job_ids "$REL" | tr '\n' ' ')" = "tag release release-assets manifest scan " ]
}
