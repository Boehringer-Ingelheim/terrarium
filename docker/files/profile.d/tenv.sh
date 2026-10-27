# shellcheck shell=bash
# /etc/profile.d/tenv.sh — put tenv's managed binaries on PATH for login shells.
# Sourced, not executed. Was a heredoc in Dockerfile.terrarium; now a static
# file so hadolint can parse the Dockerfile (INFIAAS-11916 code review).
if command -v tenv >/dev/null 2>&1; then
  if tenv --help 2>&1 | grep -q 'update-path'; then
    TENV_NEW_PATH="$( (/usr/bin/tenv update-path) 2>/dev/null || true)"
    if [ -n "$TENV_NEW_PATH" ]; then
      case ":$PATH:" in *":$TENV_NEW_PATH:"*) : ;; *) PATH="$TENV_NEW_PATH:$PATH" ;; esac
    fi
  elif tenv --help 2>&1 | grep -q 'init'; then
    eval "$(/usr/bin/tenv init - bash 2>/dev/null)" || true
  fi
fi
export PATH
