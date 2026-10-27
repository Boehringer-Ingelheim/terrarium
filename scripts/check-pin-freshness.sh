#!/usr/bin/env bash
# Pin-freshness guardrail for docker/Dockerfile.terrarium (INFIAAS-9587,
# scope folded in from INFIAAS-11478).
#
# check-guardrails.sh stops security logic regressing; this stops the version
# pins going stale again. GO_VERSION sat on 1.21.13 (EOL 2024-08) and
# ROCKYLINUX_VERSION on 9.3 (EOL at 9.4) until the 2026-09 Aqua baseline showed
# the cost: the Go toolchain alone was ~30% of all Critical+High findings.
#
# Checks (each against the upstream source of truth):
#   GO_VERSION          major.minor is one of the two supported Go releases
#                       (the stable entries of https://go.dev/dl/?mode=json)
#   ROCKYLINUX_VERSION  equals the newest Rocky 9.x point release
#                       (https://dl.rockylinux.org/pub/rocky/)
#   UBI9_VERSION        exists, and the next minor (9.N+1) does NOT exist on
#                       registry.access.redhat.com (the tag list is paginated,
#                       so probe the manifest instead of listing)
#
# A deliberate lag is allowed via a dated allowlist entry (see
# scripts/pin-freshness-allowlist.txt): the check WARNs and passes until the
# entry expires, then fails again, so no exception is permanent.
#
# NETWORK-DEPENDENT: runs in CI (lint.yaml via `make guardrails`), not in the
# hermetic `helpers` stage. `make guardrails PIN_FRESHNESS=0` skips it offline.
#
# Exit: 0 fresh (warnings allowed) | 1 stale or expired allowlist entry |
#       2 usage, network or parse error (never a false pass)
#
# Usage: scripts/check-pin-freshness.sh [dockerfile]
set -euo pipefail

DF="${1:-docker/Dockerfile.terrarium}"
ALLOWLIST="${PIN_FRESHNESS_ALLOWLIST:-$(dirname "$0")/pin-freshness-allowlist.txt}"
TODAY="${PIN_FRESHNESS_TODAY:-$(date -u +%F)}"
GO_RELEASES_URL="${GO_RELEASES_URL:-https://go.dev/dl/?mode=json}"
ROCKY_INDEX_URL="${ROCKY_INDEX_URL:-https://dl.rockylinux.org/pub/rocky/}"
UBI9_MANIFEST_URL="${UBI9_MANIFEST_URL:-https://registry.access.redhat.com/v2/ubi9/ubi/manifests}"
MANIFEST_ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'

die() { echo "PIN FRESHNESS ERROR: $*" >&2; exit 2; }

[ -f "$DF" ] || die "dockerfile not found: ${DF}"
[[ "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "PIN_FRESHNESS_TODAY must be YYYY-MM-DD, got '${TODAY}'"
command -v jq >/dev/null 2>&1 || die "jq is required"

# arg <NAME> — the ARG default, or a usage error (never an empty string).
arg() {
  local v
  v="$(grep -m1 "^ARG $1=" "$DF" | cut -d= -f2- || true)"
  [ -n "$v" ] || die "ARG $1 not found (or empty) in ${DF}"
  printf '%s' "$v"
}

# get <url> — body on stdout; any transport or HTTP error is a usage error.
get() {
  curl -fsSL --retry 2 --max-time 30 "$1" || die "cannot fetch $1 (network error: refusing to pass)"
}

# probe <url> — HTTP status only (200/404 are meaningful, anything else is an error).
probe() {
  local code
  code="$(curl -s -o /dev/null --retry 2 --max-time 30 -w '%{http_code}' -H "Accept: ${MANIFEST_ACCEPT}" "$1" || true)"
  case "$code" in
    200|404) printf '%s' "$code" ;;
    *) die "unexpected HTTP status '${code}' probing $1 (refusing to pass)" ;;
  esac
}

