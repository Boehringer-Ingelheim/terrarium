#!/usr/bin/env bats
# Structural tests for the tenv GitHub-token wiring (INFIAAS-11804).
#
# `tenv tofu install` resolves OpenTofu releases through api.github.com, which
# allows 60 anonymous requests/hour/IP; shared CI runner IPs hit that and failed
# the v4.9.1-pre release. CI now hands a dedicated read-only token
# (secrets.TENV_GITHUB_TOKEN) to that one command as a BuildKit secret.
# These tests pin the security properties: every CI build passes the secret,
# only the tofu install sees it, it never becomes an ARG/ENV (layer, cache key,
# image), it is never echoed, and GITHUB_TOKEN is never used for it.
# Hermetic: reads repo files only (grep/awk).

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  WF="$ROOT/.github/workflows"
  DF="$ROOT/docker/Dockerfile.terrarium"
  MK="$ROOT/Makefile"
}

# step <file> <step-name regex>: print one workflow step (from its `- name:`
# line up to, not including, the next step or job).
step() {
  awk -v re="$2" '
    !ins && $0 ~ "- name: " re { ins=1; match($0, /^ */); ind=RLENGTH; print; next }
    ins { match($0, /^ */); if ($0 !~ /^ *$/ && RLENGTH <= ind) exit; print }
  ' "$1"
}

# tenv_run: print the Dockerfile RUN instruction that installs tenv.
tenv_run() {
  awk '
    /^RUN / { buf=""; inrun=1 }
    inrun { buf = buf $0 "\n" }
    inrun && $0 !~ /\\[ \t]*$/ { inrun=0; if (buf ~ /tenv tofu install/) { printf "%s", buf; exit } }
  ' "$DF"
}

@test "workflows: every docker buildx build passes the tenv_github_token secret" {
  for f in "$WF/main.yaml" "$WF/release.yaml"; do
    builds=$(grep -c 'docker buildx build' "$f")
    secrets=$(grep -c -- '--secret id=tenv_github_token,env=TENV_GITHUB_TOKEN \\' "$f")
    [ "$builds" -eq 2 ] || { echo "$f: expected 2 buildx builds, got $builds" >&2; return 1; }
    [ "$secrets" -eq "$builds" ] || { echo "$f: $secrets secrets for $builds builds" >&2; return 1; }
  done
}

@test "workflows: each build step sources TENV_GITHUB_TOKEN from the dedicated repo secret" {
  for f in "$WF/main.yaml" "$WF/release.yaml"; do
    for s in 'Build & run tests' 'Build & push final image'; do
      b="$(step "$f" "$s")"
      [[ "$b" == *'--secret id=tenv_github_token,env=TENV_GITHUB_TOKEN'* ]] || { echo "$f/$s: no --secret" >&2; return 1; }
      [[ "$b" == *'TENV_GITHUB_TOKEN: ${{ secrets.TENV_GITHUB_TOKEN }}'* ]] || { echo "$f/$s: no env" >&2; return 1; }
    done
  done
}

@test "workflows: GITHUB_TOKEN is never passed into a build (login-action scoping holds)" {
  # no build secret is sourced from GITHUB_TOKEN ...
  run grep -nE -- '--secret .*env=GITHUB_TOKEN' "$WF/main.yaml" "$WF/release.yaml"
  [ "$status" -ne 0 ]
  # ... and every TENV_GITHUB_TOKEN env entry comes from the dedicated secret
  run bash -c "grep -hE '^ +TENV_GITHUB_TOKEN:' '$WF/main.yaml' '$WF/release.yaml' | grep -vF 'TENV_GITHUB_TOKEN: \${{ secrets.TENV_GITHUB_TOKEN }}'"
  [ -z "$output" ] || { echo "unexpected token source: $output" >&2; return 1; }
  [ "$(grep -cE '^ +TENV_GITHUB_TOKEN:' "$WF/main.yaml" "$WF/release.yaml" | awk -F: '{s+=$2} END {print s}')" -eq 4 ]
}

@test "workflows and Makefile: the token is never used as a --build-arg" {
  run grep -nE -- '--build-arg .*GITHUB_TOKEN' "$WF/main.yaml" "$WF/release.yaml" "$MK"
  [ "$status" -ne 0 ]
}

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

@test "Makefile: the secret is only added when TENV_GITHUB_TOKEN is set" {
  run grep -n -A1 'ifneq ($(strip $(TENV_GITHUB_TOKEN)),)' "$MK"
  [ "$status" -eq 0 ]
  [[ "$output" == *'DOCKER_BUILD_OPTS_BASE += --secret id=tenv_github_token,env=TENV_GITHUB_TOKEN'* ]]
}

@test "negative: a build without the secret flag is detected" {
  t="$BATS_TEST_TMPDIR/main.yaml"
  sed '0,/--secret id=tenv_github_token,env=TENV_GITHUB_TOKEN \\/{//d}' "$WF/main.yaml" > "$t"
  builds=$(grep -c 'docker buildx build' "$t")
  secrets=$(grep -c -- '--secret id=tenv_github_token,env=TENV_GITHUB_TOKEN \\' "$t")
  [ "$secrets" -lt "$builds" ]
}
