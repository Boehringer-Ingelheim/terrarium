#!/usr/bin/env bats
# Unit tests for the kitchen + cinc-auditor bundle-exec wrappers.
#
# These wrappers `exec` an ABSOLUTE path (/opt/rbenv/shims/bundle), so a fully
# hermetic behavioural test cannot run the real file (that path does not, and
# must not, exist in the hermetic `helpers` stage). Coverage is therefore:
#   - structural: shebang, syntax, the two pinned BUNDLE_* exports, exec line;
#   - behavioural: a tmpdir COPY with the absolute bundle path redirected to a
#     stub, proving env-export + "$@" arg pass-through without touching /opt.
# End-to-end behaviour of the real wrappers stays covered by the image-level
# 50_ruby_ecosystem.bats and the build-time `kitchen --version` smoke check.

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  PATH="$BATS_TEST_DIRNAME/fixtures/bin:$BIN:$PATH"
  export PATH
}

# Resolve a helper's file path: host -> docker/files/bin; helpers stage -> the
# copy on PATH (/usr/local/bin).
helper_path() {
  if [ -f "$BIN/$1" ]; then printf '%s' "$BIN/$1"; else command -v "$1"; fi
}

# ---- structural assertions (run against the real, unmodified file) ----------

assert_structure() { # <name> <tool>
  local name="$1" tool="$2" f
  f="$(helper_path "$name")"
  [ -n "$f" ] && [ -f "$f" ]                    # exists
  [ -x "$f" ]                                   # executable
  head -n1 "$f" | grep -q '^#!/usr/bin/env bash'
  bash -n "$f"                                  # valid syntax
  grep -qxF 'export BUNDLE_GEMFILE=/opt/terrarium-gems/Gemfile' "$f"
  grep -qxF 'export BUNDLE_PATH=/opt/bundle' "$f"
  grep -qxF "exec /opt/rbenv/shims/bundle exec ${tool} \"\$@\"" "$f"
}

@test "kitchen: structure (shebang, syntax, BUNDLE_* exports, exec line)" {
  assert_structure kitchen kitchen
}

@test "cinc-auditor: structure (shebang, syntax, BUNDLE_* exports, exec line)" {
  assert_structure cinc-auditor cinc-auditor
}

# ---- behavioural: env-export + arg pass-through via a stubbed bundle ---------

# Copy the wrapper into tmpdir, redirect the absolute bundle path to a recorder
# stub, run it, and assert what bundle would have received.
run_with_stub() { # <name>  ...args
  local name="$1"; shift
  local src copy stub log
  src="$(helper_path "$name")"
  copy="$BATS_TEST_TMPDIR/${name}.copy"
  stub="$BATS_TEST_TMPDIR/bundle-stub"
  log="$BATS_TEST_TMPDIR/${name}.log"

  # Recorder stub: capture argv and the two BUNDLE_* env values, then exit 0.
  cat >"$stub" <<STUB
#!/usr/bin/env bash
{ echo "ARGS: \$*"; echo "GEMFILE: \${BUNDLE_GEMFILE:-}"; echo "PATH: \${BUNDLE_PATH:-}"; } > "$log"
STUB
  chmod +x "$stub"

  # Redirect only the absolute bundle path to the stub; nothing else changes.
  sed "s#/opt/rbenv/shims/bundle#$stub#g" "$src" > "$copy"
  chmod +x "$copy"
  "$copy" "$@"
  cat "$log"
}

@test "kitchen: passes args through and exports the pinned BUNDLE_* env" {
  run run_with_stub kitchen --config foo -x
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARGS: exec kitchen --config foo -x"* ]]
  [[ "$output" == *"GEMFILE: /opt/terrarium-gems/Gemfile"* ]]
  [[ "$output" == *"PATH: /opt/bundle"* ]]
}

@test "cinc-auditor: passes args through and exports the pinned BUNDLE_* env" {
  run run_with_stub cinc-auditor exec --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARGS: exec cinc-auditor exec --version"* ]]
  [[ "$output" == *"GEMFILE: /opt/terrarium-gems/Gemfile"* ]]
  [[ "$output" == *"PATH: /opt/bundle"* ]]
}
