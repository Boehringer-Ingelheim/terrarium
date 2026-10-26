#!/usr/bin/env bash
# Decide whether a release tag may move `latest` and `{{major}}`
# (INFIAAS-11916, S1.6).
#
# Before this guard, every non-pre-release tag moved `latest` (main.yaml and
# release.yaml) and the per-arch `latest-linux-<arch>` and `<major>-linux-<arch>`
# tags (main.yaml metadata flavour). Publishing a maintenance release such as
# v4.8.4 after v4.9.6 would therefore have pointed `latest` and `4` back at 4.8.
#
# Rule: the tag moves `latest` only when it is
#   1. a release (scripts/is-prerelease.sh prints "false"; the classifier is
#      reused, not duplicated), AND
#   2. the highest stable vX.Y.Z tag by `sort -V` across `git tag -l` and
#      `git ls-remote --tags <remote>`. CI checkouts are shallow and carry no
#      tags, so the remote is the source that matters there. Local tags cover a
#      freshly created tag that has not been pushed yet.
#
# Prints "true" or "false" on stdout, like is-prerelease.sh, so callers share
# one pattern:
#   vX.Y.Z-<suffix>                  -> false  (pre-releases never move latest)
#   vX.Y.Z below the highest release -> false
#   vX.Y.Z equal to the highest      -> true
# Exits 2 (fail closed: no decision, so `latest` cannot move) when:
#   - the tag is not a v-prefixed semver tag (is-prerelease.sh's own exit 2);
#   - `git ls-remote` fails (no network, unknown remote);
#   - no stable tag exists at all, locally or on the remote;
#   - the release tag exists neither locally nor on the remote.
# Tags that are not vX.Y.Z[-suffix] (e.g. `latest`, `v1.0`) are ignored when
# computing the highest release.
#
# Usage: scripts/is-highest-release.sh <tag>
# Env:   HIGHEST_RELEASE_REMOTE  remote for `git ls-remote` (default: origin)
set -euo pipefail

die() { echo "ERROR: is-highest-release: $*" >&2; exit 2; }

[ "$#" -eq 1 ] || { echo "usage: is-highest-release.sh <vX.Y.Z[-suffix]>" >&2; exit 2; }
tag="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
classify="$here/is-prerelease.sh"

# 1. Shape and pre-release check. An invalid tag exits 2 here (set -e).
is_pre="$("$classify" "$tag")"
if [ "$is_pre" = true ]; then
  echo false
  exit 0
fi

# 2. Every tag known locally or on the remote.
remote="${HIGHEST_RELEASE_REMOTE:-origin}"
local_tags="$(git tag -l 'v*')" || die "git tag -l failed (not a git checkout?)"
remote_refs="$(git ls-remote --tags --refs "$remote" 'refs/tags/v*')" \
  || die "git ls-remote --tags ${remote} failed (refusing to decide)"
remote_tags="$(printf '%s\n' "$remote_refs" | sed -n 's#^[0-9a-f]*[[:space:]]*refs/tags/##p')"
all_tags="$(printf '%s\n%s\n' "$local_tags" "$remote_tags" | sed '/^$/d' | sort -u)"

known=false
stable=()
while IFS= read -r t; do
  [ -n "$t" ] || continue
  [ "$t" = "$tag" ] && known=true
  # Classify with the shared rule. Unrecognised tags exit 2 and are skipped.
  if c="$("$classify" "$t" 2>/dev/null)" && [ "$c" = false ]; then
    stable+=("$t")
  fi
done <<<"$all_tags"

[ "${#stable[@]}" -gt 0 ] || die "no stable vX.Y.Z tag found locally or on ${remote}"
[ "$known" = true ] || die "tag ${tag} exists neither locally nor on ${remote}"

highest="$(printf '%s\n' "${stable[@]}" | sort -V | tail -n1)"
if [ "$tag" = "$highest" ]; then
  echo true
else
  echo "is-highest-release: ${tag} is not the highest release (${highest})" >&2
  echo false
fi
