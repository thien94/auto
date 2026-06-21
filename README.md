# auto

**Autonomic ROS1 + ROS2 shell helpers with almost zero configuration.**

A small, battle-tested collection of scripts that make daily ROS development (ROS 1 and ROS 2) more pleasant:

- No hard-coding distro or workspace folder names in `myros.sh`.
- `ck` (build) works from **any subdirectory** inside a workspace — walks up the tree, auto-detects `colcon` / `catkin build` / `catkin_make`, builds, then sources the result so `ros2 run` / `rosrun` work immediately.
- New terminals can auto-activate a "ready" workspace (common names under `~`).
- Works on machines that have only ROS 1, only ROS 2, or both.
- Stable device names for common USB-serial hardware (FTDI, STM32 ACM, etc.).
- Helpers: `ros`, `rosmaster`, `rosdomain`, `rosenv`, `rosunsource`, `cw`, `cs`, `s`.

Goal: **"clone → ./install.sh → open new terminal → it mostly just works"**.

Clone anywhere you like (`~/auto`, `~/Projects/auto`, …). `install.sh` and `myros.sh` resolve their own path; you do **not** have to clone to `~/auto`.

> **Platform note:** Designed for **Linux** (especially Ubuntu/Debian with ROS under `/opt/ros`). WSL2 usually works for the shell helpers; udev/serial is host-specific. Not a general Windows/macOS ROS manager.

## Installation (one time)

```bash
git clone https://github.com/thien94/auto   # any path is fine
cd auto
./install.sh
```

Useful flags:

```bash
./install.sh --dry-run     # show what would change
./install.sh --no-udev     # skip /etc/udev/rules.d
./install.sh --no-rc       # skip .bashrc / .zshrc; print the source line only
```

`install.sh` will:

- Copy improved udev rules (with `ID_MM_DEVICE_IGNORE`, safer permissions, comments).
- Append (or refresh) a marker-bounded `source "/absolute/path/to/auto/myros.sh"` line in `~/.bashrc` and/or `~/.zshrc`. Re-running after moving the clone updates that path.

Then **open a new terminal** (or `source ~/.bashrc`).

## What you get (the autonomic experience)

After a new shell:

- If you have a workspace with a common name (`ws`, `catkin_ws`, `ros_ws`, `colcon_ws`, `ros1_ws`, `ros2_ws`, `workspace`, …) under your home directory **and it has been built at least once**, it may be activated automatically (workspace `install/…` or `devel/…` setup is sourced — it knows which ROS distro it was built for).
- The newest/recent ROS distro found in `/opt/ros` is sourced as a base so `ros2`, `roslaunch`, `rqt`, etc. are in `PATH` early.
- Sensible `ROS_IP` / `ROS_HOSTNAME` / `ROS_DOMAIN_ID=0` are set when unset.

You normally never have to touch configuration again.

If you use **direnv** (or similar) for per-project envs, set `ROS_AUTO_ACTIVATE=0` so login activation does not fight directory-based loading.

## Daily commands (all provided by `myros.sh`)

| Command | Description |
|---------|-------------|
| `ros` | Activate workspace. No arg: walk up from cwd, else first ready common-named ws under `~`. |
| `ros /path/to/ws` | Explicitly activate any workspace (path may be inside the tree). |
| `ck [args…]` | Build from anywhere. Auto-detects build system + sources overlay afterwards. |
| `ck --this` / `ck .` | Build only the package whose `package.xml` is nearest to cwd (colcon/catkin_tools). |
| `ckb` | Same as `ck` (backward compat). |
| `cw` | `cd` to the root of the current (or a default) workspace. |
| `cs` | `cw` then `cd src`. |
| `s` | Re-source the current workspace overlay (quick after `package.xml` changes, etc.). |
| `rosmaster 192.168.1.42` | Set `ROS_MASTER_URI` (and `ROS_IP`/`ROS_HOSTNAME` if needed) for ROS 1 multi-machine. |
| `rosdomain 7` | Set `ROS_DOMAIN_ID` (ROS 2). |
| `rosenv` | Dump relevant `ROS_*` / `AMENT_*` / `COLCON_*` variables + detected workspace/build system. |
| `rosunsource` | Clear common ROS env vars (fix a polluted shell). `rosunsource --all` also clears distro/domain/IP. |

`ck` examples:

```bash
cd ~/my_project/some/deep/package
ck                    # builds whole workspace (colcon / catkin / catkin_make as appropriate)
ck my_pkg             # pass-through args to the underlying tool
ck --this             # package containing cwd only (colcon/catkin_tools)
```

Everything is implemented as functions (not only aliases), so scripts can call them after sourcing `myros.sh`.

## How ROS 1 + ROS 2 support works

