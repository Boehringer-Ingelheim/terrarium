#!/usr/bin/env bats
# Unit tests for scripts/publish-sbom.sh (INFIAAS-11804).
#
# Hermetic, same rules as docker/tests/unit (bats core only, no network,
# nothing outside $BATS_TEST_TMPDIR). syft/oras/cosign are the stubs in
# fixtures/bin/ — they record argv to $STUB_LOG and fail on demand; jq is real.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../publish-sbom.sh"
  STUBS="$BATS_TEST_DIRNAME/fixtures/bin"
  PATH="$STUBS:$PATH"
  export PATH
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_LOG"
  export PUBLISH_SBOM_BACKOFF=0
  REPO="ghcr.io/boehringer-ingelheim/terrarium"
  DIGEST="sha256:$(printf 'a%.0s' $(seq 1 64))"
  export STUB_SBOM_DIGEST="sha256:$(printf 'b%.0s' $(seq 1 64))"
  OUT="$BATS_TEST_TMPDIR/out"; mkdir -p "$OUT"
  unset GITHUB_STEP_SUMMARY
}

# count <ERE> — number of recorded stub calls matching; never fails (unlike `! grep`,
# which bats does not treat as a failing assertion mid-test).
count() { grep -cE "$1" "$STUB_LOG" || true; }
calls() { count "^$1 "; }
published() { count '^oras (discover|attach) '; }

# ---- argument validation: exit 2, no tool invoked ----------------------------

assert_rejected() {
  [ "$status" -eq 2 ]
  [ ! -s "$STUB_LOG" ]
}

@test "args: wrong argument count exits 2" {
  run "$SCRIPT" "$REPO" "$DIGEST" amd64
  assert_rejected
  [[ "$output" == *usage:* ]]
}

@test "args: uppercase repo is rejected" {
  run "$SCRIPT" ghcr.io/Boehringer-Ingelheim/terrarium "$DIGEST" amd64 "$OUT"
  assert_rejected
}

@test "args: repo carrying a tag is rejected" {
  run "$SCRIPT" "$REPO:4.9.0" "$DIGEST" amd64 "$OUT"
  assert_rejected
}

@test "args: non-GHCR repo is rejected" {
  run "$SCRIPT" docker.io/library/terrarium "$DIGEST" amd64 "$OUT"
  assert_rejected
}

@test "args: malformed digests are rejected (short, uppercase, no prefix)" {
  for d in sha256:abc "sha256:$(printf 'A%.0s' $(seq 1 64))" "$(printf 'a%.0s' $(seq 1 64))"; do
    run "$SCRIPT" "$REPO" "$d" amd64 "$OUT"
    assert_rejected
  done
}

@test "args: unknown arch is rejected" {
  run "$SCRIPT" "$REPO" "$DIGEST" x86_64 "$OUT"
  assert_rejected
}

@test "args: missing output directory is rejected" {
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$BATS_TEST_TMPDIR/nope"
  assert_rejected
}

@test "tools: a missing tool exits 2 and names it" {
  only="$BATS_TEST_TMPDIR/only"; mkdir -p "$only"
  ln -s "$STUBS/syft" "$only/syft"; ln -s "$STUBS/oras" "$only/oras"
  ln -s "$(command -v jq)" "$only/jq"
  PATH="$only" run "$BASH" "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  assert_rejected
  [[ "$output" == *"not on PATH: cosign"* ]]
}

# ---- happy path -----------------------------------------------------------------

@test "happy: scans by digest, attaches SPDX to the digest, signs the SBOM digest" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 0 ]
  # syft: registry source, by digest, both outputs, never a tag
  grep -qxF "syft scan registry:$REPO@$DIGEST -o spdx-json=$OUT/sbom-amd64.spdx.json -o syft-table=$OUT/sbom-amd64.txt" "$STUB_LOG"
  [ -s "$OUT/sbom-amd64.spdx.json" ] && [ -s "$OUT/sbom-amd64.txt" ]
  # oras: discover first, then attach the bare filename from inside $OUT
  grep -qxF "oras discover --format json --artifact-type application/spdx+json $REPO@$DIGEST" "$STUB_LOG"
  grep -qF "oras attach --artifact-type application/spdx+json" "$STUB_LOG"
  grep -qF "$REPO@$DIGEST sbom-amd64.spdx.json:application/spdx+json" "$STUB_LOG"
  grep -qxF "oras-attach-cwd $OUT" "$STUB_LOG"
  # cosign: keyless sign of the SBOM artifact digest, not the image
  grep -qxF "cosign sign --yes $REPO@$STUB_SBOM_DIGEST" "$STUB_LOG"
  [ "$(calls cosign)" -eq 1 ]
  # report
  [[ "$output" == *"$REPO@$DIGEST → sbom $REPO@$STUB_SBOM_DIGEST (2 packages, signed)"* ]]
  grep -qF "SBOM (amd64)" "$GITHUB_STEP_SUMMARY"
  grep -qF "$STUB_SBOM_DIGEST" "$GITHUB_STEP_SUMMARY"
}

