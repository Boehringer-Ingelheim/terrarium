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
  grep -A3 '^  - id: CVE-2025-0001$' <<<"$output" | grep -q 'statement: "oc 4.19.51 is the newest 4.19.z'
  # no unescaped double quote inside a statement
  inner=$(grep '^    statement: ' <<<"$output" | sed 's/^    statement: "//; s/"$//')
  run grep '[^\\]"' <<<"$inner"
  [ "$status" -eq 1 ]
}

@test "findings we can fix ourselves are refused (exit 1, listed on stderr)" {
  gen "$FX/amd64.json" "$FX/fixable.json"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"UNMATCHED: CVE-2026-19534 undici 6.28.0"* ]]
  [[ "$stderr" == *"UNMATCHED: CVE-2025-5000 stdlib v1.26.5 at 'usr/local/bin/starship'"* ]]
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

# ---- INFIAAS-11916: vendor rules added for 4.9.6 -----------------------------------

@test "INFIAAS-11916: task, kubectl and yq (newest releases) and the az RPM's pip-vendored certifi are accepted, scoped" {
  cat > "$BATS_TEST_TMPDIR/r.json" <<'JSON'
{"Results": [
  {"Target": "usr/bin/task", "Class": "lang-pkgs", "Type": "gobinary",
   "Vulnerabilities": [{"VulnerabilityID": "CVE-2026-0001", "PkgName": "stdlib", "InstalledVersion": "v1.27.1"}]},
  {"Target": "usr/local/bin/kubectl", "Class": "lang-pkgs", "Type": "gobinary",
   "Vulnerabilities": [{"VulnerabilityID": "CVE-2026-0002", "PkgName": "stdlib", "InstalledVersion": "v1.26.8"}]},
  {"Target": "usr/local/bin/yq", "Class": "lang-pkgs", "Type": "gobinary",
   "Vulnerabilities": [{"VulnerabilityID": "CVE-2026-0003", "PkgName": "golang.org/x/net", "InstalledVersion": "v0.59.0"}]},
  {"Target": "Python", "Class": "lang-pkgs", "Type": "python-pkg",
   "Vulnerabilities": [{"VulnerabilityID": "GHSA-6q48-6c7w-9gw2", "PkgName": "certifi", "InstalledVersion": "2026.6.17"}]}
]}
JSON
  gen "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 0 ]
  for rule in task kubectl yq az-pip-certifi; do [[ "$output" == *"# ── ${rule}"* ]]; done
  [[ "$output" == *'- "pkg:pypi/certifi@2026.6.17"'* ]]
  [[ "$output" == *"Azure/azure-cli#34250"* ]]
}

@test "INFIAAS-11916: certifi with a path (a venv we own) is still refused" {
  cat > "$BATS_TEST_TMPDIR/r.json" <<'JSON'
{"Results": [{"Target": "Python", "Class": "lang-pkgs", "Type": "python-pkg",
  "Vulnerabilities": [{"VulnerabilityID": "GHSA-6q48-6c7w-9gw2", "PkgName": "certifi", "InstalledVersion": "2025.7.14",
                       "PkgPath": "tmp/.venv/lib/python3.13/site-packages/certifi-2025.7.14.dist-info/METADATA"}]}]}
JSON
  gen "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"UNMATCHED: GHSA-6q48-6c7w-9gw2 certifi 2025.7.14"* ]]
}

@test "A-03: the committed SAM statements name the SAM version that the accepted paths contain" {
  # Every aws-sam-rie entry's statement must quote the version directory of
  # the /usr/local/aws-sam-cli/<ver>/ paths it accepts (no stale "newest" claim).
  paths_ver="$(grep -oE 'usr/local/aws-sam-cli/[0-9][0-9.]*/' "$IGNORE" | sort -u | sed -E 's#.*/aws-sam-cli/([^/]+)/#\1#')"
  [ "$(wc -l <<<"$paths_ver")" -eq 1 ] || { echo "several SAM versions in paths: $paths_ver"; return 1; }
  stated="$(grep -oE 'AWS SAM CLI [0-9][0-9.]* is the newest' "$IGNORE" | sort -u)"
  [ "$stated" = "AWS SAM CLI ${paths_ver} is the newest" ] || { echo "stated: $stated, paths: $paths_ver"; return 1; }
}

