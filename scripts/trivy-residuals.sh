#!/usr/bin/env bash
# trivy-residuals.sh — generate .trivyignore.yaml from Trivy JSON reports of the
# released image (INFIAAS-9587).
#
# The release scan (scan.yaml) fails on any fixable Critical/High/Medium
# finding. Some findings can only be fixed by a vendor: the image already ships
# the vendor's newest release, but that release was built with a vulnerable Go
# toolchain or bundles a vulnerable library. Those residuals are accepted here,
# each one explicitly:
#
#   - one entry per vulnerability ID, scoped to the exact file paths (or, for
#     pip's vendored packages, which have no path, the exact purl) it was seen
#     at, so a NEW CVE in the same tool, or the same CVE anywhere else, still
#     fails the gate;
#   - every entry carries the reason (the RULES below) and an expiry date, after
#     which Trivy reports it again and the list has to be regenerated;
#   - a finding that matches no rule is an error: anything we can fix ourselves
#     must be fixed, not listed.
#
# Usage:
#   trivy image --format json --ignore-unfixed --severity CRITICAL,HIGH,MEDIUM \
#     --pkg-types os,library -o amd64.json <image>-linux-amd64   # same for arm64
#   scripts/trivy-residuals.sh 2026-12-31 amd64.json arm64.json > .trivyignore.yaml
#
# Exit codes: 0 ok, 1 unmatched findings (listed on stderr), 2 usage error.
set -euo pipefail

usage() { echo "usage: $0 <expired_at YYYY-MM-DD> <trivy.json> [<trivy.json> ...]" >&2; exit 2; }
[ "$#" -ge 2 ] || usage
EXPIRES="$1"; shift
[[ "$EXPIRES" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
for f in "$@"; do [ -f "$f" ] || { echo "ERROR: no such report: $f" >&2; exit 2; }; done

# ── Rules: path → reason. Keep each reason specific: which vendor release is
# shipped, why it cannot be fixed here, and what lifts it. First match wins.
rule_for() { # <path> <pkg> → prints the rule key, or nothing
  case "$1" in
    usr/local/bin/oc) echo oc ;;
    usr/bin/tenv|usr/bin/atmos|usr/bin/terraform|usr/bin/terragrunt|usr/bin/terramate|usr/bin/tf|usr/bin/tofu) echo tenv ;;
    opt/tenv/OpenTofu/*/tofu) echo opentofu ;;
    usr/local/bin/sops|usr/bin/sops) echo sops ;;
    usr/local/bin/terraform-docs) echo terraform-docs ;;
    usr/local/bin/tflint) echo tflint ;;
    usr/local/bin/packer) echo packer ;;
    usr/local/bin/age|usr/local/bin/age-keygen) echo age ;;
    usr/local/bin/helm) echo helm ;;
    */samcli/local/rapid/aws-lambda-rie-*) echo aws-sam-rie ;;
    usr/lib64/az/*) echo azure-cli-rpm ;;
    usr/lib64/google-cloud-sdk/*) echo gcloud ;;
    tmp/.venv/lib/python*/site-packages/cryptography-*) echo venv-cryptography ;;
    "") case "$2" in msgpack|setuptools|urllib3) echo pip-vendor ;; esac ;;
  esac
}

