#!/usr/bin/env bash
# auto - autonomic ROS helpers for ROS1 + ROS2 (minimal user configuration)
# Source this file from your ~/.bashrc or ~/.zshrc (install.sh does this safely).
#
# Philosophy:
# - Zero (or near-zero) configuration after clone + install.
# - Auto-detects ROS distro(s) present in /opt/ros.
# - Auto-discovers workspaces by walking up from cwd or trying common names under $HOME.
# - `ck` (build) works from *any* subdirectory inside a catkin/colcon workspace tree.
# - After build, the workspace is automatically sourced in the current shell.
# - The workspace's own setup file is sourced; it pulls in the correct base ROS1/ROS2 underlay.
#
# Main user-facing commands (available after sourcing):
#   ros [optional/path/to/ws]   - Activate/switch workspace (autonomic if no arg)
#   ck [args...]                - Build from anywhere (auto-detects build system)
#   ckb                         - Alias to ck (backward compat)
#   rosmaster [host]            - Set ROS_MASTER_URI (ROS1)
#   rosdomain [id]              - Set ROS_DOMAIN_ID (ROS2)
#   rosenv                      - Show relevant ROS environment variables
#   rosunsource                 - Strip common ROS env vars (fix polluted shells)
#   cw / cs / s                 - cd to ws root / src / re-source current ws
#
# Environment overrides (rarely needed):
#   ROS_DISTRO=...              - Force a specific base distro at login
#   ROS_AUTO_VERBOSE=1          - Show extra messages
#   ROS_AUTO_ACTIVATE=0         - Disable auto-activation of a default ws on new shell
#   ROS_AUTO_CLEAN=1            - Before activating a ws, clear conflicting ROS1/ROS2 vars
#   ROS_AUTO_WS_CANDIDATES=...  - Space-separated extra/default workspace paths to try
#
# See README.md for full details, udev notes, and alternatives (direnv, etc.).

# Guard: only source once per shell (safe to source repeatedly)
if [ -n "${_AUTO_ROS_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
_AUTO_ROS_LOADED=1

# ---------------------------------------------------------------------------
# Paths & shell detection
# ---------------------------------------------------------------------------

# Resolve install directory even when sourced (bash + zsh).
_auto_resolve_root() {
  local src=""
  if [ -n "${BASH_SOURCE[0]:-}" ]; then
    src="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC2296
    src="${(%):-%x}"
  else
    src="$0"
  fi
  # Resolve symlinks where possible
  if command -v readlink >/dev/null 2>&1; then
    local resolved
    resolved=$(readlink -f "$src" 2>/dev/null) || resolved=""
    [ -n "$resolved" ] && src="$resolved"
  fi
  dirname "$src"
}

export AUTO_ROOT="${AUTO_ROOT:-$(_auto_resolve_root)}"

# Prefer zsh setup files when running under zsh, else bash.
_auto_shell_ext() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    echo "zsh"
  else
    echo "bash"
  fi
}

# ---------------------------------------------------------------------------
# Logging & colors
# ---------------------------------------------------------------------------

_ros_log() {
  if [ "${ROS_AUTO_VERBOSE:-0}" = "1" ]; then
    echo "[auto] $*" >&2
  fi
}

_ros_ok()   { echo -e "\033[1;32m[auto]\033[0m $*"; }
_ros_err()  { echo -e "\033[1;31m[auto]\033[0m $*" >&2; }
_ros_info() { echo "[auto] $*"; }

# ---------------------------------------------------------------------------
# Parallelism / primary IP (portable-ish helpers)
# ---------------------------------------------------------------------------

_auto_nproc() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu 2>/dev/null || echo 4
  else
    echo 4
  fi
}

_auto_primary_ip() {
  local ip=""
  # Linux
  if command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' | head -1)
  fi
  # macOS / BSD fallback
  if [ -z "$ip" ] && command -v ipconfig >/dev/null 2>&1; then
    ip=$(ipconfig getifaddr en0 2>/dev/null || true)
  fi
  # ip route fallback (Linux)
  if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
  fi
  echo "${ip:-}"
}

# ---------------------------------------------------------------------------
# Distro preference list (newest / most common first)
# ---------------------------------------------------------------------------

_auto_distro_candidates() {
  # ROS2 then ROS1; extend here as new distros ship.
  echo "kilted jazzy iron humble galactic foxy eloquent dashing rolling noetic melodic kinetic indigo"
}

