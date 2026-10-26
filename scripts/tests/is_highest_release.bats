#!/usr/bin/env bats
# Unit tests for scripts/is-highest-release.sh (INFIAAS-11916, S1.6) and its
# wiring into the workflows. Hermetic: each test builds a throwaway git repo
# whose `origin` is a local bare repo, so `git ls-remote` never reaches the
# network.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../is-highest-release.sh"
  WF="$BATS_TEST_DIRNAME/../../.github/workflows"
  # Isolate from the user's and system git config (hooks, signing, default branch).
  export HOME="$BATS_TEST_TMPDIR/home" GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  mkdir -p "$HOME"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q "$REPO"
  git -C "$REPO" commit -q --allow-empty -m init
  git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
  git -C "$REPO" remote add origin "$BATS_TEST_TMPDIR/origin.git"
  cd "$REPO"
}

# Tags that exist both locally and on origin, like a full clone.
tags_both() { local t; for t; do git tag "$t"; git push -q origin "refs/tags/$t"; done; }
# Tags that exist only on origin, like a CI checkout (shallow, no tags).
tags_remote() { local t; for t; do git tag "$t"; git push -q origin "refs/tags/$t"; git tag -d "$t" >/dev/null; done; }
# Tags that exist only locally, e.g. created but not pushed yet.
tags_local() { local t; for t; do git tag "$t"; done; }

highest() { run --separate-stderr "$SCRIPT" "$1"; }

# ---- the scenarios from plan.md (NEW-S1.6) ---------------------------------------

@test "plan: v4.8.4 when v4.9.6 exists is not the highest (a maintenance release must not move latest)" {
  tags_both v4.8.3 v4.8.4 v4.9.5 v4.9.6
  highest v4.8.4
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
  [[ "$stderr" == *"not the highest release (v4.9.6)"* ]]
}

@test "plan: v4.9.6 is the highest" {
  tags_both v4.8.4 v4.9.5 v4.9.6
  highest v4.9.6
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  [ -z "$stderr" ]
}

@test "plan: v4.9.6-pre is not a release, even as the newest tag" {
  tags_both v4.9.5 v4.9.6-pre
  highest v4.9.6-pre
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "plan: v4.10.0 when v4.9.10 exists is the highest (two-digit minor, version sort not lexical)" {
  tags_both v4.9.9 v4.9.10 v4.10.0
  highest v4.10.0
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  highest v4.9.10
  [ "$output" = "false" ]
}

# ---- ordering edge cases ----------------------------------------------------------

@test "order: two-digit patch v4.9.10 beats v4.9.9" {
  tags_both v4.9.9 v4.9.10
  highest v4.9.10
  [ "$output" = "true" ]
  highest v4.9.9
  [ "$output" = "false" ]
}

@test "order: a newer pre-release (v4.10.0-pre) does not dethrone the highest release" {
  tags_both v4.9.6 v4.10.0-pre v4.10.0-rc.1
  highest v4.9.6
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "order: a new major wins (v5.0.0 over v4.99.99)" {
  tags_both v4.99.99 v5.0.0
  highest v5.0.0
  [ "$output" = "true" ]
  highest v4.99.99
  [ "$output" = "false" ]
}

@test "order: non-semver tags (latest, v1.0, vfoo) are ignored, not fatal" {
  tags_both v4.9.6 latest v1.0 vfoo v9.9
  highest v4.9.6
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ---- tag sources: local, remote, union -------------------------------------------

@test "sources: CI shape, where tags exist only on origin and the shallow checkout has none" {
  tags_remote v4.8.4 v4.9.6
  [ -z "$(git tag -l)" ]
  highest v4.9.6
  [ "$output" = "true" ]
  highest v4.8.4
  [ "$output" = "false" ]
}

@test "sources: a higher tag only on origin still wins over local tags" {
  tags_both v4.9.6
  tags_remote v4.9.7
  highest v4.9.6
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "sources: a fresh local tag not yet pushed is recognised" {
  tags_both v4.9.5
  tags_local v4.9.6
  highest v4.9.6
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "sources: HIGHEST_RELEASE_REMOTE selects the remote" {
  git init -q --bare "$BATS_TEST_TMPDIR/other.git"
  git remote add other "$BATS_TEST_TMPDIR/other.git"
  tags_both v4.9.6
  git tag v4.9.9 && git push -q other refs/tags/v4.9.9 && git tag -d v4.9.9 >/dev/null
  highest v4.9.6
  [ "$output" = "true" ]
  HIGHEST_RELEASE_REMOTE=other run --separate-stderr "$SCRIPT" v4.9.6
  [ "$output" = "false" ]
}

# ---- fail closed: exit 2, no decision --------------------------------------------

@test "missing: a release tag that exists neither locally nor on origin exits 2" {
  tags_both v4.9.5
  highest v4.9.6
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"exists neither locally nor on origin"* ]]
}

@test "missing: no stable tag at all (only pre-releases) exits 2" {
  tags_both v4.9.6-pre
  highest v4.9.6
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no stable vX.Y.Z tag found"* ]]
}

@test "missing: an empty repository exits 2" {
  highest v4.9.6
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no stable vX.Y.Z tag found"* ]]
}

@test "git: an unreachable remote exits 2 instead of guessing from local tags" {
  tags_both v4.9.6
  HIGHEST_RELEASE_REMOTE=does-not-exist run --separate-stderr "$SCRIPT" v4.9.6
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"git ls-remote --tags does-not-exist failed"* ]]
}

@test "git: outside a git checkout exits 2" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p not-a-repo && cd not-a-repo
  highest v4.9.6
  [ "$status" -eq 2 ]
}

@test "invalid: malformed tags exit 2 (delegated to is-prerelease.sh)" {
  tags_both v4.9.6
  for t in 4.9.6 v4.9 V4.9.6 "v4.9.6 " 'v4.9.6;id' ""; do
    highest "$t"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
  done
}

@test "invalid: no argument or two arguments exit 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  run "$SCRIPT" v4.9.6 v4.9.5
  [ "$status" -eq 2 ]
}

@test "output: exactly one word on stdout for every decision" {
  tags_both v4.8.4 v4.9.6
  for t in v4.9.6 v4.8.4 v4.9.7-pre; do
    highest "$t"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == true || "$output" == false ]]
  done
}

# ---- wiring ------------------------------------------------------------------------

@test "wiring: main.yaml and release.yaml compute move_latest with scripts/is-highest-release.sh" {
  # Count invocations, not comments: build + manifest jobs in main.yaml, manifest in release.yaml.
  [ "$(grep -cF '="$(scripts/is-highest-release.sh "' "$WF/main.yaml")" -eq 2 ]
  [ "$(grep -cF '="$(scripts/is-highest-release.sh "' "$WF/release.yaml")" -eq 1 ]
}

@test "wiring: every tag-driven latest and the {{major}} rule enable only on move_latest == 'true'" {
  run grep -hE 'value=latest,enable=\$\{\{|pattern=\{\{major\}\},' "$WF/main.yaml" "$WF/release.yaml"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]   # main: per-arch latest, {{major}}, manifest latest; release: manifest latest
  for l in "${lines[@]}"; do [[ "$l" == *"outputs.move_latest == 'true' }}"* ]]; done
}

@test "wiring: no metadata flavour adds latest on its own (latest=auto|true)" {
  run grep -nE 'flavor:.*latest=(auto|true)' "$WF/main.yaml" "$WF/release.yaml"
  [ "$status" -eq 1 ]
}