@test "happy: arm64 names its outputs per arch" {
  run "$SCRIPT" "$REPO" "$DIGEST" arm64 "$OUT"
  [ "$status" -eq 0 ]
  [ -s "$OUT/sbom-arm64.spdx.json" ] && [ -s "$OUT/sbom-arm64.txt" ]
  grep -qF "sbom-arm64.spdx.json:application/spdx+json" "$STUB_LOG"
}

@test "happy: no GITHUB_STEP_SUMMARY is fine" {
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 0 ]
}

# ---- platform resolution (buildx pushes an index: image + provenance) -------

# index_json <amd64-digest> <arm64-digest> — like a buildx push index plus the
# `unknown/unknown` attestation manifest buildx adds for provenance.
index_json() {
  local m='' a
  for a in "amd64:$1" "arm64:$2"; do
    [ -n "${a#*:}" ] || continue
    m="$m{\"digest\":\"${a#*:}\",\"platform\":{\"os\":\"linux\",\"architecture\":\"${a%%:*}\"}},"
  done
  printf '{"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[%s{"digest":"sha256:%s","platform":{"os":"unknown","architecture":"unknown"}}]}' \
    "$m" "$(printf 'f%.0s' $(seq 1 64))"
}
IMG_A="sha256:$(printf '1%.0s' $(seq 1 64))"
IMG_B="sha256:$(printf '2%.0s' $(seq 1 64))"

@test "platform: a pushed index resolves to the linux/amd64 image manifest" {
  export STUB_ORAS_MANIFEST="$(index_json "$IMG_A" "$IMG_B")"
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 0 ]
  grep -qxF "oras manifest fetch $REPO@$DIGEST" "$STUB_LOG"
  grep -qF "syft scan registry:$REPO@$IMG_A " "$STUB_LOG"
  grep -qxF "oras discover --format json --artifact-type application/spdx+json $REPO@$IMG_A" "$STUB_LOG"
  grep -qF "$REPO@$IMG_A sbom-amd64.spdx.json:application/spdx+json" "$STUB_LOG"
  [ "$(count "^syft .*$DIGEST")" -eq 0 ]
  [[ "$output" == *"Pushed index $DIGEST -> linux/amd64 image $IMG_A"* ]]
}

@test "platform: arm64 picks the arm64 entry, never the attestation manifest" {
  export STUB_ORAS_MANIFEST="$(index_json "$IMG_A" "$IMG_B")"
  run "$SCRIPT" "$REPO" "$DIGEST" arm64 "$OUT"
  [ "$status" -eq 0 ]
  grep -qF "syft scan registry:$REPO@$IMG_B " "$STUB_LOG"
}

@test "platform: a single image manifest is used as-is" {
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 0 ]
  grep -qF "syft scan registry:$REPO@$DIGEST " "$STUB_LOG"
  [[ "$output" != *"Pushed index"* ]]
}

@test "platform: an index without the requested arch fails before scanning" {
  export STUB_ORAS_MANIFEST="$(index_json "" "$IMG_B")"
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no single linux/amd64 image manifest"* ]]
  [ "$(calls syft)" -eq 0 ]
}

@test "platform: an ambiguous index (two linux/amd64 entries) fails" {
  export STUB_ORAS_MANIFEST="$(index_json "$IMG_A" "" | sed "s|\"manifests\":\[|&{\"digest\":\"$IMG_B\",\"platform\":{\"os\":\"linux\",\"architecture\":\"amd64\"}},|")"
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [ "$(calls syft)" -eq 0 ]
}

