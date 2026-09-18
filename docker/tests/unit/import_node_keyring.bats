#!/usr/bin/env bats
# Unit tests for import_node_keyring. Throwaway keys per run; the `fetch` shim
# serves the curated keyring / per-fingerprint keys from local fixtures — no
# network. Ring paths and GNUPGHOME are redirected into $BATS_TEST_TMPDIR.
# Covers curated-keyring promotion, the allowlist filter, the empty-keyring
# fail-closed error, and the per-fingerprint fallback path.

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  PATH="$BATS_TEST_DIRNAME/fixtures/bin:$BIN:$PATH"
  export PATH
  export FIXTURE_DIR="$BATS_TEST_TMPDIR/fx"; mkdir -p "$FIXTURE_DIR"
  export GNUPGHOME="$BATS_TEST_TMPDIR/gnupg"; install -d -m 0700 "$GNUPGHOME"
  export NODE_TMP_RING="$BATS_TEST_TMPDIR/rings/node.kbx"
  export NODE_FINAL_RING="$BATS_TEST_TMPDIR/rings/node.gpg"

  FPR="$(gen_key "$GNUPGHOME" 'Good Node <good@node>')"
  OTHERHOME="$BATS_TEST_TMPDIR/other"; install -d -m 0700 "$OTHERHOME"
  XFPR="$(gen_key "$OTHERHOME" 'Extra Node <extra@node>')"

  gpg --homedir "$GNUPGHOME" --batch --yes --export "$FPR" > "$BATS_TEST_TMPDIR/good.pub"
  gpg --homedir "$OTHERHOME" --batch --yes --export "$XFPR" > "$BATS_TEST_TMPDIR/extra.pub"
  # Armored good key for the per-fingerprint fallback fixture (URL basename = FPR).
  gpg --homedir "$GNUPGHOME" --batch --yes --armor --export "$FPR" > "$FIXTURE_DIR/$FPR"
}

gen_key() { # <homedir> <uid> -> prints primary fingerprint
  gpg --homedir "$1" --batch --pinentry-mode loopback --passphrase '' \
      --quick-generate-key "$2" default default never >/dev/null 2>&1
  gpg --homedir "$1" --batch --with-colons --list-keys \
    | awk -F: '/^fpr:/{print $10; exit}'
}

mk_kbx() { # <out.kbx> <pub-file...>  build a keybox from exported public keys
  local out="$1"; shift
  rm -f "$out"
  gpg --no-default-keyring --keyring "$out" --batch --yes --import "$@" >/dev/null 2>&1
}

final_fprs() {
  gpg --no-default-keyring --keyring "$NODE_FINAL_RING" --batch --with-colons \
      --fingerprint 2>/dev/null | awk -F: '/^fpr:/{print $10}'
}

@test "curated keyring: only allowlisted fingerprints are promoted" {
  mk_kbx "$FIXTURE_DIR/pubring.kbx" "$BATS_TEST_TMPDIR/good.pub" "$BATS_TEST_TMPDIR/extra.pub"
  NODE_RELEASE_FPRS="$FPR" run import_node_keyring
  [ "$status" -eq 0 ]
  final_fprs | grep -qxF "$FPR"
  ! final_fprs | grep -qxF "$XFPR"
}

@test "empty keyring: curated has no allowlisted key -> exit 1, final ring empty" {
  mk_kbx "$FIXTURE_DIR/pubring.kbx" "$BATS_TEST_TMPDIR/extra.pub"
  NODE_RELEASE_FPRS="$FPR" run import_node_keyring
  [ "$status" -eq 1 ]
  [ -z "$(final_fprs)" ]
}

@test "fallback path: no curated keyring, per-fingerprint import promotes the pin" {
  # No pubring.kbx fixture -> curated fetch fails -> allowlist fallback.
  NODE_RELEASE_FPRS="$FPR" run import_node_keyring
  [ "$status" -eq 0 ]
  final_fprs | grep -qxF "$FPR"
}
