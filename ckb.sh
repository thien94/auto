#!/usr/bin/env bash
# Compatibility shim for legacy aliases: alias ckb="source ~/auto/ckb.sh"
#
# After the autonomic update, `ckb` is simply an alias to `ck`.
# This file keeps old aliases working.

_auto_shim_root() {
  local src="${BASH_SOURCE[0]:-$0}"
  if command -v readlink >/dev/null 2>&1; then
    local resolved
    resolved=$(readlink -f "$src" 2>/dev/null) || resolved=""
    [ -n "$resolved" ] && src="$resolved"
  fi
  dirname "$src"
}

if ! declare -f ckb >/dev/null 2>&1 && ! declare -f ck >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$(_auto_shim_root)/myros.sh" 2>/dev/null || \
  source "${AUTO_ROOT:-$HOME/auto}/myros.sh" 2>/dev/null || true
fi

ckb "$@"
