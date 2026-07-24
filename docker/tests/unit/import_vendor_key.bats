#!/usr/bin/env bats
# Unit tests for import_vendor_key <name> <fpr> <primary> <fallback> <out_asc> <out_ring>.
#
# The helper fetches a PGP public key (via the `fetch` shim — no network),
# imports it into a disposable keyring, and only promotes it to <out_ring> if
# the imported key contains the pinned fingerprint. Throwaway keys per run;
# nothing outside $BATS_TEST_TMPDIR.

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  PATH="$BATS_TEST_DIRNAME/fixtures/bin:$BIN:$PATH"
  export PATH
  export FIXTURE_DIR="$BATS_TEST_TMPDIR/fx"; mkdir -p "$FIXTURE_DIR"
  export GNUPGHOME="$BATS_TEST_TMPDIR/gnupg"; install -d -m 0700 "$GNUPGHOME"

  # The pinned ("good") key and an unrelated ("wrong") key, both valid & armored.
  FPR="$(gen_key "$GNUPGHOME" 'Good Vendor <good@test>')"
  gpg --homedir "$GNUPGHOME" --batch --yes --armor --export "$FPR" > "$FIXTURE_DIR/good.asc"

  OTHERHOME="$BATS_TEST_TMPDIR/other"; install -d -m 0700 "$OTHERHOME"
  OFPR="$(gen_key "$OTHERHOME" 'Wrong Vendor <wrong@test>')"
  gpg --homedir "$OTHERHOME" --batch --yes --armor --export "$OFPR" > "$FIXTURE_DIR/wrong.asc"

  OUT_ASC="$BATS_TEST_TMPDIR/out/key.asc"
  OUT_RING="$BATS_TEST_TMPDIR/out/ring.gpg"
}

gen_key() { # <homedir> <uid> -> prints primary fingerprint
  gpg --homedir "$1" --batch --pinentry-mode loopback --passphrase '' \
      --quick-generate-key "$2" default default never >/dev/null 2>&1
  gpg --homedir "$1" --batch --with-colons --list-keys \
    | awk -F: '/^fpr:/{print $10; exit}'
}

@test "wrong arity exits 2" {
  run import_vendor_key only three args
  [ "$status" -eq 2 ]
}

@test "primary yields the pinned fingerprint: keyring written, exit 0" {
  run import_vendor_key vendor "$FPR" https://x.test/good.asc https://x.test/wrong.asc "$OUT_ASC" "$OUT_RING"
  [ "$status" -eq 0 ]
  [ -f "$OUT_RING" ]
}

@test "primary fetch fails, fallback yields the pin: exit 0, keyring written" {
  run import_vendor_key vendor "$FPR" https://x.test/absent.asc https://x.test/good.asc "$OUT_ASC" "$OUT_RING"
  [ "$status" -eq 0 ]
  [ -f "$OUT_RING" ]
}

@test "neither source yields the pin: exit 1 and out_ring is NOT created (promote-only-on-match)" {
  # primary fetch-fails; fallback imports cleanly but is the WRONG key.
  run import_vendor_key vendor "$FPR" https://x.test/absent.asc https://x.test/wrong.asc "$OUT_ASC" "$OUT_RING"
  [ "$status" -eq 1 ]
  [ ! -e "$OUT_RING" ]
}

@test "a different VALID key that imports cleanly is rejected (exit 1, no promotion)" {
  run import_vendor_key vendor "$FPR" https://x.test/wrong.asc https://x.test/wrong.asc "$OUT_ASC" "$OUT_RING"
  [ "$status" -eq 1 ]
  [ ! -e "$OUT_RING" ]
}
