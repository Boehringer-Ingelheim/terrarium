#!/usr/bin/env bats

load 'test_helper/common.bash'

# bats file_tags=python

# PYTHON_VERSION comes from the image ENV (INFIAAS-11916). Up to 4.8.3 it was
# only a build ARG, so "$PYTHON_VERSION" was empty and `--partial ""` matched
# any output: the version check passed vacuously.
@test "PYTHON_VERSION is set in the image ENV (guards the checks below)" {
  [ -n "${PYTHON_VERSION:-}" ] || fail "PYTHON_VERSION is not set in the image ENV"
  [[ "$PYTHON_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "PYTHON_VERSION='${PYTHON_VERSION}' is not X.Y.Z"
}

@test "python matches PYTHON_VERSION (the global interpreter)" {
  [ -n "${PYTHON_VERSION:-}" ] || fail "PYTHON_VERSION is not set in the image ENV"
  run python --version
  assert_success
  assert_output "Python ${PYTHON_VERSION}"
}

@test "the pyenv interpreter for PYTHON_VERSION exists and is the global one" {
  [ -n "${PYTHON_VERSION:-}" ] || fail "PYTHON_VERSION is not set in the image ENV"
  [ -x "/opt/pyenv/versions/${PYTHON_VERSION}/bin/python" ] || fail "no /opt/pyenv/versions/${PYTHON_VERSION}"
  run pyenv global
  assert_success
  assert_output "${PYTHON_VERSION}"
}

# The pip pin is a build ARG only (PIP_VERSION, INFIAAS-11916 A-02/A-07): an
# ENV in the PIP_* namespace would be read by pip as configuration. The exact
# floor is asserted independently in 15_ca_distrust.bats (PIP_FLOOR).
@test "pip is the same pinned version in the pyenv interpreter and in /opt/openstack" {
  [ -n "${PYTHON_VERSION:-}" ] || fail "PYTHON_VERSION is not set in the image ENV"
  run "/opt/pyenv/versions/${PYTHON_VERSION}/bin/python" -c 'import pip; print(pip.__version__)'
  assert_success
  pyenv_pip="$output"
  [[ "$pyenv_pip" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "unexpected pip version '${pyenv_pip}'"
  run /opt/openstack/bin/python -c 'import pip; print(pip.__version__)'
  assert_success
  assert_output "$pyenv_pip"
}

@test "no pip configuration leaks in from the image ENV (A-07)" {
  run pip config list
  assert_success
  refute_output --partial ":env:"
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