# ---------------------------------------------------------------------------
# Source a ROS setup file with the right shell extension
# ---------------------------------------------------------------------------

_auto_source_setup() {
  # Usage: _auto_source_setup /path/to/dir_or_file [prefer_local]
  # If given a directory, tries local_setup then setup for the current shell.
  local target="$1"
  local prefer_local="${2:-1}"
  local ext
  ext=$(_auto_shell_ext)
  local f=""

  if [ -f "$target" ]; then
    f="$target"
  elif [ -d "$target" ]; then
    if [ "$prefer_local" = "1" ] && [ -f "$target/local_setup.$ext" ]; then
      f="$target/local_setup.$ext"
    elif [ -f "$target/setup.$ext" ]; then
      f="$target/setup.$ext"
    elif [ "$prefer_local" = "1" ] && [ -f "$target/local_setup.bash" ]; then
      f="$target/local_setup.bash"
    elif [ -f "$target/setup.bash" ]; then
      f="$target/setup.bash"
    fi
  fi

  if [ -z "$f" ] || [ ! -f "$f" ]; then
    return 1
  fi

  # shellcheck disable=SC1090
  source "$f"
  echo "$f"
  return 0
}

# ---------------------------------------------------------------------------
# Primary base ROS underlay (so tools are on PATH early)
# Preference: user ROS_DISTRO > preference list > first dir under /opt/ros
# ---------------------------------------------------------------------------

_ros_source_primary_base() {
  local ext
  ext=$(_auto_shell_ext)

  if [ -n "${ROS_DISTRO:-}" ]; then
    local base="/opt/ros/${ROS_DISTRO}"
    if [ -f "$base/setup.$ext" ] || [ -f "$base/setup.bash" ]; then
      if _auto_source_setup "$base" 0 >/dev/null; then
        _ros_log "Sourced user-specified base $base"
        return 0
      fi
    fi
  fi

  local d
  for d in $(_auto_distro_candidates); do
    if [ -f "/opt/ros/$d/setup.$ext" ] || [ -f "/opt/ros/$d/setup.bash" ]; then
      export ROS_DISTRO="$d"
      if _auto_source_setup "/opt/ros/$d" 0 >/dev/null; then
        _ros_log "Auto-selected and sourced base ROS $d"
        return 0
      fi
    fi
  done

  if [ -d /opt/ros ]; then
    local first
    first=$(ls /opt/ros 2>/dev/null | head -1)
    if [ -n "$first" ]; then
      export ROS_DISTRO="$first"
      if _auto_source_setup "/opt/ros/$first" 0 >/dev/null; then
        _ros_log "Auto-sourced first available base ROS $first"
        return 0
      fi
    fi
  fi

  _ros_log "No ROS installation found under /opt/ros"
  return 1
}

_ros_source_primary_base

# ---------------------------------------------------------------------------
# Basic networking defaults (ROS1 master + ROS2 domain)
# ---------------------------------------------------------------------------

_ros_setup_basic_network() {
  local primary_ip
  primary_ip=$(_auto_primary_ip)

  if [ -n "$primary_ip" ]; then
    export ROS_IP="${ROS_IP:-$primary_ip}"
    export ROS_HOSTNAME="${ROS_HOSTNAME:-$primary_ip}"
  fi

  export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

  if [ -z "${ROS_MASTER_URI:-}" ]; then
    export ROS_MASTER_URI="http://localhost:11311"
  fi
}

_ros_setup_basic_network

# ---------------------------------------------------------------------------
# Workspace discovery
# ---------------------------------------------------------------------------

