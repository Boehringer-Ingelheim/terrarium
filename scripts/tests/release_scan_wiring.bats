#!/usr/bin/env bats
# Structural tests for the release image scan (INFIAAS-11804 Phase 4).
#
# release.yaml calls scan.yaml (workflow_call) after its manifest job, so the
# exact published <ver>-linux-<arch> image is scanned for dispatch cuts and UI
# releases alike. The old `release: published` trigger never fired for dispatch
# cuts and raced the build. Hermetic: reads repo files only (grep/awk).

setup() {
  WF="$BATS_TEST_DIRNAME/../../.github/workflows"
  SCAN="$WF/scan.yaml"
  REL="$WF/release.yaml"
}

# block <file> <top-level-or-job key regex> — print the YAML block under a key
# (the key line plus every following line indented deeper than it).
block() {
  awk -v re="$2" '
    !inb && $0 ~ re { inb=1; match($0, /^ */); ind=RLENGTH; print; next }
    inb { match($0, /^ */); if ($0 !~ /^ *$/ && RLENGTH <= ind) exit; print }
  ' "$1"
}

@test "scan.yaml: callable with a required string image-tag input" {
  b="$(block "$SCAN" '^  workflow_call:')"
  [[ "$b" == *"image-tag:"* ]]
  [[ "$b" == *"type: string"* ]]
  [[ "$b" == *"required: true"* ]]
}

@test "scan.yaml: the racy 'release: published' trigger is gone" {
  on="$(block "$SCAN" '^on:')"
  [[ "$on" != *"  release:"* ]]
}

@test "scan.yaml: the pull uses the release tag when called, latest-<arch> otherwise" {
  b="$(block "$SCAN" 'name: Try to pull published image')"
  [[ "$b" == *'RELEASE_TAG: ${{ inputs.image-tag }}'* ]]
  [[ "$b" == *'TAG="${RELEASE_TAG}-${{ matrix.suffix }}"'* ]]
  [[ "$b" == *'TAG="latest-${{ matrix.suffix }}"'* ]]
}

@test "scan.yaml: a release scan fails hard if the image can't be pulled (no silent fs fallback)" {
  b="$(block "$SCAN" 'name: Fail if the released image could not be pulled')"
  [[ "$b" == *"if: inputs.image-tag != '' && steps.pull.outcome != 'success'"* ]]
  [[ "$b" == *"exit 1"* ]]
}

@test "scan.yaml: the table step is informational only (exit-code 0)" {
  b="$(block "$SCAN" 'name: Trivy image findings [(]table')"
  [[ "$b" == *'format: table'* ]]
  [[ "$b" == *'exit-code: "0"'* ]]
}

@test "scan.yaml: the gating image scan still fails on findings (exit-code 1)" {
  b="$(block "$SCAN" 'name: Trivy image scan$')"
  [[ "$b" == *'exit-code: "1"'* ]]
}

@test "release.yaml: a scan job calls scan.yaml after the manifest with the published tag" {
  b="$(block "$REL" '^  scan:')"
  [[ "$b" == *"uses: ./.github/workflows/scan.yaml"* ]]
  [[ "$b" == *"needs: [manifest]"* ]]
  [[ "$b" == *'image-tag: ${{ needs.manifest.outputs.image_tag }}'* ]]
  [[ "$b" == *"security-events: write"* ]]
}

@test "release.yaml: the manifest job exports the v-less image tag it published" {
  b="$(block "$REL" '^  manifest:')"
  [[ "$b" == *'image_tag: ${{ steps.resolve.outputs.image_tag }}'* ]]
}