reason_for() {
  case "$1" in
    oc) echo "oc 4.19.48 is the newest 4.19.z (Red Hat build, Go 1.23 with 2023-era modules); even oc 4.22.15 carries 62 of these. oc stays within one minor of the ODS clusters. Lifted by a Red Hat 4.19.z rebuild or the cluster move to a newer minor." ;;
    tenv) echo "tenv 4.15.1 is the newest release and is built with go1.25.12; /usr/bin/{atmos,terraform,terragrunt,terramate,tf,tofu} are tenv's own proxy binaries. Lifted by the next tenv release." ;;
    opentofu) echo "OpenTofu 1.13.1 is the newest release (go1.27.1); the remaining modules (x/mod, grpc) are fixed only in releases newer than its build. Lifted by the next OpenTofu patch." ;;
    sops) echo "sops 3.13.3 is the newest release (go1.26.5). Lifted by the next sops release." ;;
    terraform-docs) echo "terraform-docs v0.24.0 is the newest release (go1.25.8). Lifted by the next terraform-docs release." ;;
    tflint) echo "tflint 0.64.0 is the newest release (go1.26.3). Lifted by the next tflint release." ;;
    packer) echo "packer 1.16.1 is the newest release. Lifted by the next packer release." ;;
    age) echo "age 1.3.2 is the newest release (x/crypto v0.55.0). Lifted by the next age release." ;;
    helm) echo "helm 3.22.0 is the newest v3 release (x/crypto v0.55.0); helm 4.3.0 has the same x/crypto. Lifted by the next helm release." ;;
    aws-sam-rie) echo "AWS SAM CLI 1.166.2 is the newest release; it bundles the Lambda Runtime Interface Emulator (chi v5.2.2), which only runs locally under 'sam local'. Lifted by the next SAM CLI release." ;;
    azure-cli-rpm) echo "Azure CLI 2.90.0 is the newest Microsoft RPM; it bundles its own Python packages under /usr/lib64/az. Lifted by the next Azure CLI release." ;;
    gcloud) echo "Google Cloud CLI is installed unpinned from Google's repo (newest release); it bundles its own Python under /usr/lib64/google-cloud-sdk. Lifted by the next Cloud SDK release." ;;
    venv-cryptography) echo "azure-cli-core 2.90.0 (newest) pins msal==1.36.0, which requires cryptography<49, so /tmp/.venv stays on cryptography 48.0.1. Lifted when Azure CLI moves to a newer msal." ;;
    pip-vendor) echo "pip 26.2.1 (newest; pip main too) vendors these, listed in pip/_vendor/vendor.txt of every pip in the image; Trivy reports them without a path. pip vendors only pkg_resources from setuptools. Lifted by the next pip release." ;;
  esac
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# One row per (id, path, pkg, version), de-duplicated across architectures.
# A finding with no path (pip's vendored packages) gets "-": `read` would
# otherwise collapse the empty tab-separated field.
jq -r '.Results[]? as $r | ($r.Vulnerabilities // [])[]
       | [.VulnerabilityID, (.PkgPath // (if $r.Class == "lang-pkgs" and ($r.Target | test("^(Python|Node.js)$")) then "-" else $r.Target end)), .PkgName, .InstalledVersion]
       | @tsv' "$@" | sort -u > "$tmp/rows"

unmatched=0
: > "$tmp/entries"
while IFS=$'\t' read -r id path pkg ver; do
  [ "$path" != "-" ] || path=""
  rule="$(rule_for "$path" "$pkg")"
  if [ -z "$rule" ]; then
    echo "UNMATCHED: ${id} ${pkg} ${ver} at '${path}'" >&2; unmatched=$((unmatched + 1)); continue
  fi
  if [ -n "$path" ]; then scope="paths	${path}"; else scope="purls	pkg:pypi/${pkg,,}@${ver}"; fi
  printf '%s\t%s\t%s\n' "$rule" "$id" "$scope" >> "$tmp/entries"
done < "$tmp/rows"
[ "$unmatched" -eq 0 ] || { echo "ERROR: ${unmatched} finding(s) match no rule; fix them or add a justified rule" >&2; exit 1; }

cat <<EOF
# Accepted residual findings for the release Trivy gate (scan.yaml).
# GENERATED by scripts/trivy-residuals.sh: do not edit by hand. Regenerate
# from fresh Trivy JSON reports of both architectures before each release, or
# when an entry expires. Each entry is one CVE at the exact path (or purl) it
# was found at; anything else, including a new CVE in the same tool, still
# fails the gate.
vulnerabilities:
EOF
# Group by (rule, id): one entry per CVE, listing all its paths/purls.
entry_tail() { # rule
  printf '    statement: "%s"\n    expired_at: %s\n' "$(reason_for "$1" | sed 's/"/\\"/g')" "$EXPIRES"
}
prev_key="" prev_rule=""
while IFS=$'\t' read -r rule id kind value; do
  key="${rule} ${id} ${kind}"
  if [ "$key" != "$prev_key" ]; then
    [ -z "$prev_key" ] || entry_tail "$prev_rule"
    [ "$rule" = "$prev_rule" ] || printf '  # ── %s\n' "$rule"
    printf '  - id: %s\n    %s:\n' "$id" "$kind"
    prev_key="$key" prev_rule="$rule"
  fi
  printf '      - "%s"\n' "$value"
done < <(sort -t$'\t' -k1,1 -k2,2 -k3,3 -k4,4 -u "$tmp/entries")
[ -z "$prev_key" ] || entry_tail "$prev_rule"