# True if $1 looks like a ROS workspace root.
_auto_is_ws_root() {
  local dir="$1"
  [ -d "$dir/src" ] || return 1

  [ -d "$dir/.catkin_tools" ] && return 0
  [ -d "$dir/.colcon" ] && return 0
  [ -f "$dir/colcon.pkg" ] && return 0
  { [ -f "$dir/install/local_setup.bash" ] || [ -f "$dir/install/local_setup.zsh" ]; } && return 0
  { [ -f "$dir/install/setup.bash" ] || [ -f "$dir/install/setup.zsh" ]; } && return 0
  { [ -f "$dir/devel/setup.bash" ] || [ -f "$dir/devel/setup.zsh" ]; } && return 0
  [ -d "$dir/install/ament_cmake_index" ] && return 0

  # At least one package marker under src (one level is enough for most trees)
  if compgen -G "$dir/src/*/package.xml" >/dev/null 2>&1; then
    return 0
  fi
  if compgen -G "$dir/src/*/*/package.xml" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# True if workspace has been built at least once (has a setup we can source).
_auto_ws_has_setup() {
  local dir="$1"
  local ext
  ext=$(_auto_shell_ext)
  [ -f "$dir/install/local_setup.$ext" ] || \
  [ -f "$dir/install/setup.$ext" ] || \
  [ -f "$dir/devel/setup.$ext" ] || \
  [ -f "$dir/install/local_setup.bash" ] || \
  [ -f "$dir/install/setup.bash" ] || \
  [ -f "$dir/devel/setup.bash" ]
}

# Find the root of the nearest ROS workspace walking up from a directory.
find_ros_ws_root() {
  local start="${1:-$(pwd)}"
  local dir="$start"

  # Normalize to absolute path when possible
  if command -v realpath >/dev/null 2>&1; then
    dir=$(realpath "$dir" 2>/dev/null || echo "$dir")
  fi

  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if _auto_is_ws_root "$dir"; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# Default / user-extended list of candidate workspace paths.
_auto_ws_candidates() {
  if [ -n "${ROS_AUTO_WS_CANDIDATES:-}" ]; then
    # shellcheck disable=SC2086
    echo $ROS_AUTO_WS_CANDIDATES
    return
  fi
  echo \
    "$HOME/ws" \
    "$HOME/catkin_ws" \
    "$HOME/ros_ws" \
    "$HOME/colcon_ws" \
    "$HOME/ros1_ws" \
    "$HOME/ros2_ws" \
    "$HOME/workspace" \
    "$HOME/dev/ws" \
    "$HOME/ros"
}

# Resolve which setup file to source for a workspace (prints path, returns 0/1).
_auto_ws_setup_file() {
  local ws="$1"
  local ext
  ext=$(_auto_shell_ext)
  local candidate

  for candidate in \
      "$ws/install/local_setup.$ext" \
      "$ws/install/setup.$ext" \
      "$ws/devel/setup.$ext" \
      "$ws/install/local_setup.bash" \
      "$ws/install/setup.bash" \
      "$ws/devel/setup.bash"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Optional env cleanup when switching workspaces (ROS_AUTO_CLEAN=1)
# ---------------------------------------------------------------------------

rosunsource() {
  # Strip the most common ROS1/ROS2 environment pollution so a fresh
  # workspace/distro can be sourced without crosstalk. Not as thorough as
  # starting a new shell, but good enough for daily use.
  unset ROS_PACKAGE_PATH ROS_ROOT ROS_ETC_DIR ROS_MASTER_URI 2>/dev/null || true
  unset ROSLISP_PACKAGE_DIRECTORIES PYTHONPATH CMAKE_PREFIX_PATH 2>/dev/null || true
  unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH 2>/dev/null || true
  unset ROS_VERSION ROS_PYTHON_VERSION 2>/dev/null || true
  # Keep ROS_DISTRO / ROS_DOMAIN_ID / ROS_IP unless caller wants a full reset
  if [ "${1:-}" = "--all" ]; then
    unset ROS_DISTRO ROS_DOMAIN_ID ROS_IP ROS_HOSTNAME RMW_IMPLEMENTATION 2>/dev/null || true
  fi
  _ros_ok "Cleared common ROS environment variables."
}

_auto_maybe_clean_env() {
  if [ "${ROS_AUTO_CLEAN:-0}" = "1" ]; then
    # Quiet version of rosunsource (keep distro/domain/ip)
    unset ROS_PACKAGE_PATH ROS_ROOT ROS_ETC_DIR 2>/dev/null || true
    unset ROSLISP_PACKAGE_DIRECTORIES 2>/dev/null || true
    unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH 2>/dev/null || true
    # Do not unset CMAKE_PREFIX_PATH / PYTHONPATH entirely — too aggressive mid-session.
  fi
}

# ---------------------------------------------------------------------------
# Activate a workspace
#   ros                  # auto: from cwd upward, else first ready common-named ws under ~
#   ros ~/my/special/ws
# ---------------------------------------------------------------------------

ros() {
  local target="${1:-}"
  local ws=""
  local quiet=0
  if [ "$target" = "--quiet" ]; then
    quiet=1
    target="${2:-}"
  fi

  if [ -n "$target" ]; then
    if [ -d "$target" ]; then
      # Allow pointing at a path inside the ws too
      ws=$(find_ros_ws_root "$target") || ws="$target"
    else
      _ros_err "ros: '$target' is not a directory"
      return 1
    fi
  else
    ws=$(find_ros_ws_root "$(pwd)") || true

    if [ -z "$ws" ]; then
      local c
      for c in $(_auto_ws_candidates); do
        if [ -d "$c/src" ] && _auto_ws_has_setup "$c"; then
          ws="$c"
          break
        fi
      done
    fi
  fi

  if [ -z "$ws" ] || [ ! -d "$ws" ]; then
    if [ "$quiet" != "1" ]; then
      echo "ros: No ROS workspace found."
      echo "     - cd into any directory inside your workspace tree and run 'ros' or 'ck'"
      echo "     - or explicitly: ros /path/to/your/workspace"
      echo "     Common names tried under ~ : ws, catkin_ws, ros_ws, colcon_ws, ros2_ws, ..."
      echo "     Override list: export ROS_AUTO_WS_CANDIDATES=\"\$HOME/my_ws \$HOME/other_ws\""
    fi
    return 1
  fi

  local setup_file
  setup_file=$(_auto_ws_setup_file "$ws") || setup_file=""

  if [ -z "$setup_file" ]; then
    if [ "$quiet" != "1" ]; then
      echo "ros: Found workspace at $ws, but no setup file yet."
      echo "     Build it first (e.g. run 'ck' or 'colcon build' / 'catkin build' from the root)."
    fi
    cd "$ws" 2>/dev/null || true
    return 1
  fi

  _auto_maybe_clean_env

  # shellcheck disable=SC1090
  source "$setup_file"
  export AUTO_CURRENT_WS="$ws"

  if [ "$quiet" != "1" ]; then
    _ros_ok "Activated ROS workspace: $ws"
    _ros_ok "Using: $setup_file"
  else
    _ros_log "Activated $ws via $setup_file"
  fi
}

# ---------------------------------------------------------------------------
# Build-system detection
# ---------------------------------------------------------------------------

# Returns: colcon | catkin_tools | catkin_make
_auto_detect_build_system() {
  local ws="${1:-.}"

  # Strong catkin_tools signal wins (even if colcon is installed globally).
  if [ -d "$ws/.catkin_tools" ] && command -v catkin >/dev/null 2>&1; then
    echo "catkin_tools"
    return 0
  fi

  # Strong colcon signals.
  if command -v colcon >/dev/null 2>&1; then
    if [ -f "$ws/install/local_setup.bash" ] || [ -f "$ws/install/local_setup.zsh" ] || \
       [ -d "$ws/install/ament_cmake_index" ] || \
       [ -d "$ws/.colcon" ] || \
       [ -f "$ws/colcon.pkg" ] || \
       [ -f "$ws/COLCON_IGNORE" ]; then
      echo "colcon"
      return 0
    fi
    # Heuristic: ament / ROS2 package markers in src
    if grep -l -m1 -E '<build_type>ament_(cmake|python)</build_type>' \
         "$ws"/src/*/package.xml "$ws"/src/*/*/package.xml 2>/dev/null | head -1 | grep -q .; then
      echo "colcon"
      return 0
    fi
  fi

  # Classic ROS1: devel/ or catkin tools absent but catkin_make available
  if [ -f "$ws/devel/setup.bash" ] || [ -f "$ws/devel/setup.zsh" ] || [ -d "$ws/devel" ]; then
    if [ -d "$ws/.catkin_tools" ] && command -v catkin >/dev/null 2>&1; then
      echo "catkin_tools"
    else
      echo "catkin_make"
    fi
    return 0
  fi

  # No build artifacts yet: prefer catkin_tools if initialized, else colcon if only tool present,
  # else catkin_make for ROS1-style trees.
  if [ -d "$ws/.catkin_tools" ] && command -v catkin >/dev/null 2>&1; then
    echo "catkin_tools"
    return 0
  fi
  if command -v colcon >/dev/null 2>&1 && ! command -v catkin_make >/dev/null 2>&1; then
    echo "colcon"
    return 0
  fi
  if command -v catkin >/dev/null 2>&1 && [ -d "$ws/.catkin_tools" ]; then
    echo "catkin_tools"
    return 0
  fi
  if command -v catkin_make >/dev/null 2>&1; then
    echo "catkin_make"
    return 0
  fi
  if command -v colcon >/dev/null 2>&1; then
    echo "colcon"
    return 0
  fi

  echo "unknown"
  return 1
}

# ---------------------------------------------------------------------------
# ck: build from anywhere, then re-source overlay in this shell
# ---------------------------------------------------------------------------

ck() {
  local orig_dir
  orig_dir=$(pwd)

  local ws
  ws=$(find_ros_ws_root "$orig_dir") || {
    _ros_err "ck: Not inside a ROS workspace (no 'src/' directory with packages found upward)."
    echo "    cd into a package or the workspace root and try again."
    return 1
  }

  _ros_info "Workspace root: $ws"
  cd "$ws" || return 1

  local build_sys
  build_sys=$(_auto_detect_build_system "$ws") || build_sys="unknown"
  _ros_info "Build system: $build_sys"

  local jobs
  jobs=$(_auto_nproc)
  local after_source=""
  local rc=0
  local cmd=""

  # Light ergonomics: `ck --this` / `ck .` builds the package containing cwd
  # (colcon --packages-select / catkin build <pkg>) when we can resolve it.
  local this_pkg=""
  if [ "${1:-}" = "--this" ] || [ "${1:-}" = "." ]; then
    shift || true
    local d="$orig_dir"
    while [ "$d" != "/" ] && [ "$d" != "$ws" ]; do
      if [ -f "$d/package.xml" ]; then
        this_pkg=$(basename "$d")
        break
      fi
      d=$(dirname "$d")
    done
  fi

  # Build argv as a string + eval is avoided for the tool itself; we pass "$@"
  # through directly. this_pkg is injected via a small prefix when set.
  case "$build_sys" in
    colcon)
      after_source="install/local_setup.$(_auto_shell_ext)"
      [ -f "$after_source" ] || after_source="install/local_setup.bash"
      # colcon accepts --parallel-workers, not make-style -jN
      if [ -n "$this_pkg" ]; then
        cmd="colcon build --symlink-install --parallel-workers ${jobs} --packages-select ${this_pkg}"
      else
        cmd="colcon build --symlink-install --parallel-workers ${jobs}"
      fi
      ;;
    catkin_tools)
      after_source="devel/setup.$(_auto_shell_ext)"
      [ -f "$after_source" ] || after_source="devel/setup.bash"
      if [ -n "$this_pkg" ]; then
        cmd="catkin build -j${jobs} --no-status ${this_pkg}"
      else
        cmd="catkin build -j${jobs} --no-status"
      fi
      ;;
    catkin_make)
      after_source="devel/setup.$(_auto_shell_ext)"
      [ -f "$after_source" ] || after_source="devel/setup.bash"
      cmd="catkin_make -j${jobs}"
      ;;
    *)
      _ros_err "ck: Could not detect build system (need colcon, catkin, or catkin_make in PATH)."
      cd "$orig_dir" || true
      return 1
      ;;
  esac

  _ros_info "Running: $cmd $*"
  # shellcheck disable=SC2086
  if $cmd "$@"; then
    _ros_ok "Build succeeded."

    if [ -f "$after_source" ]; then
      # shellcheck disable=SC1090
      source "$after_source"
      export AUTO_CURRENT_WS="$ws"
      _ros_ok "Workspace re-sourced (overlay active)."
    else
      local fallback
      fallback=$(_auto_ws_setup_file "$ws") || fallback=""
      if [ -n "$fallback" ]; then
        # shellcheck disable=SC1090
        source "$fallback"
        export AUTO_CURRENT_WS="$ws"
        _ros_ok "Workspace re-sourced (overlay active)."
      fi
    fi
    rc=0
  else
    _ros_err "Build failed."
    rc=1
  fi

  cd "$orig_dir" || true
  return "$rc"
}

