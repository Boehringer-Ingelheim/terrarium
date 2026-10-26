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
# Overridable so scripts/tests can point the workflow checks at fixtures.
# ACTIONS_DIR holds local composite actions; their `uses:` must be pinned too.
WF_DIR="${WF_DIR:-.github/workflows}"
ACTIONS_DIR="${ACTIONS_DIR:-.github/actions}"
[ -d "$WF_DIR" ] || { echo "ERROR: workflow dir not found: ${WF_DIR}" >&2; exit 1; }
PIN_DIRS=("$WF_DIR")
[ -d "$ACTIONS_DIR" ] && PIN_DIRS+=("$ACTIONS_DIR")

# ── Ratchet thresholds ───────────────────────────────────────────────────────
# Tighten these as extraction phases land. Do not loosen.
#   heredocs:      baseline 10 → target 2 (the two config heredocs at :557,:642)
#   longest RUN:   baseline 68 → target 20
HEREDOC_MAX=2    # Phase 5: import_vendor_key extracted (3→2) — FINAL target: the 2 config heredocs (:557,:642)
RUN_MAX=20       # Phase 6: age/sops + node keyring decomposed — FINAL target reached

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
chk "unpinned actions"   "$(grep -rhoE 'uses: [^@]+@[^ ]+' "${PIN_DIRS[@]}" | grep -cvE '@[0-9a-f]{40}' || true)" -eq 0
# INFIAAS-11804: every buildx setup pins its BuildKit image by tag AND digest.
# The default `buildx-stable-1` floated to v0.32.2 (40 MiB attestation cap) and
# silently broke every GHCR publish from 2026-09-17. Dependabot can't see this
# pin, so it is enforced here. `buildx setups >= 1` stops a wrong path from
# passing as 0 == 0.
wf_all() { find "$WF_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -exec cat {} +; }
buildx_setups="$(wf_all | grep -cE 'uses: docker/setup-buildx-action@' || true)"
buildkit_pins="$(wf_all | grep -cE 'driver-opts:.*image=moby/buildkit:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' || true)"
chk "buildx setups"      "$buildx_setups" -ge 1
chk "buildkit pinned"    "$buildkit_pins" -eq "$buildx_setups"
# INFIAAS-11804 (B4): every `latest` tag rule must be conditional, so a
# pre-release tag can never move `latest` (tag-driven rules use
# scripts/is-prerelease.sh; the branch rule uses {{is_default_branch}}).
chk "unguarded latest"   "$(wf_all | grep -E 'value=latest' | grep -cv 'enable=' || true)" -eq 0
# INFIAAS-11916 (S1.6): `latest` and `{{major}}` move only for the HIGHEST
# release, so a maintenance release (v4.8.4 after v4.9.6) cannot move them
# back. Every `latest` rule must be the default-branch rule or be gated on the
# `move_latest` output, which scripts/is-highest-release.sh computes. The
# `{{major}}` rule must be gated the same way. A metadata flavour of
# latest=auto|true would add `latest` for any release tag, so it is banned.
# Every workflow that gates on move_latest must compute it with the script.
guard_expr="enable=\\$\\{\\{ steps\\.[a-z_]+\\.outputs\\.move_latest == 'true' \\}\\}"
chk "latest not via highest-release guard" \
  "$(wf_all | grep -E 'value=latest' | grep -vE "enable=\\{\\{is_default_branch\\}\\}|${guard_expr}" | grep -c . || true)" -eq 0
chk "major not via highest-release guard" \
  "$(wf_all | grep -E 'pattern=\{\{major\}\}([^.]|$)' | grep -vE "$guard_expr" | grep -c . || true)" -eq 0
chk "flavor latest=auto|true" "$(wf_all | grep -cE 'flavor:.*latest=(auto|true)' || true)" -eq 0
# INFIAAS-11916 (A-01): a metadata-action step with NO flavour defaults to
# latest=auto, and its type=semver rule then emits `latest` for any release
# tag, whatever the move_latest rules say. So every docker/metadata-action
# step must declare latest=false in its own `with:` block (checked per step,
# so one step cannot cover for another).
meta_unflavored() { # files... -> one line per metadata-action step lacking latest=false
  awk '
    function flush() { if (inmeta && !ok) print FILENAME ":" start; inmeta=0; ok=0 }
    FNR==1 { flush() }
    /^[[:space:]]*-[[:space:]]+(name|uses):/ { flush() }
    /uses:[[:space:]]*docker\/metadata-action@/ { inmeta=1; ok=0; start=FNR }
    inmeta && /^[[:space:]]*flavor:.*latest=false/ { ok=1 }
    END { flush() }
  ' "$@"
}
mapfile -t wf_files < <(find "$WF_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
meta_bad="$(meta_unflavored "${wf_files[@]}")"
[ -z "$meta_bad" ] || printf '  metadata-action step without flavor latest=false: %s\n' $meta_bad
chk "metadata-action without latest=false" "$(printf '%s\n' "$meta_bad" | grep -c . || true)" -eq 0
unwired=0
while IFS= read -r f; do
  grep -q 'scripts/is-highest-release.sh' "$f" || { echo "  move_latest used without scripts/is-highest-release.sh: $f"; unwired=$((unwired + 1)); }
done < <(grep -rlE 'outputs\.move_latest' "$WF_DIR" 2>/dev/null || true)
chk "move_latest without guard script" "$unwired" -eq 0

# ── Ratchet metrics ──────────────────────────────────────────────────────────
chk "helper heredocs"    "$(grep -cE '<<.?(EOF|EOS|EOT)' "$DF" || true)" -le "$HEREDOC_MAX"
# Measured ONLY over RUN blocks (a block is the RUN line plus any
# trailing-backslash continuations). The earlier one-liner also counted
# backslash-continued ENV blocks (e.g. the 63-entry NODE_RELEASE_FPRS list),
# mis-reporting 68; this scopes to RUN and reports the true value.
longest=$(awk '
  /^RUN / {inrun=1; start=NR}
  inrun && $0 !~ /\\[ \t]*$/ {if (NR-start+1 > m) m=NR-start+1; inrun=0}
  END {print m+0}
' "$DF")
chk "longest RUN block"  "$longest" -le "$RUN_MAX"

exit $fail
