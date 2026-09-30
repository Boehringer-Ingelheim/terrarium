#!/usr/bin/env bats
# Unit tests for scripts/check-pin-freshness.sh (INFIAAS-9587).
#
# Hermetic: curl is the stub in fixtures/bin/ (recorded Go JSON, Rocky index,
# and a UBI tag set for the manifest probes); jq is real. Each test writes its
# own minimal Dockerfile, so the suite does not move when the real pins do.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../check-pin-freshness.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures/pin-freshness"
  PATH="$BATS_TEST_DIRNAME/fixtures/bin:$PATH"
  export PATH
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_LOG"
  export STUB_CURL_GO_JSON="$FIX/go-current.json"        # supported: 1.26, 1.27
  export STUB_CURL_ROCKY_HTML="$FIX/rocky-index.html"    # newest 9.x: 9.8
  export STUB_CURL_UBI_TAGS="9.6 9.7 9.8"                # newest UBI9: 9.8
  export PIN_FRESHNESS_ALLOWLIST="$BATS_TEST_TMPDIR/allowlist.txt"; : > "$PIN_FRESHNESS_ALLOWLIST"
  export PIN_FRESHNESS_TODAY=2026-09-30
  unset STUB_CURL_FAIL STUB_CURL_PROBE_CODE STUB_CURL_PROBE_CODES
  DF="$BATS_TEST_TMPDIR/Dockerfile"
  pins 1.26.8 9.8 9.8
}

# pins <GO_VERSION> <ROCKYLINUX_VERSION> <UBI9_VERSION>
pins() {
  printf 'ARG ROCKYLINUX_VERSION=%s\nARG UBI9_VERSION=%s\nARG GO_VERSION=%s\nFROM scratch\n' \
    "$2" "$3" "$1" > "$DF"
}

allow() { printf '%s\n' "$*" >> "$PIN_FRESHNESS_ALLOWLIST"; }

# ---- current pins ------------------------------------------------------------

@test "current: all three pins fresh -> exit 0" {
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: GO_VERSION=1.26.8 (supported: 1.26 1.27)"* ]]
  [[ "$output" == *"ok: ROCKYLINUX_VERSION=9.8 (newest: 9.8)"* ]]
  [[ "$output" == *"ok: UBI9_VERSION=9.8 (no 9.9 yet)"* ]]
}

@test "current: the other supported Go major (1.27) also passes" {
  pins 1.27.1 9.8 9.8
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
}

@test "current: a two-part GO_VERSION (1.26) is accepted" {
  pins 1.26 9.8 9.8
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
}

@test "current: the UBI probes hit the pinned tag and the next minor" {
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
  grep -q 'manifests/9.8$' "$STUB_LOG"
  grep -q 'manifests/9.9$' "$STUB_LOG"
}

# ---- stale pins --------------------------------------------------------------

@test "stale: GO_VERSION=1.21.13 (unsupported major) fails" {
  pins 1.21.13 9.8 9.8
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PIN FRESHNESS FAIL: GO_VERSION=1.21.13 is stale (supported: 1.26 1.27)"* ]]
}

@test "stale: a patch of an old major does not pass on prefix (1.2.6 vs 1.26)" {
  pins 1.2.6 9.8 9.8
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
}

@test "stale: ROCKYLINUX_VERSION=9.3 fails" {
  pins 1.26.8 9.3 9.8
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PIN FRESHNESS FAIL: ROCKYLINUX_VERSION=9.3 is stale (newest: 9.8)"* ]]
}

@test "stale: Rocky newest is chosen by version, not text (9.10 > 9.8)" {
  sed 's#<a href="9.8/">9.8/</a>#&\n<a href="9.10/">9.10/</a>#' "$FIX/rocky-index.html" > "$BATS_TEST_TMPDIR/r.html"
  export STUB_CURL_ROCKY_HTML="$BATS_TEST_TMPDIR/r.html"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ROCKYLINUX_VERSION=9.8 is stale (newest: 9.10)"* ]]
}

@test "stale: Rocky 10.x does not count as newer than 9.x" {
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
  [[ "$output" != *"newest: 10"* ]]
}

@test "stale: UBI9_VERSION=9.5 fails when 9.6 exists" {
  pins 1.26.8 9.8 9.5
  export STUB_CURL_UBI_TAGS="9.5 9.6 9.7 9.8"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PIN FRESHNESS FAIL: UBI9_VERSION=9.5 is stale (newer minor 9.6 exists)"* ]]
}

@test "stale: a UBI9_VERSION tag that does not exist fails" {
  pins 1.26.8 9.8 9.42
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UBI9_VERSION=9.42 is stale (tag 9.42 does not exist)"* ]]
}

@test "stale: every stale pin is reported, not just the first" {
  pins 1.21.13 9.3 9.5
  export STUB_CURL_UBI_TAGS="9.5 9.6"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
  [ "$(grep -c 'PIN FRESHNESS FAIL' <<<"$output")" -eq 3 ]
}

# ---- allowlist ---------------------------------------------------------------

