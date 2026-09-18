#!/usr/bin/env bats
# Unit tests for verify_gpg_signed_checksums and verify_gpg_detached.
#
# A throwaway key is generated per run into $BATS_TEST_TMPDIR/gnupg; standalone
# keyrings (keybox) are built by export+import, matching how import_vendor_key
# writes /opt/keys/gpg/*.gpg in production. The `fetch` fixture-shim serves the
# checksum/signature documents — no network. Nothing is written outside
# $BATS_TEST_TMPDIR.

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  PATH="$BATS_TEST_DIRNAME/fixtures/bin:$BIN:$PATH"
  export PATH
  export FIXTURE_DIR="$BATS_TEST_TMPDIR/fx"; mkdir -p "$FIXTURE_DIR"

  export GNUPGHOME="$BATS_TEST_TMPDIR/gnupg"
  install -d -m 0700 "$GNUPGHOME"

  # Signing key (trusted) and a second, unrelated key (for the wrong-keyring path).
  FPR="$(gen_key "$GNUPGHOME" 'Terrarium Test <t@test>')"
  KEYRING="$BATS_TEST_TMPDIR/trusted.gpg"
  make_keyring "$GNUPGHOME" "$FPR" "$KEYRING"

  OTHERHOME="$BATS_TEST_TMPDIR/other"; install -d -m 0700 "$OTHERHOME"
  OFPR="$(gen_key "$OTHERHOME" 'Other <o@test>')"
  WRONG_KEYRING="$BATS_TEST_TMPDIR/wrong.gpg"
  make_keyring "$OTHERHOME" "$OFPR" "$WRONG_KEYRING"

  ART="$BATS_TEST_TMPDIR/art"; printf 'terrarium-artifact\n' > "$ART"
  SUM="$(sha256sum "$ART" | awk '{print $1}')"

  # Signed checksums doc: "<sum>  art", detached-signed with the trusted key.
  printf '%s  art\n' "$SUM" > "$FIXTURE_DIR/sums.txt"
  sign_detached "$GNUPGHOME" "$FIXTURE_DIR/sums.txt" "$FIXTURE_DIR/sums.txt.sig"
  # Detached signature over the artifact itself.
  sign_detached "$GNUPGHOME" "$ART" "$FIXTURE_DIR/art.sig"
}

gen_key() { # <homedir> <uid> -> prints primary fingerprint
  gpg --homedir "$1" --batch --pinentry-mode loopback --passphrase '' \
      --quick-generate-key "$2" default default never >/dev/null 2>&1
  gpg --homedir "$1" --batch --with-colons --list-keys \
    | awk -F: '/^fpr:/{print $10; exit}'
}

make_keyring() { # <homedir> <fpr> <out-keyring>
  gpg --homedir "$1" --batch --yes --export "$2" > "$BATS_TEST_TMPDIR/pub.tmp"
  gpg --no-default-keyring --keyring "$3" --batch --yes \
      --import "$BATS_TEST_TMPDIR/pub.tmp" >/dev/null 2>&1
}

sign_detached() { # <homedir> <file> <out-sig>
  gpg --homedir "$1" --batch --yes --pinentry-mode loopback --passphrase '' \
      --detach-sign -o "$3" "$2" >/dev/null 2>&1
}

# ---- verify_gpg_signed_checksums --------------------------------------------

@test "signed_checksums: valid signature + matching sum passes" {
  run verify_gpg_signed_checksums "$KEYRING" https://x.test/sums.txt https://x.test/sums.txt.sig "$ART"
  [ "$status" -eq 0 ]
}

@test "signed_checksums: tampered artifact fails (sig ok, sha mismatch)" {
  printf 'tampered\n' > "$ART"
  run verify_gpg_signed_checksums "$KEYRING" https://x.test/sums.txt https://x.test/sums.txt.sig "$ART"
  [ "$status" -ne 0 ]
}

@test "signed_checksums: wrong keyring fails (signature not trusted)" {
  run verify_gpg_signed_checksums "$WRONG_KEYRING" https://x.test/sums.txt https://x.test/sums.txt.sig "$ART"
  [ "$status" -ne 0 ]
}

@test "signed_checksums: missing .sig (unmapped URL) fails closed" {
  run verify_gpg_signed_checksums "$KEYRING" https://x.test/sums.txt https://x.test/absent.sig "$ART"
  [ "$status" -ne 0 ]
}

# ---- verify_gpg_detached ----------------------------------------------------

@test "detached: valid detached signature passes" {
  run verify_gpg_detached "$KEYRING" "$ART" https://x.test/art.sig
  [ "$status" -eq 0 ]
}

@test "detached: tampered artifact fails" {
  printf 'tampered\n' > "$ART"
  run verify_gpg_detached "$KEYRING" "$ART" https://x.test/art.sig
  [ "$status" -ne 0 ]
}

@test "detached: wrong keyring fails" {
  run verify_gpg_detached "$WRONG_KEYRING" "$ART" https://x.test/art.sig
  [ "$status" -ne 0 ]
}

@test "detached: GNUPGHOME empty still verifies (exercises the \${GNUPGHOME:+} branch)" {
  # With GNUPGHOME empty the helper omits --homedir; redirect HOME into tmpdir
  # so gpg's default homedir stays hermetic. gpg creates $HOME/.gnupg but needs
  # $HOME itself to exist first. Verification uses the explicit keyring regardless.
  mkdir -p "$BATS_TEST_TMPDIR/home"
  HOME="$BATS_TEST_TMPDIR/home" GNUPGHOME="" run verify_gpg_detached "$KEYRING" "$ART" https://x.test/art.sig
  [ "$status" -eq 0 ]
}
