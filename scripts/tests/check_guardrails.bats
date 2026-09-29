#!/usr/bin/env bats
# Tests for the "buildkit pinned" guardrail in scripts/check-guardrails.sh
# (INFIAAS-11804). The Dockerfile checks run against the real Dockerfile
# (read-only); the workflow checks run against fixture workflows via WF_DIR.

setup() {
  GUARD="$BATS_TEST_DIRNAME/../check-guardrails.sh"
  DF="$BATS_TEST_DIRNAME/../../docker/Dockerfile.terrarium"
  export WF_DIR="$BATS_TEST_TMPDIR/wf"; mkdir -p "$WF_DIR"
  export ACTIONS_DIR="$BATS_TEST_TMPDIR/actions"; mkdir -p "$ACTIONS_DIR/x"
  SHA40="$(printf 'a%.0s' $(seq 1 40))"
  SHA64="$(printf 'b%.0s' $(seq 1 64))"
}

# wf <file> <driver-opts line or empty> — a workflow with one pinned buildx setup
wf() {
  {
    printf 'jobs:\n  b:\n    steps:\n'
    printf '      - uses: docker/setup-buildx-action@%s # v4\n' "$SHA40"
    if [ -n "$2" ]; then printf '        with:\n          %s\n' "$2"; fi
  } > "$WF_DIR/$1"
}

PINNED="driver-opts: image=moby/buildkit:v0.33.0@sha256:$(printf 'b%.0s' $(seq 1 64))"

@test "buildkit: tag@digest pin in every setup passes" {
  wf main.yaml "$PINNED"; wf release.yaml "$PINNED"
  run "$GUARD" "$DF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: buildkit pinned = 2 (-eq 2)"* ]]
}

@test "buildkit: a setup without driver-opts fails" {
  wf main.yaml "$PINNED"; wf release.yaml ""
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: buildkit pinned = 1, expected -eq 2"* ]]
}

@test "buildkit: a tag-only image (no digest) fails" {
  wf main.yaml "driver-opts: image=moby/buildkit:v0.33.0"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: buildkit pinned"* ]]
}

@test "buildkit: the floating buildx-stable-1 tag fails" {
  wf main.yaml "driver-opts: image=moby/buildkit:buildx-stable-1"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
}

@test "buildkit: digest without a version tag fails (tag keeps the pin reviewable)" {
  wf main.yaml "driver-opts: image=moby/buildkit@sha256:$SHA64"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
}

@test "buildkit: no buildx setup at all fails (guards a wrong WF_DIR reading 0 == 0)" {
  printf 'jobs: {}\n' > "$WF_DIR/empty.yaml"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: buildx setups = 0"* ]]
}

@test "workflows: an unpinned action in the fixture dir still fails (WF_DIR is honoured)" {
  wf main.yaml "$PINNED"
  printf '      - uses: actions/checkout@v4\n' >> "$WF_DIR/main.yaml"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: unpinned actions = 1"* ]]
}

@test "actions: an unpinned action inside a local composite action fails" {
  wf main.yaml "$PINNED"
  printf 'runs:\n  using: composite\n  steps:\n    - uses: sigstore/cosign-installer@v4\n' > "$ACTIONS_DIR/x/action.yml"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: unpinned actions = 1"* ]]
}

@test "actions: SHA-pinned composite actions and local ./ refs pass" {
  wf main.yaml "$PINNED"
  printf 'runs:\n  using: composite\n  steps:\n    - uses: sigstore/cosign-installer@%s # v4\n    - uses: ./.github/actions/other\n' "$SHA40" > "$ACTIONS_DIR/x/action.yml"
  run "$GUARD" "$DF"
  [ "$status" -eq 0 ]
}

@test "actions: a missing ACTIONS_DIR is fine (no local actions)" {
  wf main.yaml "$PINNED"
  ACTIONS_DIR="$BATS_TEST_TMPDIR/none" run "$GUARD" "$DF"
  [ "$status" -eq 0 ]
}

@test "workflows: a missing WF_DIR is an error, not a silent pass" {
  WF_DIR="$BATS_TEST_TMPDIR/does-not-exist" run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"workflow dir not found"* ]]
}