@test "allowlist: a live entry turns the failure into a warning (exit 0)" {
  pins 1.26.8 9.3 9.8
  allow "ROCKYLINUX_VERSION 2026-12-31 9.9 breaks pyenv, see INFIAAS-1"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: ROCKYLINUX_VERSION=9.3 is stale (newest: 9.8); allowlisted until 2026-12-31: 9.9 breaks pyenv, see INFIAAS-1"* ]]
}

@test "allowlist: the expiry day itself still passes" {
  pins 1.21.13 9.8 9.8
  allow "GO_VERSION 2026-09-30 last day"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: GO_VERSION"* ]]
}

@test "allowlist: an expired entry fails again" {
  pins 1.21.13 9.8 9.8
  allow "GO_VERSION 2026-09-29 expired yesterday"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"allowlist entry EXPIRED 2026-09-29"* ]]
}

@test "allowlist: an entry only covers its own pin" {
  pins 1.21.13 9.3 9.8
  allow "ROCKYLINUX_VERSION 2026-12-31 deliberate"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN: ROCKYLINUX_VERSION"* ]]
  [[ "$output" == *"PIN FRESHNESS FAIL: GO_VERSION"* ]]
}

@test "allowlist: comments and blank lines are ignored" {
  printf '# header\n\n   \nGO_VERSION 2026-12-31 lag  # trailing comment\n' > "$PIN_FRESHNESS_ALLOWLIST"
  pins 1.21.13 9.8 9.8
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
}

@test "allowlist: an unknown ARG name is an error (exit 2), not a silent no-op" {
  allow "TERRAFORM_VERSION 2026-12-31 ODS agents"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"'TERRAFORM_VERSION' is not a checked pin"* ]]
}

@test "allowlist: a malformed expiry is an error (exit 2)" {
  allow "GO_VERSION 31.12.2026 bad date"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"expiry must be YYYY-MM-DD"* ]]
}

@test "allowlist: an entry without a reason is an error (exit 2)" {
  allow "GO_VERSION 2026-12-31"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"a reason is required"* ]]
}

@test "allowlist: a missing allowlist file is fine" {
  export PIN_FRESHNESS_ALLOWLIST="$BATS_TEST_TMPDIR/does-not-exist"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 0 ]
}

# ---- network / parse failures: a clear error, never a false pass --------------

@test "network: curl failing everywhere exits 2 with a clear message" {
  export STUB_CURL_FAIL=1
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot fetch"*"refusing to pass"* ]]
}

@test "network: a UBI probe error (HTTP 000) exits 2, not 'tag missing' (1)" {
  export STUB_CURL_PROBE_CODE=000
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unexpected HTTP status '000'"* ]]
  [[ "$output" != *"does not exist"* ]]
}

@test "network: an error probing only the PINNED tag exits 2" {
  export STUB_CURL_PROBE_CODES="9.8=000"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"probing"*"manifests/9.8"* ]]
}

@test "network: an error probing only the NEXT minor exits 2 (not 'fresh')" {
  export STUB_CURL_PROBE_CODES="9.9=502"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"probing"*"manifests/9.9"* ]]
}

@test "network: a registry 5xx exits 2" {
  export STUB_CURL_PROBE_CODE=503
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
}

@test "network: a registry 401 exits 2 (auth change must not read as 'missing')" {
  export STUB_CURL_PROBE_CODE=401
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
}

@test "parse: Go JSON with no stable releases exits 2" {
  printf '[{"version":"go1.28rc1","stable":false}]' > "$BATS_TEST_TMPDIR/go.json"
  export STUB_CURL_GO_JSON="$BATS_TEST_TMPDIR/go.json"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no stable Go releases parsed"* ]]
}

@test "parse: non-JSON Go response (captive portal) exits 2" {
  printf '<html>login</html>' > "$BATS_TEST_TMPDIR/go.json"
  export STUB_CURL_GO_JSON="$BATS_TEST_TMPDIR/go.json"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
}

@test "parse: a Rocky index with no 9.x entries exits 2" {
  printf '<a href="10.1/">10.1/</a>\n' > "$BATS_TEST_TMPDIR/r.html"
  export STUB_CURL_ROCKY_HTML="$BATS_TEST_TMPDIR/r.html"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no Rocky 9.x releases parsed"* ]]
}

# ---- usage -------------------------------------------------------------------

@test "usage: a missing Dockerfile exits 2" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  [ ! -s "$STUB_LOG" ]
}

@test "usage: a missing GO_VERSION ARG exits 2" {
  printf 'ARG ROCKYLINUX_VERSION=9.8\nARG UBI9_VERSION=9.8\n' > "$DF"
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ARG GO_VERSION not found"* ]]
}

@test "usage: a malformed UBI9_VERSION exits 2" {
  pins 1.26.8 9.8 latest
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UBI9_VERSION 'latest' is not 9.N"* ]]
}

@test "usage: a malformed PIN_FRESHNESS_TODAY exits 2" {
  export PIN_FRESHNESS_TODAY=yesterday
  run "$SCRIPT" "$DF"
  [ "$status" -eq 2 ]
}

@test "real Dockerfile: the repository pins parse (network stubbed)" {
  run "$SCRIPT" "$BATS_TEST_DIRNAME/../../docker/Dockerfile.terrarium"
  [ "$status" -ne 2 ]
}
