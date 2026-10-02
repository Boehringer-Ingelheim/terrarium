#!/usr/bin/env bats
# Unit tests for scripts/trivy-residuals.sh (INFIAAS-9587): the generator of
# .trivyignore.yaml, and the committed file's shape. Hermetic: fixture JSON
# only, no Trivy, no network.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../trivy-residuals.sh"
  FX="$BATS_TEST_DIRNAME/fixtures/trivy-residuals"
  IGNORE="$BATS_TEST_DIRNAME/../../.trivyignore.yaml"
}

gen() { run --separate-stderr "$SCRIPT" 2026-12-31 "$@"; }

# Number of entries for an id (lines "  - id: <id>").
entries() { grep -c "^  - id: $1\$" <<<"$output" || true; }

@test "usage: missing args, bad date or missing report exit 2" {
  run "$SCRIPT"; [ "$status" -eq 2 ]
  run "$SCRIPT" 2026-12-31; [ "$status" -eq 2 ]
  run "$SCRIPT" 31.12.2026 "$FX/amd64.json"; [ "$status" -eq 2 ]
  run "$SCRIPT" 2026-12-31 "$FX/nope.json"; [ "$status" -eq 2 ]
}

@test "every residual becomes an entry with statement and expiry" {
  gen "$FX/amd64.json"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^  - id: ' <<<"$output")" -eq 6 ]
  [ "$(grep -c '^    statement: "' <<<"$output")" -eq 6 ]
  [ "$(grep -c '^    expired_at: 2026-12-31$' <<<"$output")" -eq 6 ]
}

@test "entries are scoped to exact paths, one entry per CVE across binaries" {
  gen "$FX/amd64.json"
  [ "$(entries CVE-2025-1000)" -eq 1 ]
  grep -qx '      - "usr/bin/tenv"' <<<"$output"
  grep -qx '      - "usr/bin/tofu"' <<<"$output"
  grep -qx '      - "usr/lib64/az/lib/python3.12/site-packages/pyjwt-2.13.0.dist-info/METADATA"' <<<"$output"
}

@test "pathless pip-vendored package is scoped by exact purl, not by id alone" {
  gen "$FX/amd64.json"
  grep -A2 '^  - id: CVE-2025-3000$' <<<"$output" | grep -qx '    purls:'
  grep -qx '      - "pkg:pypi/setuptools@70.3.0"' <<<"$output"
}

@test "arch reports are merged and de-duplicated" {
  gen "$FX/amd64.json" "$FX/arm64.json"
  [ "$status" -eq 0 ]
  [ "$(entries CVE-2025-0001)" -eq 1 ]
  [ "$(grep -cx '      - "usr/local/bin/oc"' <<<"$output")" -eq 2 ]   # CVE-...0001 and ...0002
  grep -q 'aws-lambda-rie-x86_64"$' <<<"$output"
  grep -q 'samcli/local/rapid/aws-lambda-rie-arm64"$' <<<"$output"
}

@test "statements name the vendor release and are YAML-safe" {
  gen "$FX/amd64.json"
  grep -A3 '^  - id: CVE-2025-0001$' <<<"$output" | grep -q 'statement: "oc 4.19.48 is the newest 4.19.z'
  # no unescaped double quote inside a statement
  inner=$(grep '^    statement: ' <<<"$output" | sed 's/^    statement: "//; s/"$//')
  run grep '[^\\]"' <<<"$inner"
  [ "$status" -eq 1 ]
}

@test "findings we can fix ourselves are refused (exit 1, listed on stderr)" {
  gen "$FX/amd64.json" "$FX/fixable.json"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"UNMATCHED: CVE-2026-19534 undici 6.28.0"* ]]
  [[ "$stderr" == *"UNMATCHED: CVE-2025-5000 stdlib v1.26.5 at 'usr/bin/task'"* ]]
  [[ "$stderr" == *"2 finding(s) match no rule"* ]]
  [ -z "$output" ]
}

@test "output is deterministic" {
  gen "$FX/arm64.json" "$FX/amd64.json"; first="$output"
  gen "$FX/amd64.json" "$FX/arm64.json"
  [ "$output" = "$first" ]
}

# ---- the committed .trivyignore.yaml and its wiring -----------------------------

@test ".trivyignore.yaml: every entry has a scope, a statement and an expiry" {
  [ -f "$IGNORE" ]
  ids=$(grep -c '^  - id: ' "$IGNORE")
  [ "$ids" -gt 0 ]
  [ "$(grep -c '^    statement: "' "$IGNORE")" -eq "$ids" ]
  [ "$(grep -cE '^    expired_at: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$IGNORE")" -eq "$ids" ]
  [ "$(grep -cE '^    (paths|purls):$' "$IGNORE")" -eq "$ids" ]
}

@test ".trivyignore.yaml: no glob paths, so nothing is ignored wholesale" {
  [ -f "$IGNORE" ]
  run grep -E '^      - ".*[*?\[]' "$IGNORE"
  [ "$status" -eq 1 ]
}

@test "scan.yaml passes .trivyignore.yaml to every image scan step" {
  wf="$BATS_TEST_DIRNAME/../../.github/workflows/scan.yaml"
  image_steps=$(grep -c 'image-ref: ' "$wf")
  [ "$image_steps" -ge 2 ]
  [ "$(grep -c 'trivyignores: .trivyignore.yaml' "$wf")" -eq "$image_steps" ]
}