# ---- INFIAAS-11916: 4.8 line rules (ODS-agent-aligned tools, Ruby, frozen gems) ----

@test "4.8: ODS-agent-aligned tools, Ruby default gems, the gem lock and the venv azure pins are accepted, scoped by path" {
  cat > "$BATS_TEST_TMPDIR/r.json" <<'JSON'
{"Results": [
  {"Target": "opt/tenv/Terraform/1.9.4/terraform", "Class": "lang-pkgs", "Type": "gobinary",
   "Vulnerabilities": [{"VulnerabilityID": "CVE-2026-1001", "PkgName": "stdlib", "InstalledVersion": "v1.22.5"}]},
  {"Target": "usr/local/bin/terraform-config-inspect", "Class": "lang-pkgs", "Type": "gobinary",
   "Vulnerabilities": [{"VulnerabilityID": "CVE-2026-1002", "PkgName": "stdlib", "InstalledVersion": "v1.22.5"}]},
  {"Target": "Ruby", "Class": "lang-pkgs", "Type": "gemspec",
   "Vulnerabilities": [
     {"VulnerabilityID": "CVE-2026-1003", "PkgName": "zlib", "InstalledVersion": "3.1.1",
      "PkgPath": "opt/rbenv/versions/3.3.4/lib/ruby/gems/3.3.0/specifications/default/zlib-3.1.1.gemspec"},
     {"VulnerabilityID": "CVE-2026-1004", "PkgName": "excon", "InstalledVersion": "0.112.0",
      "PkgPath": "opt/bundle/ruby/3.3.0/specifications/excon-0.112.0.gemspec"}]},
  {"Target": "Python", "Class": "lang-pkgs", "Type": "python-pkg",
   "Vulnerabilities": [
     {"VulnerabilityID": "CVE-2026-1005", "PkgName": "PyNaCl", "InstalledVersion": "1.5.0",
      "PkgPath": "tmp/.venv/lib/python3.13/site-packages/PyNaCl-1.5.0.dist-info/METADATA"},
     {"VulnerabilityID": "CVE-2026-1006", "PkgName": "cryptography", "InstalledVersion": "47.0.0",
      "PkgPath": "tmp/.venv/lib/python3.13/site-packages/cryptography-47.0.0.dist-info/METADATA"}]}
]}
JSON
  gen "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 0 ]
  for rule in terraform-default terraform-config-inspect ruby-default-gems gem-lock venv-azure-pins; do
    [[ "$output" == *"# ── ${rule}"* ]] || { echo "missing rule ${rule}"; return 1; }
  done
  [[ "$output" == *'- "opt/bundle/ruby/3.3.0/specifications/excon-0.112.0.gemspec"'* ]]
  [[ "$output" == *"ODS terraform-2408 agent"* ]]
}

@test "4.8: findings in what we own and can fix are still refused (openstack venv, /tmp/.venv PyJWT, starship)" {
  cat > "$BATS_TEST_TMPDIR/r.json" <<'JSON'
{"Results": [
  {"Target": "Python", "Class": "lang-pkgs", "Type": "python-pkg",
   "Vulnerabilities": [
     {"VulnerabilityID": "CVE-2026-2001", "PkgName": "urllib3", "InstalledVersion": "1.26.20",
      "PkgPath": "opt/openstack/lib/python3.13/site-packages/urllib3-1.26.20.dist-info/METADATA"},
     {"VulnerabilityID": "CVE-2026-2002", "PkgName": "PyJWT", "InstalledVersion": "2.13.0",
      "PkgPath": "tmp/.venv/lib/python3.13/site-packages/pyjwt-2.13.0.dist-info/METADATA"}]},
  {"Target": "usr/local/bin/starship", "Class": "lang-pkgs", "Type": "gobinary",
   "Vulnerabilities": [{"VulnerabilityID": "CVE-2026-2003", "PkgName": "stdlib", "InstalledVersion": "v1.26.5"}]}
]}
JSON
  gen "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"3 finding(s) match no rule"* ]]
}
