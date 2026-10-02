#!/usr/bin/env bash
# Common helper functions / variables

 load 'test_helper/bats-support/load'
 load 'test_helper/bats-assert/load'

 # Ensure the user-local bin directory is searchable even for non-login shells
 export PATH="$PATH:$HOME/.local/bin"

 # Short helper for “binary exists and prints a version”
 check_binary() {
   local exe="$1"
   run "$exe" --version
   assert_success
 }

# Return "gid:<gid>" for a group, or empty if not found
get_gid_of_group() {
  local grp="$1"
  getent group "$grp" | awk -F: '{print "gid:"$3}'
}
# Assert a path is group-owned by `devtools` AND has setgid bit
assert_devtools_setgid_dir() {
  local p="$1"
  run bash -lc 'stat -c "%G %a %A %n" '"$p"
  assert_success
  # Expect group=devtools
  [[ "${output}" == devtools* ]] || {
    echo "Expected group 'devtools' for $p, got: ${output}" >&2
    return 1
  }
  # Expect setgid bit (2xxx) and at least g+rwX (775 typical)
  # Check via find -perm -2000
  run bash -lc 'test -d '"$p"' && find '"$p"' -maxdepth 0 -perm -2000 -print -quit'
  assert_success
  [[ -n "${output}" ]] || {
    echo "Expected setgid bit on directory $p" >&2
    return 1
  }
}

# Echo 1 if PATH contains a segment, else 0
path_contains() {
  local seg="$1"
  case ":$PATH:" in
    *":$seg:"*) echo 1;;
    *) echo 0;;
  esac
}


# Usage: check_version xorriso -version
check_version() {
  local exe="$1"; shift
  run "$exe" "$@"
  assert_success
}

# Assert that a tool reports exactly the version pinned in the image ENV.
# Usage: assert_pinned_version GO_VERSION go version
#   - fails if the pin variable is unset/empty (a missing ENV would otherwise
#     make any --partial match pass vacuously);
#   - tolerates a leading "v" on either side (TERRAFORM_DOCS_VERSION=v0.18.0,
#     `helm version` prints v3.x);
#   - anchors the match so 1.26.8 does not match 1.26.80 or 11.26.8;
#   - returns explicitly after each assertion, so it also fails correctly when
#     called without errexit (e.g. wrapped in `run`).
assert_pinned_version() {
  local var="$1"; shift
  local want="${!var:-}"
  want="${want#v}"
  [ -n "$want" ] || { echo "$var is not set in the image environment" >&2; return 1; }
  run "$@"
  assert_success || return 1
  assert_output --regexp "(^|[^0-9.])v?${want//./\\.}([^0-9]|$)" || return 1
}
