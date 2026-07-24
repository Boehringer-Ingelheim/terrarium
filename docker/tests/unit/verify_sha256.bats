#!/usr/bin/env bats
# Unit tests for verify_sha256_from_url and verify_sha256_from_checksums.
#
# The verify helpers call `fetch` by bare name, so the fetch fixture-shim
# (fixtures/bin/fetch, first on PATH) serves the checksum documents from local
# fixtures — no network. The artifact itself is a local file (as in production,
# it is already downloaded before verification).

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  PATH="$BATS_TEST_DIRNAME/fixtures/bin:$BIN:$PATH"
  export PATH
  export FIXTURE_DIR="$BATS_TEST_TMPDIR/fx"; mkdir -p "$FIXTURE_DIR"
  ART="$BATS_TEST_TMPDIR/art"; printf 'terrarium-artifact\n' > "$ART"
  SUM="$(sha256sum "$ART" | awk '{print $1}')"
  BAD="$(printf '0%.0s' $(seq 1 64))"   # 64 zeros — a valid-shape wrong sum
}

# ---- verify_sha256_from_url -------------------------------------------------

@test "from_url: matching sum passes" {
  printf '%s\n' "$SUM" > "$FIXTURE_DIR/sha"
  run verify_sha256_from_url https://x.test/sha "$ART"
  [ "$status" -eq 0 ]
}

@test "from_url: mismatching sum fails" {
  printf '%s\n' "$BAD" > "$FIXTURE_DIR/sha"
  run verify_sha256_from_url https://x.test/sha "$ART"
  [ "$status" -ne 0 ]
}

@test "from_url: tolerates 'hex *name' binary-mode form (awk takes field 1)" {
  printf '%s *art\n' "$SUM" > "$FIXTURE_DIR/sha"
  run verify_sha256_from_url https://x.test/sha "$ART"
  [ "$status" -eq 0 ]
}

@test "from_url: unmapped URL hits the shim's fail-closed guard (no network)" {
  run verify_sha256_from_url https://x.test/not-a-fixture "$ART"
  [ "$status" -ne 0 ]
}

# ---- verify_sha256_from_checksums -------------------------------------------

@test "from_checksums: matching entry passes" {
  printf '%s  art\n' "$SUM" > "$FIXTURE_DIR/checksums"
  run verify_sha256_from_checksums https://x.test/checksums "$ART"
  [ "$status" -eq 0 ]
}

@test "from_checksums: missing entry exits 1 (the guard absent in from_url)" {
  printf '%s  some-other-file\n' "$SUM" > "$FIXTURE_DIR/checksums"
  run verify_sha256_from_checksums https://x.test/checksums "$ART"
  [ "$status" -eq 1 ]
}

@test "from_checksums: present but mismatching entry fails" {
  printf '%s  art\n' "$BAD" > "$FIXTURE_DIR/checksums"
  run verify_sha256_from_checksums https://x.test/checksums "$ART"
  [ "$status" -ne 0 ]
}

@test "from_checksums: tolerates 'hex *name' binary-mode form" {
  printf '%s *art\n' "$SUM" > "$FIXTURE_DIR/checksums"
  run verify_sha256_from_checksums https://x.test/checksums "$ART"
  [ "$status" -eq 0 ]
}
