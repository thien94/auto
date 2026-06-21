# >>> auto (https://github.com/thien94/auto) >>>
# Recommended block to add to your ~/.bashrc (or adapt for ~/.zshrc).
# Split into two independent parts so you can use one without the other.
#
# Tip: prefer ./install.sh which writes a correct absolute path for myros.sh.

# Resolve this repo if you sourced/copied this block from inside the clone.
_AUTO_BASHRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$HOME/auto}")" 2>/dev/null && pwd)"
# Fallback if BASH_SOURCE is unavailable in your setup:
: "${_AUTO_BASHRC_DIR:=$HOME/auto}"

# ------------------------------------------------------------------
# 1. PRETTIER / MORE HELPFUL BASH SETUP (git prompt + colors + basics)
#    Safe to use even if you have no ROS yet.
# ------------------------------------------------------------------

if [ -f "$_AUTO_BASHRC_DIR/git-prompt.sh" ]; then
  # shellcheck disable=SC1091
  source "$_AUTO_BASHRC_DIR/git-prompt.sh"
elif [ -f /usr/share/git/completion/git-prompt.sh ]; then
  # shellcheck disable=SC1091
  source /usr/share/git/completion/git-prompt.sh
elif [ -f /usr/lib/git-core/git-sh-prompt ]; then
  # shellcheck disable=SC1091
  source /usr/lib/git-core/git-sh-prompt
fi

export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWUNTRACKEDFILES=1
# Optional extras:
# export GIT_PS1_SHOWSTASHSTATE=1
# export GIT_PS1_SHOWUPSTREAM="auto"

green="\[\033[0;32m\]"
blue="\[\033[0;34m\]"
purple="\[\033[0;35m\]"
reset="\[\033[0m\]"

# Example:  thien (main) ~/Projects/auto $
export PS1="$purple\u$green\$(__git_ps1 ' (%s)')$blue \W $ $reset"

alias ls="ls --color=auto"
alias ll="ls -al --color=auto"
alias la="ls -A --color=auto"
alias ..="cd .."
alias ...="cd ../.."

export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend 2>/dev/null || true

# Optional: git tab completion (vendored or system)
# if [ -f "$_AUTO_BASHRC_DIR/git-completion.bash" ]; then
#   source "$_AUTO_BASHRC_DIR/git-completion.bash"
# fi

# ------------------------------------------------------------------
# 2. ROS HELPERS (uncomment when you use ROS; install.sh does this for you)
# ------------------------------------------------------------------

# export ROS_AUTO_ACTIVATE=1          # set 0 if you use direnv for workspaces
# export ROS_AUTO_CLEAN=0             # set 1 to scrub ROS1/ROS2 crosstalk on `ros`/`s`
# export ROS_AUTO_VERBOSE=0
# # export ROS_AUTO_WS_CANDIDATES="$HOME/my_ws $HOME/other_ws"
# source "$_AUTO_BASHRC_DIR/myros.sh"

# <<< auto <<<
