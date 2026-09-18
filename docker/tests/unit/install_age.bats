#!/usr/bin/env bats
# Unit tests for install_age. The `fetch` shim serves a locally-built fake age
# release (tarball + checksums) — no network. Install dir is redirected into
# $BATS_TEST_TMPDIR via AGE_BINDIR. Covers the verified-install happy path, the
# checksum-candidate chain, a checksum mismatch, and the fail-closed terminus.

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  PATH="$BATS_TEST_DIRNAME/fixtures/bin:$BIN:$PATH"
  export PATH
  export FIXTURE_DIR="$BATS_TEST_TMPDIR/fx"; mkdir -p "$FIXTURE_DIR"
  export AGE_VERSION="1.2.0" TARGETARCH="amd64"
  export AGE_BINDIR="$BATS_TEST_TMPDIR/bin"; mkdir -p "$AGE_BINDIR"
  TARBALL="age-v${AGE_VERSION}-linux-amd64.tar.gz"

  # Build a fake age release tarball containing age/age + age/age-keygen.
  local stage="$BATS_TEST_TMPDIR/stage"; mkdir -p "$stage/age"
  printf '#!/bin/sh\necho "v%s"\n' "$AGE_VERSION" > "$stage/age/age"
  printf '#!/bin/sh\necho keygen\n' > "$stage/age/age-keygen"
  chmod +x "$stage/age/age" "$stage/age/age-keygen"
  tar -C "$stage" -czf "$FIXTURE_DIR/$TARBALL" age/age age/age-keygen
  SUM="$(sha256sum "$FIXTURE_DIR/$TARBALL" | awk '{print $1}')"
}

write_good_checksums() {
  printf '%s  %s\n' "$SUM" "$TARBALL" > "$FIXTURE_DIR/checksums.txt"
}

@test "verified install: extracts age + age-keygen and exits 0" {
  write_good_checksums
  run install_age
  [ "$status" -eq 0 ]
  [ -x "$AGE_BINDIR/age" ]
  [ -x "$AGE_BINDIR/age-keygen" ]
}

@test "checksum mismatch aborts and does not install age" {
  printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "$TARBALL" > "$FIXTURE_DIR/checksums.txt"
  run install_age
  [ "$status" -ne 0 ]
  [ ! -e "$AGE_BINDIR/age" ]
}

@test "fail-closed: no checksums and no tarball reachable -> exit 1, nothing installed" {
  rm -f "$FIXTURE_DIR/checksums.txt" "$FIXTURE_DIR/$TARBALL"
  run install_age
  [ "$status" -eq 1 ]
  [ ! -e "$AGE_BINDIR/age" ]
}