- `find_ros_ws_root` walks upward looking for a `src/` directory plus package markers or build artifacts (`.catkin_tools`, `.colcon`, `install/…`, `devel/…`, `package.xml` files, …).
- `ck` classifies the workspace **before** choosing a tool: `.catkin_tools` prefers `catkin build` even if `colcon` is installed globally; ament/`install/local_setup` signals prefer `colcon`; classic `devel/` prefers `catkin_make`.
- When we `source` a workspace's `install/local_setup.*` (ROS 2) or `devel/setup.*` (ROS 1), that generated file sources the correct underlay (`/opt/ros/<distro>`). No manual distro switching required.
- Under **zsh**, setup files prefer `*.zsh` when present, with fallback to `*.bash`.
- At login we still source *one* primary base (preferring recent ROS 2) so tools are available before you activate a workspace.
- Optional `ROS_AUTO_CLEAN=1` lightly clears ROS1/ROS2 path vars before `ros`/`s` to reduce crosstalk (not as strong as a new shell; use `rosunsource` for a heavier scrub).

## Customization (you almost never need this)

| Variable | Default | Meaning |
|----------|---------|---------|
| `ROS_DISTRO` | auto | Force a specific base distro at login |
| `ROS_AUTO_ACTIVATE` | `1` | `0` disables auto-activation on new shells |
| `ROS_AUTO_VERBOSE` | `0` | `1` prints debug traces from helpers |
| `ROS_AUTO_CLEAN` | `0` | `1` scrub some ROS path vars before activating/re-sourcing |
| `ROS_AUTO_WS_CANDIDATES` | built-in list | Space-separated workspace paths to try when not inside a tree |
| `AUTO_ROOT` | detected | Override install directory (normally set automatically) |

If your main workspace has a non-standard name, `cd` into it and run `ros` or `ck`, or set `ROS_AUTO_WS_CANDIDATES`.

For advanced multi-workspace / mixed ROS1+ROS2 workflows, consider **direnv** / [ros-direnv](https://github.com/wentasah/ros-direnv), [ros_management_tools](https://github.com/oKermorgant/ros_management_tools), or [robot_folders](https://github.com/fzi-forschungszentrum-informatik/robot_folders). This repo stays minimal for the common case.

Pair `auto` with standard ROS 2 ergonomics such as `~/.colcon/defaults.yaml` and [colcon mixins](https://github.com/colcon/colcon-mixin-repository) (ninja, ccache, compile-commands); `ck` does not replace those.

## udev rules for persistent device names

The `rules/` directory contains improved rules for:

- STM32 virtual COM ports (`/dev/sensors/acm_<serial>`)
- Classic FTDI FT232 (`/dev/sensors/ftdi_<serial>`)

Enhancements over typical lab copies:

- `ENV{ID_MM_DEVICE_IGNORE}="1"` (stops ModemManager from claiming devices).
- `GROUP="dialout"`, `MODE="0660"` (safer than world-writable `0666`). Add your user once:

  ```bash
  sudo usermod -a -G dialout $USER
  # then log out and back in
  ```

- Clear comments + reload instructions.
- Latency timer example for FTDI (uncomment if needed for Dynamixel etc.).

After any change:

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

**Modern alternative:** many people skip custom rules and use kernel-provided stable names in launch files:

- `/dev/serial/by-id/usb-…`
- `/dev/serial/by-path/…`

These require zero configuration.

## Files in this repo

| File | Role |
|------|------|
| `myros.sh` | ROS autonomic helpers (core). |
| `ck.sh`, `ckb.sh` | Thin shims for old `source ~/…/ck.sh` aliases; resolve sibling `myros.sh`. |
| `install.sh` | Installer (udev + rc markers; supports `--dry-run` / `--no-udev` / `--no-rc`). |
| `rules/` | Improved udev rules for USB serial devices. |
| `.bashrc` | **Recommended block** (pretty bash + optional ROS). Paths resolve via `BASH_SOURCE` when possible. |
| `git-completion.bash`, `git-prompt.sh` | Vendored classic git helpers (pretty prompt section). |

You can use the pretty bash part even with no ROS workspaces. Add section 1 from `.bashrc` to your `~/.bashrc`, then enable ROS later via `install.sh` or an uncommented `source …/myros.sh`.

## History & credits

Originally created around 2016 by Wang Chen (Jeffsan) as a personal ROS productivity toolkit.

Extended and maintained by thien ([thien94](https://github.com/thien94/auto)).

Major updates: autonomic rewrite + first-class ROS 1 + ROS 2 support, smarter workspace/build detection, portable install path, optional env cleanup, zsh setup preference, and coexistence notes for direnv — while preserving simple "clone anywhere" spirit and `ck` / `CK` muscle memory.

Acknowledgement: Chen Chun-lin.

If this saves you time in the lab, feel free to star/fork and contribute improvements.
