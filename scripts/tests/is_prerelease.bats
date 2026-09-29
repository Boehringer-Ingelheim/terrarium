#!/usr/bin/env bats
# Unit tests for scripts/is-prerelease.sh (INFIAAS-11804, B4) and its wiring
# into the workflows. Hermetic: no network, reads only repo files.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../is-prerelease.sh"
  WF="$BATS_TEST_DIRNAME/../../.github/workflows"
}

classify() { run "$SCRIPT" "$1"; }

# ---- releases -> false ----------------------------------------------------------

@test "release: plain vX.Y.Z is a release" {
  for t in v4.9.0 v0.0.1 v10.20.30 v4.10.0; do
    classify "$t"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
  done
}

# ---- pre-releases -> true -------------------------------------------------------

@test "pre-release: every documented suffix is a pre-release" {
  for t in v4.9.0-pre v4.9.0-pre.1 v4.9.0-alpha.1 v4.9.0-beta.10 v4.9.0-rc.2 v4.9.0-0 v4.9.0-x-y.z; do
    classify "$t"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "pre-release: output is exactly one word, nothing on stderr" {
  run --separate-stderr "$SCRIPT" v4.9.0-pre
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  [ -z "$stderr" ]
}

# ---- fail closed: exit 2, no classification -------------------------------------

@test "invalid: tags without the v prefix are rejected (tagging standard)" {
  for t in 4.9.0 4.9.0-pre V4.9.0; do
    classify "$t"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a v-prefixed semver tag"* ]]
  done
}

@test "invalid: malformed versions are rejected" {
  for t in v4.9 v4.9.0.1 v04.9.0 v4.09.0 v4.9.0- v4.9.0-pre..1 v4.9.0-pre. "v4.9.0+build.1" "v4.9.0-pre+b" vfoo v; do
    classify "$t"
    [ "$status" -eq 2 ]
  done
}

@test "invalid: whitespace and shell metacharacters are rejected" {
  for t in "v4.9.0 " " v4.9.0" $'v4.9.0\n' 'v4.9.0-pre;rm' 'v4.9.0-$(id)' 'v4.9.0-pre/x'; do
    classify "$t"
    [ "$status" -eq 2 ]
  done
}

@test "invalid: empty tag, no argument, or two arguments exit 2" {
  classify ""
  [ "$status" -eq 2 ]
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  run "$SCRIPT" v4.9.0 v4.9.1
  [ "$status" -eq 2 ]
}

# ---- wiring: both workflows use the script and fail closed ----------------------

@test "wiring: main.yaml and release.yaml classify via scripts/is-prerelease.sh" {
  grep -q 'scripts/is-prerelease.sh' "$WF/main.yaml"
  grep -q 'scripts/is-prerelease.sh' "$WF/release.yaml"
}

@test "wiring: the old unanchored -(pre|alpha|beta|rc) regex is gone" {
  run grep -nF -- '-(pre|alpha|beta|rc)' "$WF/main.yaml" "$WF/release.yaml"
  [ "$status" -eq 1 ]
}

@test "wiring: tag-driven latest is enabled only on an explicit 'false' (empty/unknown never moves latest)" {
  run grep -hE 'type=raw,value=latest,enable=\$\{\{' "$WF/main.yaml" "$WF/release.yaml"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  for l in "${lines[@]}"; do [[ "$l" == *"is_prerelease == 'false'"* ]]; done
}