# Backward-compat alias
ckb() {
  ck "$@"
}

# ---------------------------------------------------------------------------
# Ergonomic helpers
# ---------------------------------------------------------------------------

cw() {
  local ws
  ws=$(find_ros_ws_root "$(pwd)") || {
    # Fall back to first candidate with setup, or any candidate that exists
    local c
    for c in $(_auto_ws_candidates); do
      if [ -d "$c/src" ]; then
        ws="$c"
        break
      fi
    done
  }
  if [ -z "${ws:-}" ]; then
    _ros_err "cw: No workspace found"
    return 1
  fi
  cd "$ws" || return 1
}

cs() {
  cw && cd src 2>/dev/null || { _ros_err "cs: src/ not found in workspace"; return 1; }
}

# Re-source whatever the current workspace overlay is
s() {
  local ws
  ws=$(find_ros_ws_root "$(pwd)") || ws="${AUTO_CURRENT_WS:-}"
  if [ -z "$ws" ] || [ ! -d "$ws" ]; then
    _ros_err "s: Not inside a workspace tree"
    return 1
  fi

  local setup_file
  setup_file=$(_auto_ws_setup_file "$ws") || {
    _ros_err "s: No setup file found in $ws"
    return 1
  }

  _auto_maybe_clean_env
  # shellcheck disable=SC1090
  source "$setup_file"
  export AUTO_CURRENT_WS="$ws"
  _ros_ok "Re-sourced workspace overlay ($setup_file)."
}

# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------

rosmaster() {
  if [ $# -eq 0 ]; then
    echo "ROS_MASTER_URI=${ROS_MASTER_URI:-unset}"
    return 0
  fi
  local host="$1"
  export ROS_MASTER_URI="http://${host}:11311"
  if [ -z "${ROS_IP:-}" ] && [ -z "${ROS_HOSTNAME:-}" ]; then
    local ip
    ip=$(_auto_primary_ip)
    if [ -n "$ip" ]; then
      export ROS_IP="$ip"
      export ROS_HOSTNAME="$ip"
    fi
  fi
  echo "ROS_MASTER_URI=$ROS_MASTER_URI"
}

rosdomain() {
  if [ $# -eq 0 ]; then
    echo "ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}"
    return 0
  fi
  export ROS_DOMAIN_ID="$1"
  echo "ROS_DOMAIN_ID=$ROS_DOMAIN_ID (ROS 2 discovery)"
}

rosenv() {
  echo "=== auto ROS environment ==="
  echo "AUTO_ROOT=${AUTO_ROOT:-?}"
  echo "AUTO_CURRENT_WS=${AUTO_CURRENT_WS:-?}"
  echo "ROS_DISTRO=${ROS_DISTRO:-?}"
  echo "ROS_AUTO_ACTIVATE=${ROS_AUTO_ACTIVATE:-1}  ROS_AUTO_CLEAN=${ROS_AUTO_CLEAN:-0}  ROS_AUTO_VERBOSE=${ROS_AUTO_VERBOSE:-0}"
  env | grep -E '^(ROS_|RMW_|AMENT_|COLCON_)' | sort || true
  local cur_ws
  cur_ws=$(find_ros_ws_root "$(pwd)" 2>/dev/null || echo "none")
  echo "Current workspace (detected from cwd): $cur_ws"
  if [ -n "${cur_ws:-}" ] && [ "$cur_ws" != "none" ]; then
    echo "Build system (detected): $(_auto_detect_build_system "$cur_ws" 2>/dev/null || echo unknown)"
  fi
}

# ---------------------------------------------------------------------------
# Aliases (uppercase variants for old muscle memory)
# ---------------------------------------------------------------------------

alias CK='ck'
alias CKB='ckb'

# ---------------------------------------------------------------------------
# Autonomic behavior on shell startup
# ---------------------------------------------------------------------------

# True if a *workspace* overlay already looks active (not merely /opt/ros base).
# Sourcing /opt/ros/<distro> sets AMENT_PREFIX_PATH, so we must not treat that alone
# as "already activated" or login auto-activate never runs on ROS 2 hosts.
_auto_workspace_overlay_active() {
  [ -n "${AUTO_CURRENT_WS:-}" ] && return 0
  [ -n "${ROS_PACKAGE_PATH:-}" ] && return 0
  [ -n "${COLCON_PREFIX_PATH:-}" ] && return 0
  return 1
}

if [ "${ROS_AUTO_ACTIVATE:-1}" != "0" ]; then
  # Skip if direnv owns the environment, or a workspace overlay is already loaded.
  if [ -z "${DIRENV_DIR:-}" ] && ! _auto_workspace_overlay_active; then
    ros --quiet || true
  fi
fi

_ros_log "auto helpers loaded (ros, ck, rosunsource, rosmaster, rosdomain, rosenv, cw, cs, s). ROS_DISTRO=${ROS_DISTRO:-none} AUTO_ROOT=$AUTO_ROOT"
