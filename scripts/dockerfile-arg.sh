#!/usr/bin/env bash
# Read a single ARG default value out of the terrarium Dockerfile.
#
# Replaces the inline `arg_val()` one-liner previously duplicated across
# .github/workflows/{main,release}.yaml (four copies). Unlike that helper,
# this one FAILS LOUDLY when the ARG is missing or has an empty default,
# instead of silently returning "" and letting a stale/empty --build-arg
# mask a version bump (see research.md §5).
#
# Usage: scripts/dockerfile-arg.sh <ARG_NAME> [dockerfile]
set -euo pipefail

name="${1:?usage: dockerfile-arg.sh <ARG_NAME> [dockerfile]}"
df="${2:-docker/Dockerfile.terrarium}"

[ -f "$df" ] || { echo "ERROR: dockerfile not found: ${df}" >&2; exit 1; }

val="$(grep -m1 "^ARG ${name}=" "$df" | cut -d= -f2- || true)"
[ -n "$val" ] || { echo "ERROR: ARG ${name} not found (or empty) in ${df}" >&2; exit 1; }

printf '%s' "$val"
