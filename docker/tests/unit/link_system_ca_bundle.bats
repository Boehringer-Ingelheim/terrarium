#!/usr/bin/env bats
# Unit tests for link_system_ca_bundle (INFIAAS-11916). Hermetic: every path is
# under $BATS_TEST_TMPDIR, no network, bats core only.

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  PATH="$BIN:$PATH"; export PATH
  D="$BATS_TEST_TMPDIR"
  pem() { printf -- '-----BEGIN CERTIFICATE-----\nMIIB%s\n-----END CERTIFICATE-----\n' "$2" > "$1"; }
  SYS="$D/system/ca-bundle.crt"; mkdir -p "$D/system" "$D/gems/a/data" "$D/gems/b"
  pem "$SYS" system
  pem "$D/gems/a/data/cacert.pem" stale-a
  pem "$D/gems/b/ca-bundle.crt" stale-b
}

@test "replaces every vendored bundle with a symlink to the system bundle" {
  run link_system_ca_bundle "$SYS" "$D/gems/a/data/cacert.pem" "$D/gems/b/ca-bundle.crt"
  [ "$status" -eq 0 ]
  for f in "$D/gems/a/data/cacert.pem" "$D/gems/b/ca-bundle.crt"; do
    [ -L "$f" ]
    [ "$(readlink "$f")" = "$SYS" ]
    grep -q MIIBsystem "$f"
  done
  [[ "$output" == *"linked $D/gems/a/data/cacert.pem -> $SYS"* ]]
}

@test "is idempotent: an existing link to the system bundle is a NOTE, not an error" {
  link_system_ca_bundle "$SYS" "$D/gems/b/ca-bundle.crt"
  run link_system_ca_bundle "$SYS" "$D/gems/b/ca-bundle.crt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOTE: $D/gems/b/ca-bundle.crt already links to $SYS"* ]]
}

@test "an unmatched glob (literal path) fails, so a moved bundle cannot be silently skipped" {
  run link_system_ca_bundle "$SYS" "$D/gems/excon-*/data/cacert.pem"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such vendored bundle"* ]]
}

@test "fails before touching anything when a later argument is missing" {
  run link_system_ca_bundle "$SYS" "$D/gems/missing.pem" "$D/gems/b/ca-bundle.crt"
  [ "$status" -eq 1 ]
  [ ! -L "$D/gems/b/ca-bundle.crt" ]
}

@test "refuses a file that holds no PEM certificate" {
  echo "not a bundle" > "$D/gems/b/notes.txt"
  run link_system_ca_bundle "$SYS" "$D/gems/b/notes.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"holds no PEM certificate; refusing"* ]]
  [ -f "$D/gems/b/notes.txt" ] && [ ! -L "$D/gems/b/notes.txt" ]
}

@test "refuses a directory" {
  mkdir "$D/gems/dir.pem"
  run link_system_ca_bundle "$SYS" "$D/gems/dir.pem"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a regular file"* ]]
}

@test "refuses a symlink that points somewhere else" {
  ln -s "$D/gems/a/data/cacert.pem" "$D/gems/other.pem"
  run link_system_ca_bundle "$SYS" "$D/gems/other.pem"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing"* ]]
}

@test "a missing or non-PEM system bundle fails" {
  run link_system_ca_bundle "$D/system/none.crt" "$D/gems/b/ca-bundle.crt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
  echo junk > "$D/system/junk.crt"
  run link_system_ca_bundle "$D/system/junk.crt" "$D/gems/b/ca-bundle.crt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"holds no PEM certificate"* ]]
  [ ! -L "$D/gems/b/ca-bundle.crt" ]
}

@test "usage: fewer than two arguments exits 2" {
  run link_system_ca_bundle "$SYS"
  [ "$status" -eq 2 ]
  run link_system_ca_bundle
  [ "$status" -eq 2 ]
}
