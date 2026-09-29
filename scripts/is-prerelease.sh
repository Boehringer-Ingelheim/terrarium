#!/usr/bin/env bash
# Classify a git release tag as a pre-release or a release (INFIAAS-11804, B4).
#
# Single source of truth for the `latest` decision in main.yaml (tag-push
# manifest) and release.yaml (release/dispatch manifest). Before this, main.yaml
# added `latest` for EVERY `v*` tag, so a pushed `-pre` tag would have moved it,
# and release.yaml used its own unanchored `-(pre|alpha|beta|rc)` regex.
#
# Rule (docs/tagging-standard.md):
#   vX.Y.Z           -> release      -> prints "false"
#   vX.Y.Z-<suffix>  -> pre-release  -> prints "true"   (any semver pre-release
#                       suffix: -pre, -pre.1, -alpha.N, -beta.N, -rc.N, ...)
#   anything else    -> exit 2       (fail closed: an unrecognised tag must
#                       never be classified, so it can never move `latest`)
#
# Usage: scripts/is-prerelease.sh <tag>
set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: is-prerelease.sh <vX.Y.Z[-suffix]>" >&2; exit 2; }
tag="$1"

num='(0|[1-9][0-9]*)'
ident='[0-9A-Za-z-]+'
re_release="^v${num}\.${num}\.${num}$"
re_prerelease="^v${num}\.${num}\.${num}-${ident}(\.${ident})*$"

if [[ "$tag" =~ $re_release ]]; then
  echo false
elif [[ "$tag" =~ $re_prerelease ]]; then
  echo true
else
  echo "ERROR: not a v-prefixed semver tag (vX.Y.Z or vX.Y.Z-<suffix>): '${tag}'" >&2
  exit 2
fi