@test "platform: manifest fetch keeps failing -> exit 1 after 3 attempts, no scan" {
  STUB_ORAS_MANIFEST_FAIL=1 run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [ "$(count '^oras manifest fetch ')" -eq 3 ]
  [ "$(calls syft)" -eq 0 ]
}

# ---- scan / content failures: nothing is published --------------------------

@test "scan: syft failure exits 1; oras and cosign never run" {
  STUB_SYFT_FAIL=1 run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [ "$(published)" -eq 0 ] && [ "$(calls cosign)" -eq 0 ]
}

@test "content: an SBOM with zero packages is refused" {
  STUB_SYFT_SPDX='{"packages":[]}' run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lists no packages"* ]]
  [ "$(published)" -eq 0 ] && [ "$(calls cosign)" -eq 0 ]
}

@test "content: invalid JSON is refused" {
  STUB_SYFT_SPDX='not json' run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [ "$(published)" -eq 0 ]
}

@test "content: SPDX without a packages array is refused" {
  STUB_SYFT_SPDX='{"spdxVersion":"SPDX-2.3"}' run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [ "$(published)" -eq 0 ]
}

# ---- idempotency on re-runs ----------------------------------------------------

@test "rerun: an already-attached SPDX SBOM is reused and signed, not duplicated" {
  existing="sha256:$(printf 'c%.0s' $(seq 1 64))"
  export STUB_ORAS_DISCOVER_JSON="{\"referrers\":[{\"artifactType\":\"application/vnd.dev.cosign.artifact.sig.v1+json\",\"digest\":\"sha256:$(printf 'd%.0s' $(seq 1 64))\"},{\"artifactType\":\"application/spdx+json\",\"digest\":\"$existing\"}]}"
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 0 ]
  [ "$(count '^oras attach ')" -eq 0 ]
  grep -qxF "cosign sign --yes $REPO@$existing" "$STUB_LOG"
  [[ "$output" == *"reusing it"* ]]
}

@test "rerun: referrers of other types do not count as an SBOM" {
  export STUB_ORAS_DISCOVER_JSON="{\"referrers\":[{\"artifactType\":\"application/vnd.in-toto+json\",\"digest\":\"sha256:$(printf 'e%.0s' $(seq 1 64))\"}]}"
  run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 0 ]
  [ "$(count '^oras attach ')" -eq 1 ]
}

# ---- retries -----------------------------------------------------------------------

@test "retry: attach fails twice then succeeds (3 attempts)" {
  STUB_ORAS_ATTACH_FAILS=2 run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 0 ]
  [ "$(count '^oras attach ')" -eq 3 ]
  [ "$(calls cosign)" -eq 1 ]
}

@test "retry: attach fails 3 times -> exit 1, cosign never runs" {
  STUB_ORAS_ATTACH_FAILS=3 run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed after 3 attempts"* ]]
  [ "$(calls cosign)" -eq 0 ]
}

@test "retry: discover keeps failing -> exit 1, nothing attached or signed" {
  STUB_ORAS_DISCOVER_FAIL=1 run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [ "$(count '^oras discover ')" -eq 3 ]
  [ "$(count '^oras attach ')" -eq 0 ]
  [ "$(calls cosign)" -eq 0 ]
}

@test "retry: cosign fails once then succeeds" {
  STUB_COSIGN_FAILS=1 run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 0 ]
  [ "$(calls cosign)" -eq 2 ]
}

@test "retry: cosign fails every attempt -> exit 1" {
  STUB_COSIGN_FAILS=3 run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [ "$(calls cosign)" -eq 3 ]
}

@test "retry: attempts are configurable (PUBLISH_SBOM_ATTEMPTS=1 means no retry)" {
  PUBLISH_SBOM_ATTEMPTS=1 STUB_ORAS_ATTACH_FAILS=1 run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [ "$(count '^oras attach ')" -eq 1 ]
}

# ---- output guard ------------------------------------------------------------------

@test "guard: a non-digest attach result is refused before signing" {
  STUB_ORAS_ATTACH_OUT="Attached to ghcr.io/..." run "$SCRIPT" "$REPO" "$DIGEST" amd64 "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not determine the attached SBOM digest"* ]]
  [ "$(calls cosign)" -eq 0 ]
}
