#!/usr/bin/env bats
# Structural tests for the PR CI triggers on maintenance branches (INFIAAS-11916).
#
# PRs into a maintenance branch (release/<major>.<minor>, e.g. release/4.8) must
# run the same build/test (main.yaml) and lint (lint.yaml) gates as PRs into
# master. Hermetic: reads repo files only (awk).

setup() {
  WF="$BATS_TEST_DIRNAME/../../.github/workflows"
}

# pr_branches <workflow> — print the pull_request branch filter line.
pr_branches() {
  awk '
    /^on:/ { on=1; next }
    on && /^[^ ]/ { exit }
    on && /^  pull_request:/ { pr=1; next }
    pr && /^  [^ ]/ { exit }
    pr && /^    branches:/ { print; exit }
  ' "$1"
}

@test "main.yaml: pull_request runs for master" {
  b="$(pr_branches "$WF/main.yaml")"
  [[ "$b" == *"master"* ]]
}

@test "main.yaml: pull_request runs for release/** maintenance branches" {
  b="$(pr_branches "$WF/main.yaml")"
  [[ "$b" == *'"release/**"'* ]]
}

@test "lint.yaml: pull_request runs for master" {
  b="$(pr_branches "$WF/lint.yaml")"
  [[ "$b" == *"master"* ]]
}

@test "lint.yaml: pull_request runs for release/** maintenance branches" {
  b="$(pr_branches "$WF/lint.yaml")"
  [[ "$b" == *'"release/**"'* ]]
}

@test "pr_branches helper: finds no filter in a workflow without pull_request" {
  tmp="$BATS_TEST_TMPDIR/wf.yaml"
  printf 'on:\n  push:\n    branches: [master]\njobs: {}\n' > "$tmp"
  [ -z "$(pr_branches "$tmp")" ]
}
