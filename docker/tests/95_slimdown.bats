#!/usr/bin/env bats
load 'test_helper/common.bash'

# bats file_tags=slimdown
# Negative assertions: verify build-time deps and docs were removed from the
# final image to keep it slim. Positive tool tests live in their domain files.

# --- Build deps removed (compiler toolchain should NOT be present) -----------

@test "gcc is removed (build-dep cleanup)" {
  run bash -lc 'command -v gcc'
  assert_failure
}

@test "g++ is removed (build-dep cleanup)" {
  run bash -lc 'command -v g++'
  assert_failure
}

@test "cpp is removed (build-dep cleanup)" {
  run bash -lc 'command -v cpp'
  assert_failure
}

# --- Ruby toolchain removed (INFIAAS-11797) ----------------------------------
# Ruby, rbenv, bundler, test-kitchen and cinc-auditor/InSpec were dropped in
# 4.9.0. Checked in a login shell so /etc/profile.d PATH additions count too.

@test "Ruby toolchain binaries are absent (ruby rbenv bundle bundler gem kitchen cinc-auditor inspec)" {
  for exe in ruby rbenv bundle bundler gem kitchen cinc-auditor inspec; do
    run bash -lc "command -v $exe"
    assert_failure
  done
}

@test "Ruby toolchain directories are absent (/opt/rbenv /opt/bundle /opt/terrarium-gems)" {
  for d in /opt/rbenv /opt/bundle /opt/terrarium-gems; do
    [ ! -e "$d" ] || { echo "Expected $d to be removed" >&2; return 1; }
  done
}

@test "Ruby wrapper scripts are absent from /usr/local/bin" {
  for f in /usr/local/bin/kitchen /usr/local/bin/cinc-auditor; do
    [ ! -e "$f" ] || { echo "Expected $f to be removed" >&2; return 1; }
  done
}

@test "No Ruby environment variables are set in a login shell" {
  run bash -lc 'printf "%s|%s|%s|%s|%s\n" "${GEM_HOME:-}" "${RUBY_VERSION:-}" "${BUNDLER_VERSION:-}" "${RBENV_ROOT:-}" "${BUNDLE_SILENCE_ROOT_WARNING:-}"'
  assert_success
  assert_output "||||"
}

@test "PATH has no rbenv or bundle entries (login and interactive shells)" {
  for mode in -lc -ic; do
    run bash "$mode" 'echo "$PATH"'
    assert_success
    refute_output --partial "/opt/rbenv"
    refute_output --partial "/opt/bundle"
  done
}

# --- terraform-config-inspect removed (INFIAAS-11477) -------------------------
# The unmaintained 2022 fork was downloaded without verification and
# had no known consumers. Dropped in 4.9.x; see CHANGELOG for alternatives.

@test "terraform-config-inspect is absent" {
  run bash -lc 'command -v terraform-config-inspect'
  assert_failure
  [ ! -e /usr/local/bin/terraform-config-inspect ] || { echo "Expected /usr/local/bin/terraform-config-inspect to be removed" >&2; return 1; }
}

@test "TERRAFORM_CONFIG_INSPECT_VERSION is not set in a login shell" {
  run bash -lc 'printf "%s\n" "${TERRAFORM_CONFIG_INSPECT_VERSION-unset}"'
  assert_success
  assert_output "unset"
}

# --- Docs/man pages removed --------------------------------------------------

@test "/usr/share/doc is removed" {
  [ ! -d /usr/share/doc ]
}

@test "/usr/share/man is removed" {
  [ ! -d /usr/share/man ]
}

@test "/usr/share/info is removed" {
  [ ! -d /usr/share/info ]
}
