#!/usr/bin/env bats

load 'test_helper/common.bash'

# bats file_tags=common_dev_tools

# --- Moved from 00_core.bats ------------------------------------------------

@test "jq is installed" {
  check_binary jq
}

@test "GNU parallel is installed" {
  run parallel --version
  assert_success
  assert_output --partial "GNU parallel"
}

# --- Moved from 90_extras.bats ----------------------------------------------

@test "Go is installed" {
  run go version
  assert_success
}

# INFIAAS-11916: the user toolchain is pinned by GO_VERSION (ENV). 4.8 has no
# 02_pinned_versions.bats, so the exact version is asserted here.
@test "go matches GO_VERSION (user toolchain)" {
  [ -n "${GO_VERSION:-}" ] || fail "GO_VERSION is not set in the image ENV"
  run go version
  assert_success
  assert_output --regexp "^go version go${GO_VERSION//./\\.} linux/(amd64|arm64)$"
}

# --- New: common dev tools that previously had no tests ----------------------

@test "make is installed" { check_binary make; }

@test "git is installed" { check_binary git; }

@test "openssl CLI is installed" {
  run openssl version
  assert_success
}

@test "curl is installed" { check_binary curl; }

@test "sudo is installed" { check_binary sudo; }

@test "ripgrep is installed" {
  run rg --version
  assert_success
  assert_output --partial "ripgrep"
}

@test "chsh is installed (util-linux-user)" {
  run chsh --version
  assert_success
}

@test "ca-certificates bundle is present" {
  run test -s /etc/pki/tls/certs/ca-bundle.crt
  assert_success
}
