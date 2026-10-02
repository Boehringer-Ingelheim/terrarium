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

# nano replaces vi/vim-minimal (INFIAAS-9587).
@test "nano is installed" { check_binary nano; }

# With vi gone, `git commit` / `visudo` need EDITOR to name a real command. The
# image defaults it to nano; a consumer override (e.g. `code --wait`) is fine as
# long as its command exists, so the suite stays valid in live devcontainers.
@test "EDITOR and VISUAL resolve to an installed command" {
  for var in EDITOR VISUAL; do
    run bash -lc 'cmd="${'"$var"'%% *}"; [ -n "$cmd" ] && command -v "$cmd"'
    assert_success
  done
}
