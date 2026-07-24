#!/usr/bin/env bash
# Mechanical guardrails for docker/Dockerfile.terrarium and the workflows.
#
# Two classes of assertion:
#
#   1. DO-NOT-REGRESS security invariants (minimums / exact counts). These must
#      hold at every commit — a drop means verification logic was lost. Sourced
#      from prd.md §5 and confirmed against the 378de2f baseline.
#
#   2. RATCHET metrics (heredoc count, longest RUN block). These start at the
#      current baseline and are TIGHTENED as the extraction phases land — the
#      "shrinking ignore list" from the plan. They may only ever move toward the
#      final target, never away from it. Final targets are noted inline.
#
# Run: make guardrails   (or: scripts/check-guardrails.sh)
set -euo pipefail

DF="${1:-docker/Dockerfile.terrarium}"
[ -f "$DF" ] || { echo "ERROR: dockerfile not found: ${DF}" >&2; exit 1; }

# ── Ratchet thresholds ───────────────────────────────────────────────────────
# Tighten these as extraction phases land. Do not loosen.
#   heredocs:      baseline 10 → target 2 (the two config heredocs at :557,:642)
#   longest RUN:   baseline 68 → target 20
HEREDOC_MAX=2    # Phase 5: import_vendor_key extracted (3→2) — FINAL target: the 2 config heredocs (:557,:642)
RUN_MAX=68       # final target: 20 (reached in Phase 6)

fail=0
chk() { # name actual op expected  (op ∈ -ge|-le|-eq; literal so shellcheck parses)
  local pass=0
  case "$3" in
    -ge) [ "$2" -ge "$4" ] && pass=1 ;;
    -le) [ "$2" -le "$4" ] && pass=1 ;;
    -eq) [ "$2" -eq "$4" ] && pass=1 ;;
    *) echo "GUARDRAIL ERROR: unknown op '$3' for $1" >&2; fail=1; return ;;
  esac
  if [ "$pass" -eq 1 ]; then
    echo "ok: $1 = $2 ($3 $4)"
  else
    echo "GUARDRAIL FAIL: $1 = $2, expected $3 $4"; fail=1
  fi
}

# ── Do-not-regress security invariants ───────────────────────────────────────
# Verification logic is being extracted from the Dockerfile into
# docker/files/bin/. Count sha256/gpg references across BOTH so extraction (which
# only MOVES the logic) does not read as a regression — a genuine drop still
# fails. The `.sha`/`.gpg`-generating heredocs are gone, so this is the union.
BIN_DIR="$(dirname "$DF")/files/bin"
VSRC=("$DF")
for f in "$BIN_DIR"/*; do [ -f "$f" ] && VSRC+=("$f"); done
chk "sha256 refs"        "$(grep -h sha256 "${VSRC[@]}" 2>/dev/null | grep -c sha256 || true)"        -ge 23
chk "gpg/pgp refs"       "$(grep -hiE 'gpg|pgp' "${VSRC[@]}" 2>/dev/null | grep -ciE 'gpg|pgp' || true)" -ge 66
chk "ARG pins"           "$(grep -cE '^ARG ' "$DF")"                   -ge 42
chk "node fingerprints"  "$(sed -n '/NODE_RELEASE_FPRS/,/^$/p' "$DF" | grep -cE '^[[:space:]]*[0-9A-F]{40}')" -eq 63
chk "curl-pipe-to-shell" "$(grep -cE 'curl[^|]*\|[[:space:]]*(ba)?sh' "$DF" || true)" -eq 0
chk "unpinned actions"   "$(grep -rhoE 'uses: [^@]+@[^ ]+' .github/workflows/ | grep -cvE '@[0-9a-f]{40}' || true)" -eq 0

# ── Ratchet metrics ──────────────────────────────────────────────────────────
chk "helper heredocs"    "$(grep -cE '<<.?(EOF|EOS|EOT)' "$DF" || true)" -le "$HEREDOC_MAX"
longest=$(awk '/^RUN /{n=1;next} /\\$/{n++;next} {if(n){if(n>m)m=n;n=0}} END{print m+0}' "$DF")
chk "longest RUN block"  "$longest" -le "$RUN_MAX"

exit $fail
