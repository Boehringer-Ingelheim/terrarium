#!/usr/bin/env bash
# check-vendor-key-drift.sh — fail (exit 1) if the vendor-key fingerprint pins in
# the checked-in env reference file drift from the ENV block baked into the
# Dockerfile.
#
# Why a comparison and not a generation step: the Dockerfile `ENV` cannot source
# a file, so the pins are mirrored by hand (refresh-vendor-keys.sh writes the env
# reference; the ENV block is updated manually). This check closes that seam in
# CI. It compares the three scalar fingerprints plus the NODE_RELEASE_FPRS list,
# case-insensitively, with the Node list normalised (upcase / sort -u).
#
# Output is FINGERPRINTS ONLY — public identifiers. No key material is ever read,
# printed, or logged.
set -euo pipefail

DF="${1:-docker/Dockerfile.terrarium}"
ENV_FILE="${2:-docker/vendor-keys/vendor-keys.env}"
[ -f "$DF" ] || { echo "ERROR: dockerfile not found: $DF" >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "ERROR: env reference not found: $ENV_FILE" >&2; exit 1; }

up() { tr '[:lower:]' '[:upper:]'; }
norm_list() { tr ' ' '\n' | grep -oE '[0-9A-Fa-f]{40}' | up | sort -u; }

# --- Reference pins PARSED (never executed) from the env file. We grep the
# assignments rather than sourcing so the file's format is irrelevant and no
# content from a protected file is ever run. ---
env_scalar() { grep -m1 -oE "$1=\"?[0-9A-Fa-f]{40}" "$ENV_FILE" 2>/dev/null | grep -oE '[0-9A-Fa-f]{40}' | up || true; }
ref_hashi="$(env_scalar HASHICORP_PGP_FPR)"
ref_opentofu="$(env_scalar OPENTOFU_PGP_FPR)"
ref_aws="$(env_scalar AWS_CLI_PGP_FPR)"
# Node list: everything from its assignment to EOF (it is the last pin), 40-hex only.
ref_node="$(sed -n '/NODE_RELEASE_FPRS/,$p' "$ENV_FILE" | norm_list || true)"

# --- Values from the Dockerfile ENV block. ---
# Matches both `ENV VAR=<hex>` and indented `    VAR=<hex> \` continuation lines.
df_scalar() { grep -oE "(^|[[:space:]])$1=\"?[0-9A-Fa-f]{40}" "$DF" 2>/dev/null | head -1 | grep -oE '[0-9A-Fa-f]{40}' | up || true; }
df_hashi="$(df_scalar HASHICORP_PGP_FPR)"
df_opentofu="$(df_scalar OPENTOFU_PGP_FPR)"
df_aws="$(df_scalar AWS_CLI_PGP_FPR)"
df_node="$(sed -n '/NODE_RELEASE_FPRS/,/^$/p' "$DF" | norm_list || true)"

fail=0
cmp_scalar() { # name ref df
  if [ -z "$2" ] || [ -z "$3" ]; then echo "DRIFT: $1 — missing value (env='$2' dockerfile='$3')"; fail=1
  elif [ "$2" != "$3" ]; then echo "DRIFT: $1"; echo "  env ref:    $2"; echo "  dockerfile: $3"; fail=1
  else echo "ok: $1 = $2"; fi
}
cmp_scalar HASHICORP_PGP_FPR "$ref_hashi" "$df_hashi"
cmp_scalar OPENTOFU_PGP_FPR  "$ref_opentofu" "$df_opentofu"
cmp_scalar AWS_CLI_PGP_FPR   "$ref_aws" "$df_aws"

ref_n="$(printf '%s\n' "$ref_node" | grep -c . || true)"
df_n="$(printf '%s\n' "$df_node" | grep -c . || true)"
if [ "$ref_node" != "$df_node" ]; then
  echo "DRIFT: NODE_RELEASE_FPRS (env=${ref_n} dockerfile=${df_n} fingerprints)"
  echo "  only in one side (fingerprints):"
  comm -3 <(printf '%s\n' "$ref_node") <(printf '%s\n' "$df_node") || true
  fail=1
else
  echo "ok: NODE_RELEASE_FPRS (${df_n} fingerprints match)"
fi

[ "$fail" -eq 0 ] && echo "vendor-key pins: no drift"
exit $fail
