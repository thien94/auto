#!/usr/bin/env bash
#
# auto installer (ROS1 + ROS2 autonomic helpers)
# https://github.com/thien94/auto
#
# What this does (with almost zero user configuration required afterwards):
#   - Copies improved udev rules for common robotics USB-serial devices (FTDI, STM32 ACM, etc.)
#     so they appear as stable /dev/sensors/... names.
#   - Safely appends a single source line to your shell rc file(s) (.bashrc and/or .zshrc)
#     using markers so it is idempotent. Uses the *actual* clone path (not hardcoded ~/auto).
#
# After running:
#   - Open a *new* terminal (or source your rc file).
#   - `ros`, `ck`, `rosmaster`, `rosdomain`, `rosenv`, `rosunsource`, `cw`, `cs`, `s` become available.
#   - `ck` works from any subdirectory inside any catkin or colcon workspace (ROS1 or ROS2).
#   - A common workspace under ~/ will be auto-activated on new shells if it has been built at least once.
#
# Options:
#   --no-udev     Skip udev rule installation
#   --no-rc       Skip shell rc modification
#   --dry-run     Print actions without changing files
#   -h, --help    Show help

set -euo pipefail

AUTO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_START="# >>> auto-ros (https://github.com/thien94/auto) >>>"
MARKER_END="# <<< auto-ros <<<"
# Quote path so spaces / unusual home dirs are safe in rc files
SOURCE_LINE="source \"${AUTO_DIR}/myros.sh\""

DO_UDEV=1
DO_RC=1
DRY_RUN=0

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \?//'
  echo "Install directory: $AUTO_DIR"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-udev) DO_UDEV=0 ;;
    --no-rc)   DO_RC=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo " [dry-run] $*"
  else
    "$@"
  fi
}

echo "==> Installing auto (autonomic ROS1 + ROS2 helpers)..."
echo "    AUTO_DIR=$AUTO_DIR"

# --- 1. Install udev rules (best-effort; non-fatal if no sudo or no rules dir) ---
if [ "$DO_UDEV" = "1" ] && [ -d "$AUTO_DIR/rules" ]; then
  echo " -> Installing udev rules to /etc/udev/rules.d/ (sudo may be required)..."
  if [ "$DRY_RUN" = "1" ]; then
    echo " [dry-run] sudo cp $AUTO_DIR/rules/* /etc/udev/rules.d/"
  elif sudo cp "$AUTO_DIR"/rules/* /etc/udev/rules.d/ 2>/dev/null; then
    echo " -> Reloading udev rules..."
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
    echo "    udev rules installed. Devices should now have stable names like /dev/sensors/ftdi_XXXX or /dev/sensors/acm_XXXX"
    echo "    (You may need to unplug/replug devices, or run the udevadm commands manually.)"
  else
    echo "    (Skipped udev rules or insufficient permissions. You can copy them manually later.)"
  fi
elif [ "$DO_UDEV" = "0" ]; then
  echo " -> Skipping udev rules (--no-udev)"
fi

# --- 2. Safe, idempotent append / update of the source line in shell rc files ---
add_to_rc() {
  local rc="$1"
  if [ ! -f "$rc" ]; then
    return 0
  fi

  if grep -q "auto-ros" "$rc" 2>/dev/null; then
    # Already installed: refresh the source line path if the block exists (clone moved).
    if [ "$DRY_RUN" = "1" ]; then
      echo " [dry-run] would refresh auto-ros block in $rc -> $SOURCE_LINE"
      return 0
    fi
    # Replace content between markers when present; otherwise leave alone.
    if grep -q "$MARKER_START" "$rc" 2>/dev/null; then
      local tmp
      tmp=$(mktemp)
      awk -v start="$MARKER_START" -v end="$MARKER_END" -v line="$SOURCE_LINE" '
        $0 == start { print; print line; skip=1; next }
        $0 == end   { skip=0; print; next }
        !skip       { print }
      ' "$rc" > "$tmp" && mv "$tmp" "$rc"
      echo " -> Refreshed auto-ros block in $rc"
    else
      echo " -> $rc already contains auto-ros configuration (skipped)"
    fi
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo " [dry-run] append to $rc:"
    echo "    $MARKER_START"
    echo "    $SOURCE_LINE"
    echo "    $MARKER_END"
    return 0
  fi

  {
    echo ""
    echo "$MARKER_START"
    echo "$SOURCE_LINE"
    echo "$MARKER_END"
  } >> "$rc"
  echo " -> Added source line to $rc"
}

if [ "$DO_RC" = "1" ]; then
  echo " -> Configuring shell startup..."
  add_to_rc "$HOME/.bashrc"
  add_to_rc "$HOME/.zshrc"
else
  echo " -> Skipping shell rc (--no-rc)"
  echo "    Manually add: $SOURCE_LINE"
fi

echo ""
echo "==> Done."
echo ""
echo "Next steps (almost zero config):"
echo "  1. Close this terminal and open a new one (or: source ~/.bashrc)"
echo "  2. If you have a workspace with a common name (ws, catkin_ws, ros_ws, colcon_ws, ros2_ws ...)"
echo "     under your home directory and it has been built at least once, it will be activated automatically."
echo "  3. From anywhere inside a workspace tree, just run:"
echo "        ck                 # builds + sources the overlay (ROS1 or ROS2, auto-detected)"
echo "        ck --this          # build only the package containing your current directory"
echo "        ros                # (re)activate a workspace (from cwd or common defaults)"
echo "        rosunsource        # clear polluted ROS env (optional; or ROS_AUTO_CLEAN=1)"
echo "        rosmaster 192.168.1.42"
echo "        rosdomain 7"
echo "        rosenv"
echo ""
echo "If your main workspace has a non-standard name/location, simply cd into it (or any package dir)"
echo "and run 'ck' or 'ros' — it will discover the tree automatically."
echo "Or set: export ROS_AUTO_WS_CANDIDATES=\"\$HOME/my_ws\""
echo ""
echo "Using direnv? Set ROS_AUTO_ACTIVATE=0 so auto does not fight directory-based envs."
echo ""
echo "See README.md for more (multiple workspaces, udev details, overrides, alternatives)."
echo ""
echo "Author history: original by Wang Chen / Jeffsan; updated for autonomic + ROS1/ROS2 by thien."
