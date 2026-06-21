#!/usr/bin/env bash
# Compatibility shim for legacy aliases: alias ck="source ~/auto/ck.sh"
#
# The real implementation is the `ck` function defined in myros.sh.
# This allows old muscle-memory aliases (and any scripts that source ck.sh directly)
# to continue working after the autonomic update.
#
# New recommended usage (no sourcing needed after login):
#   ck [package-or-args...]
#   ck --this          (build package in current directory, colcon/catkin_tools)
#   ck my_pkg another_pkg

_auto_shim_root() {
  local src="${BASH_SOURCE[0]:-$0}"
  if command -v readlink >/dev/null 2>&1; then
    local resolved
    resolved=$(readlink -f "$src" 2>/dev/null) || resolved=""
    [ -n "$resolved" ] && src="$resolved"
  fi
  dirname "$src"
}

if ! declare -f ck >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$(_auto_shim_root)/myros.sh" 2>/dev/null || \
  source "${AUTO_ROOT:-$HOME/auto}/myros.sh" 2>/dev/null || true
fi

ck "$@"
