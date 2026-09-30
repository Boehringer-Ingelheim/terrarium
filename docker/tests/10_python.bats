#!/usr/bin/env bats

load 'test_helper/common.bash'

# bats file_tags=python

@test "Python PYTHON_VERSION is the global interpreter" {
  # PYTHON_VERSION is baked into ENV (INFIAAS-9587); it was ARG-only before,
  # so this assert used to match an empty string and pass vacuously.
  assert_pinned_version PYTHON_VERSION python --version
}

@test "uv CLI is installed" {
  check_binary uv
}

@test "uv is the default Python launcher" {
  run uv --version
  assert_success
  assert_output --partial "uv"
}

@test "pyenv is installed" {
  check_binary pyenv
}

@test "pip is installed" {
  run bash -lc 'pip --version'
  assert_success
}

@test "pre-commit is installed" {
  check_binary pre-commit
}
