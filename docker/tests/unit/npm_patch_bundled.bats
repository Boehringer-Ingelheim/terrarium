#!/usr/bin/env bats
# Unit tests for npm_patch_bundled. A stub `npm` (NPM_BIN) builds the "registry"
# tarball locally, so there is no Node and no network. NPM_ROOT points at a fake
# npm install in $BATS_TEST_TMPDIR. Covers the swap, the skip when the bundled
# copy is already new enough, and every fail-closed rule.

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  PATH="$BIN:$PATH"; export PATH
  export NPM_ROOT="$BATS_TEST_TMPDIR/npm"
  mkdir -p "$NPM_ROOT/node_modules"
  bundle undici 6.28.0

  # Stub `npm pack --silent --pack-destination <dir> <name>@<ver>`: packs
  # package/package.json for that name and version (or STUB_NAME/STUB_VERSION,
  # to simulate a registry serving something else) and prints the file name.
  export NPM_BIN="$BATS_TEST_TMPDIR/npm-stub"
  cat > "$NPM_BIN" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
[ "$1 $2 $3" = "pack --silent --pack-destination" ] || { echo "unexpected: $*" >&2; exit 9; }
dest="$4"; spec="$5"; name="${STUB_NAME:-${spec%@*}}"; ver="${STUB_VERSION:-${spec#*@}}"
[ -z "${STUB_FAIL:-}" ] || exit 1
s="$(mktemp -d)"; mkdir -p "$s/package"
printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$name" "$ver" > "$s/package/package.json"
echo "patched" > "$s/package/marker"
tar -C "$s" -czf "$dest/$name-$ver.tgz" package
echo "$name-$ver.tgz"
EOS
  chmod +x "$NPM_BIN"
}

bundle() { # name version
  mkdir -p "$NPM_ROOT/node_modules/$1"
  printf '{\n  "name": "%s",\n  "version": "%s",\n  "main": "index.js"\n}\n' "$1" "$2" \
    > "$NPM_ROOT/node_modules/$1/package.json"
  echo "old" > "$NPM_ROOT/node_modules/$1/marker"
}

version_of() { sed -n 's/.*"version": "\(.*\)".*/\1/p' "$NPM_ROOT/node_modules/$1/package.json"; }

@test "swaps the bundled package for the fixed version" {
  run npm_patch_bundled undici@6.28.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"patched bundled undici 6.28.0 -> 6.28.1"* ]]
  [ "$(version_of undici)" = "6.28.1" ]
  [ "$(cat "$NPM_ROOT/node_modules/undici/marker")" = "patched" ]
}

@test "patches several packages in one call" {
  bundle ip-address 10.5.0
  bundle brace-expansion 5.0.9
  run npm_patch_bundled undici@6.28.1 ip-address@10.7.1 brace-expansion@5.0.11
  [ "$status" -eq 0 ]
  [ "$(version_of undici)" = "6.28.1" ]
  [ "$(version_of ip-address)" = "10.7.1" ]
  [ "$(version_of brace-expansion)" = "5.0.11" ]
}

@test "bundled copy already newer: left alone, NOTE printed, exit 0" {
  bundle undici 6.30.0
  run npm_patch_bundled undici@6.28.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOTE: bundled undici is already 6.30.0"* ]]
  [ "$(version_of undici)" = "6.30.0" ]
  [ "$(cat "$NPM_ROOT/node_modules/undici/marker")" = "old" ]
}

@test "bundled copy equal to the target is not re-installed" {
  run npm_patch_bundled undici@6.28.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOTE:"* ]]
  [ "$(cat "$NPM_ROOT/node_modules/undici/marker")" = "old" ]
}

@test "version compare is numeric, not lexical (6.9.0 < 6.28.1)" {
  bundle undici 6.9.0
  run npm_patch_bundled undici@6.28.1
  [ "$status" -eq 0 ]
  [ "$(version_of undici)" = "6.28.1" ]
}

@test "different major is refused and nothing changes" {
  run npm_patch_bundled undici@7.29.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"different major"* ]]
  [ "$(version_of undici)" = "6.28.0" ]
}

@test "package npm no longer bundles fails the build" {
  run npm_patch_bundled left-pad@1.3.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"npm no longer bundles left-pad"* ]]
}

@test "invalid specs are rejected" {
  for spec in undici "undici@6.28" "undici@latest" "@scope/pkg@1.0.0" "../x@1.0.0"; do
    run npm_patch_bundled "$spec"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid spec"* ]]
  done
}

@test "tarball with the wrong name or version is refused, old copy kept" {
  STUB_VERSION=6.28.2 run npm_patch_bundled undici@6.28.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"contains undici@6.28.2"* ]]
  STUB_NAME=evil run npm_patch_bundled undici@6.28.1
  [ "$status" -eq 1 ]
  [ "$(version_of undici)" = "6.28.0" ]
  [ "$(cat "$NPM_ROOT/node_modules/undici/marker")" = "old" ]
}

@test "npm pack failure fails the build, old copy kept" {
  STUB_FAIL=1 run npm_patch_bundled undici@6.28.1
  [ "$status" -ne 0 ]
  [ "$(version_of undici)" = "6.28.0" ]
}

@test "no arguments is a usage error" {
  run npm_patch_bundled
  [ "$status" -eq 2 ]
}

@test "missing npm install fails" {
  NPM_ROOT="$BATS_TEST_TMPDIR/nope" run npm_patch_bundled undici@6.28.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"no npm install"* ]]
}
