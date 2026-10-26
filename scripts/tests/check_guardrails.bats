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

@test "latest: an unconditional value=latest fails" {
  wf main.yaml "$PINNED"
  printf '          tags: |\n            type=raw,value=latest\n' >> "$WF_DIR/main.yaml"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: unguarded latest = 1"* ]]
}

@test "latest: value=latest gated on move_latest, computed by is-highest-release.sh, passes" {
  wf main.yaml "$PINNED"
  latest_rules main.yaml "type=raw,value=latest,enable=\${{ steps.rel.outputs.move_latest == 'true' }}" \
    "type=semver,pattern={{major}},enable=\${{ steps.rel.outputs.move_latest == 'true' }}" \
    "type=semver,pattern={{major}}.{{minor}}" "type=raw,value=latest,enable={{is_default_branch}}"
  run "$GUARD" "$DF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: unguarded latest = 0"* ]]
  [[ "$output" == *"ok: latest not via highest-release guard = 0"* ]]
  [[ "$output" == *"ok: major not via highest-release guard = 0"* ]]
  [[ "$output" == *"ok: move_latest without guard script = 0"* ]]
}

# ---- INFIAAS-11916 (S1.6): latest/{{major}} only for the highest release ----------

# latest_rules <file> <rule>... — append a metadata step with these tag rules
# and a step that computes move_latest with the guard script.
latest_rules() {
  local f="$1"; shift
  printf '      - id: rel\n        run: move_latest="$(scripts/is-highest-release.sh "$GITHUB_REF_NAME")"\n' >> "$WF_DIR/$f"
  printf '      - uses: docker/metadata-action@%s # v6\n        with:\n          flavor: latest=false\n          tags: |\n' "$SHA40" >> "$WF_DIR/$f"
  local r; for r in "$@"; do printf '            %s\n' "$r" >> "$WF_DIR/$f"; done
}

# meta_step <file> <flavor line or empty> — a metadata step (semver + guarded
# latest) followed by another step, so the step boundary is exercised.
meta_step() {
  printf '      - id: rel\n        run: move_latest="$(scripts/is-highest-release.sh "$GITHUB_REF_NAME")"\n' >> "$WF_DIR/$1"
  printf '      - name: Generate manifest tags\n        id: meta\n        uses: docker/metadata-action@%s # v6\n        with:\n          images: ghcr.io/x/y\n' "$SHA40" >> "$WF_DIR/$1"
  [ -z "$2" ] || printf '          %s\n' "$2" >> "$WF_DIR/$1"
  printf '          tags: |\n            type=semver,pattern={{version}}\n            type=raw,value=latest,enable=${{ steps.rel.outputs.move_latest == %s }}\n' "'true'" >> "$WF_DIR/$1"
  printf '      - name: Create and push manifest\n        uses: int128/docker-manifest-create-action@%s # v2\n        with:\n          flavor: latest=false\n' "$SHA40" >> "$WF_DIR/$1"
}

@test "A-01: a metadata-action step with no flavor fails (default latest=auto would add latest via type=semver)" {
  wf main.yaml "$PINNED"
  meta_step main.yaml ""
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: metadata-action without latest=false = 1"* ]]
}

@test "A-01: a metadata-action step with flavor latest=auto fails" {
  wf main.yaml "$PINNED"
  meta_step main.yaml "flavor: latest=auto"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: metadata-action without latest=false = 1"* ]]
}

@test "A-01: a metadata-action step with flavor latest=false (with or without suffix) passes" {
  for fl in "flavor: latest=false" "flavor: latest=false,suffix=-linux-amd64"; do
    wf main.yaml "$PINNED"
    meta_step main.yaml "$fl"
    run "$GUARD" "$DF"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok: metadata-action without latest=false = 0"* ]]
  done
}

@test "A-01: a flavor latest=false in a LATER step does not cover an unflavored metadata step" {
  wf main.yaml "$PINNED"
  meta_step main.yaml ""   # the following step carries flavor: latest=false
  wf release.yaml "$PINNED"; meta_step release.yaml "flavor: latest=false"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: metadata-action without latest=false = 1"* ]]
}

@test "latest: the old pre-release-only gate (is_prerelease == 'false') now fails" {
  wf main.yaml "$PINNED"
  latest_rules main.yaml "type=raw,value=latest,enable=\${{ steps.pre.outputs.is_prerelease == 'false' }}"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: latest not via highest-release guard = 1"* ]]
}

@test "latest: an ungated {{major}} rule fails ({{major}}.{{minor}} is allowed)" {
  wf main.yaml "$PINNED"
  latest_rules main.yaml "type=semver,pattern={{major}}" "type=semver,pattern={{major}}.{{minor}}"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: major not via highest-release guard = 1"* ]]
}

@test "latest: a metadata flavour latest=auto (or true) fails" {
  for v in auto true; do
    wf main.yaml "$PINNED"
    printf '          flavor: latest=%s,suffix=-linux-amd64\n' "$v" >> "$WF_DIR/main.yaml"
    run "$GUARD" "$DF"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GUARDRAIL FAIL: flavor latest=auto|true = 1"* ]]
  done
}

@test "latest: latest=false in the flavour passes" {
  wf main.yaml "$PINNED"
  printf '          flavor: latest=false,suffix=-linux-amd64\n' >> "$WF_DIR/main.yaml"
  run "$GUARD" "$DF"
  [ "$status" -eq 0 ]
}

@test "latest: gating on move_latest in a workflow that never runs the guard script fails" {
  wf main.yaml "$PINNED"
  printf '      - uses: docker/metadata-action@%s # v6\n        with:\n          tags: |\n            type=raw,value=latest,enable=${{ steps.x.outputs.move_latest == %s }}\n' "$SHA40" "'true'" >> "$WF_DIR/main.yaml"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"move_latest used without scripts/is-highest-release.sh"* ]]
  [[ "$output" == *"GUARDRAIL FAIL: move_latest without guard script = 1"* ]]
}

@test "latest: a move_latest gate on 'false' (inverted) fails" {
  wf main.yaml "$PINNED"
  latest_rules main.yaml "type=raw,value=latest,enable=\${{ steps.rel.outputs.move_latest == 'false' }}"
  run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GUARDRAIL FAIL: latest not via highest-release guard = 1"* ]]
}

@test "workflows: a missing WF_DIR is an error, not a silent pass" {
  WF_DIR="$BATS_TEST_TMPDIR/does-not-exist" run "$GUARD" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"workflow dir not found"* ]]
}