# ── Allowlist ────────────────────────────────────────────────────────────────
# Format, one entry per line:  <ARG_NAME> <expires YYYY-MM-DD> <reason...>
declare -A ALLOW_UNTIL=() ALLOW_WHY=()
if [ -f "$ALLOWLIST" ]; then
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%%#*}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    read -r name expiry why <<<"$line"
    # An entry for an ARG this script does not check is almost certainly a
    # typo; reject it so an exception can never silently cover nothing.
    case "$name" in
      GO_VERSION|ROCKYLINUX_VERSION|UBI9_VERSION) ;;
      *) die "${ALLOWLIST}:${n}: '${name}' is not a checked pin (GO_VERSION ROCKYLINUX_VERSION UBI9_VERSION)" ;;
    esac
    [[ "${expiry:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "${ALLOWLIST}:${n}: expiry must be YYYY-MM-DD"
    [ -n "${why:-}" ] || die "${ALLOWLIST}:${n}: a reason is required"
    ALLOW_UNTIL[$name]="$expiry"; ALLOW_WHY[$name]="$why"
  done < "$ALLOWLIST"
fi

fail=0
# verdict <ARG> <pinned> <ok 0|1> <message>
verdict() {
  local name="$1" pinned="$2" ok="$3" msg="$4" expiry
  if [ "$ok" -eq 1 ]; then
    echo "ok: ${name}=${pinned} (${msg})"
    return
  fi
  expiry="${ALLOW_UNTIL[$name]:-}"
  # ISO dates compare correctly as strings; the expiry day itself still passes.
  if [ -n "$expiry" ] && [[ ! "$TODAY" > "$expiry" ]]; then
    echo "WARN: ${name}=${pinned} is stale (${msg}); allowlisted until ${expiry}: ${ALLOW_WHY[$name]}"
  elif [ -n "$expiry" ]; then
    echo "PIN FRESHNESS FAIL: ${name}=${pinned} is stale (${msg}); allowlist entry EXPIRED ${expiry}"
    fail=1
  else
    echo "PIN FRESHNESS FAIL: ${name}=${pinned} is stale (${msg})"
    fail=1
  fi
}

# ── GO_VERSION: major.minor must be a supported release ──────────────────────
go_pin="$(arg GO_VERSION)"
[[ "$go_pin" =~ ^([0-9]+\.[0-9]+)(\.[0-9]+)?$ ]] || die "GO_VERSION '${go_pin}' is not N.N[.N]"
go_major="${BASH_REMATCH[1]}"
go_json="$(get "$GO_RELEASES_URL")" || exit 2
go_supported="$(jq -r '.[] | select(.stable == true) | .version' <<<"$go_json" 2>/dev/null \
  | sed -nE 's/^go([0-9]+\.[0-9]+).*/\1/p' | sort -uV | tr '\n' ' ')" || true
go_supported="${go_supported% }"
[ -n "$go_supported" ] || die "no stable Go releases parsed from ${GO_RELEASES_URL}"
ok=0; for m in $go_supported; do [ "$m" = "$go_major" ] && ok=1; done
verdict GO_VERSION "$go_pin" "$ok" "supported: ${go_supported}"

# ── ROCKYLINUX_VERSION: newest 9.x point release ─────────────────────────────
rocky_pin="$(arg ROCKYLINUX_VERSION)"
rocky_html="$(get "$ROCKY_INDEX_URL")" || exit 2
rocky_latest="$(grep -oE 'href="9\.[0-9]+/"' <<<"$rocky_html" \
  | sed -E 's/href="(9\.[0-9]+)\/"/\1/' | sort -V | tail -n1)" || true
[ -n "$rocky_latest" ] || die "no Rocky 9.x releases parsed from ${ROCKY_INDEX_URL}"
ok=0; [ "$rocky_pin" = "$rocky_latest" ] && ok=1
verdict ROCKYLINUX_VERSION "$rocky_pin" "$ok" "newest: ${rocky_latest}"

# ── UBI9_VERSION: exists, and no newer minor exists ──────────────────────────
ubi_pin="$(arg UBI9_VERSION)"
[[ "$ubi_pin" =~ ^9\.([0-9]+)$ ]] || die "UBI9_VERSION '${ubi_pin}' is not 9.N"
ubi_next="9.$((BASH_REMATCH[1] + 1))"
# Capture first: `die` inside $(...) only exits the subshell, and an empty
# status must be an error (exit 2), never read as "tag missing" (exit 1).
ubi_pin_code="$(probe "${UBI9_MANIFEST_URL}/${ubi_pin}")" || exit 2
ubi_next_code="$(probe "${UBI9_MANIFEST_URL}/${ubi_next}")" || exit 2
if [ "$ubi_pin_code" != 200 ]; then
  verdict UBI9_VERSION "$ubi_pin" 0 "tag ${ubi_pin} does not exist"
elif [ "$ubi_next_code" = 200 ]; then
  verdict UBI9_VERSION "$ubi_pin" 0 "newer minor ${ubi_next} exists"
else
  verdict UBI9_VERSION "$ubi_pin" 1 "no ${ubi_next} yet"
fi

exit $fail
