#!/usr/bin/env bash
# Publish a signed SPDX SBOM for ONE pushed per-arch image (INFIAAS-11804).
#
# Replaces the BuildKit `--sbom=true` attestation. That attestation is size-capped
# (40 MiB in BuildKit v0.32.x, 80 MiB from v0.33.0) and our SBOM is ~66 MiB, so
# every publish failed once the runner's BuildKit floated to v0.32.2. Instead:
#
#   0. resolve the linux/<arch> IMAGE manifest. buildx pushes an index (image +
#      provenance attestation) and the release manifest job re-indexes the
#      per-arch image manifests, so consumers resolve <tag> -> linux/<arch>
#      image digest. The SBOM must hang off THAT digest, not the push index.
#   1. syft scans that image BY DIGEST (never by tag: --platform is
#      unreliable on indexes) -> sbom-<arch>.spdx.json + sbom-<arch>.txt
#   2. the SBOM must contain packages (a silently empty SBOM never ships)
#   3. oras attaches it to the image digest as an OCI artifact
#      (artifactType application/spdx+json). GHCR has no Referrers API; oras
#      falls back to the `sha256-<digest>` tag schema. Idempotent: if an SPDX
#      SBOM is already attached (job re-run), it is reused, not duplicated.
#   4. cosign signs the SBOM artifact's DIGEST keyless (GitHub OIDC). Only a
#      hash reaches the Rekor log, so SBOM size is not limited anywhere.
#
# Usage: scripts/publish-sbom.sh <image-repo> <digest> <amd64|arm64> <out-dir>
#   e.g. scripts/publish-sbom.sh ghcr.io/boehringer-ingelheim/terrarium \
#          sha256:<64 hex> amd64 "$RUNNER_TEMP/sbom"
#
# Exit codes: 0 ok · 1 a step failed · 2 bad arguments / missing tool
# Env (tests): PUBLISH_SBOM_ATTEMPTS (default 3), PUBLISH_SBOM_BACKOFF (default 30 s)
set -euo pipefail

SPDX_TYPE="application/spdx+json"
ATTEMPTS="${PUBLISH_SBOM_ATTEMPTS:-3}"
BACKOFF="${PUBLISH_SBOM_BACKOFF:-30}"

die() { echo "ERROR: $2" >&2; exit "$1"; }

[ "$#" -eq 4 ] || die 2 "usage: publish-sbom.sh <image-repo> <digest> <amd64|arm64> <out-dir>"
repo="$1" digest="$2" arch="$3" out="$4"

# ── Validate (exit 2, before any tool runs) ─────────────────────────────────
[[ "$repo" =~ ^ghcr\.io/[a-z0-9._/-]+$ ]] \
  || die 2 "image repo must be lowercase 'ghcr.io/<owner>/<name>' with no tag or digest: '${repo}'"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || die 2 "digest must be 'sha256:<64 lowercase hex>': '${digest}'"
case "$arch" in amd64|arm64) ;; *) die 2 "arch must be amd64 or arm64: '${arch}'" ;; esac
[ -d "$out" ] || die 2 "output directory does not exist: '${out}'"
for tool in syft oras cosign jq; do
  command -v "$tool" >/dev/null 2>&1 || die 2 "required tool not on PATH: ${tool}"
done

# retry <description> <command...> — for the network steps (oras, cosign).
retry() {
  local what="$1" n=1; shift
  until "$@"; do
    if [ "$n" -ge "$ATTEMPTS" ]; then
      echo "ERROR: ${what} failed after ${n} attempts" >&2; return 1
    fi
    echo "WARN: ${what} failed (attempt ${n}/${ATTEMPTS}); retrying in ${BACKOFF}s" >&2
    sleep "$BACKOFF"; n=$((n + 1))
  done
}

sbom="sbom-${arch}.spdx.json"

# ── 0. Resolve the linux/<arch> image manifest ──────────────────────────────
img=""
resolve_image() {
  local json
  json="$(oras manifest fetch "${repo}@${digest}")" || return 1
  case "$(jq -r '.mediaType // empty' <<<"$json")" in
    application/vnd.oci.image.index.v1+json|application/vnd.docker.distribution.manifest.list.v2+json)
      img="$(jq -r --arg a "$arch" '[.manifests[]
               | select(.platform.os == "linux" and .platform.architecture == $a) | .digest]
             | if length == 1 then .[0] else empty end' <<<"$json")" ;;
    *) img="$digest" ;;  # already a single image manifest
  esac
}
retry "oras manifest fetch ${repo}@${digest}" resolve_image
[[ "$img" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || die 1 "no single linux/${arch} image manifest in ${repo}@${digest}"
[ "$img" = "$digest" ] || echo "Pushed index ${digest} -> linux/${arch} image ${img}"
ref="${repo}@${img}"

# ── 1. Scan once, two outputs ───────────────────────────────────────────────
echo "Scanning ${ref} ..."
syft scan "registry:${ref}" \
  -o "spdx-json=${out}/${sbom}" \
  -o "syft-table=${out}/sbom-${arch}.txt" \
  || die 1 "syft scan failed for ${ref}"

# ── 2. Sanity: valid JSON with at least one package ─────────────────────────
jq -e '(.packages | type) == "array" and (.packages | length) > 0' "${out}/${sbom}" >/dev/null 2>&1 \
  || die 1 "SBOM ${out}/${sbom} is invalid or lists no packages — refusing to publish it"
pkgs="$(jq '.packages | length' "${out}/${sbom}")"

# ── 3. Attach (reuse an existing SPDX referrer on re-runs) ──────────────────
sbom_digest=""
find_existing() {
  local json
  json="$(oras discover --format json --artifact-type "$SPDX_TYPE" "$ref")" || return 1
  sbom_digest="$(jq -r --arg t "$SPDX_TYPE" \
    '[.referrers[]? | select(.artifactType == $t) | .digest] | first // empty' <<<"$json")"
}
attach() {
  # Run from $out so the layer's title annotation is a bare filename.
  sbom_digest="$(cd "$out" && oras attach --artifact-type "$SPDX_TYPE" \
    --format go-template='{{.digest}}' "$ref" "${sbom}:${SPDX_TYPE}")"
}

retry "oras discover ${ref}" find_existing
if [ -n "$sbom_digest" ]; then
  echo "SBOM already attached to ${ref} as ${sbom_digest} — reusing it (re-run)"
else
  retry "oras attach ${ref}" attach
fi
[[ "$sbom_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || die 1 "could not determine the attached SBOM digest (got '${sbom_digest}')"

# ── 4. Sign the SBOM artifact (keyless; hash-only transparency-log entry) ───
retry "cosign sign ${repo}@${sbom_digest}" cosign sign --yes "${repo}@${sbom_digest}"

line="${ref} → sbom ${repo}@${sbom_digest} (${pkgs} packages, signed)"
echo "$line"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf -- '- **SBOM (%s):** `%s`\n' "$arch" "$line" >> "$GITHUB_STEP_SUMMARY"
fi
