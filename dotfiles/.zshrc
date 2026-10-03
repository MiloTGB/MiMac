# ==============================================================================
#  .zshrc — Sourced for INTERACTIVE shells
#  Maintainer: milothegalaxyboy
#  Rev: 2026-10-03
# ==============================================================================

# --- Oh My Zsh (OMZ) Configuration ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="bira"
zstyle ':omz:update' mode auto
COMPLETION_WAITING_DOTS="true"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting z colored-man-pages command-not-found gh)

# Load Oh My Zsh (guarded: a hard failure here would abort the rest of .zshrc)
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  echo "MiMac: oh-my-zsh not found at $ZSH — install it before sourcing .zshrc" >&2
fi

# --- PATH Customization ---
# Add user-specific and Python paths. Homebrew path is set in .zprofile.

path=(
  "$HOME/bin"
  "$HOME/.local/bin"
  $path
)

# Add latest python.org version to PATH, if present
PYTHON_FRAMEWORK_DIR="/Library/Frameworks/Python.framework/Versions"
if [[ -d "$PYTHON_FRAMEWORK_DIR" ]]; then
  LATEST_PYTHON_VERSION=$(ls "$PYTHON_FRAMEWORK_DIR" | sort -V | tail -n 1)
  LATEST_PYTHON_PATH="$PYTHON_FRAMEWORK_DIR/$LATEST_PYTHON_VERSION"
  if [[ -d "$LATEST_PYTHON_PATH/bin" ]]; then
    path=("$LATEST_PYTHON_PATH/bin" $path)
  fi
fi

# Remove duplicate path entries
typeset -U path

# --- Source Personal Aliases ---
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# --- NVM (lazy load, prefers Homebrew) ---
export NVM_DIR="$HOME/.nvm"

# Choose the cleanest available nvm.sh (Homebrew first)
_nvm_source=""
if [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
  _nvm_source="/opt/homebrew/opt/nvm/nvm.sh"
elif [ -s "$NVM_DIR/nvm.sh" ]; then
  _nvm_source="$NVM_DIR/nvm.sh"
fi
unset NVM_CD_FLAGS 2>/dev/null  # keep env tidy

# Install lightweight shims that load NVM only on demand — and only when there
# is an nvm to load. Without that guard the shims shadowed Homebrew's node, npm
# and npx on a machine with no nvm at all, and every call failed.
if [[ -n "$_nvm_source" ]] && ! typeset -f nvm >/dev/null; then
  _nvm_lazy_load() {
    # Load NVM once
    . "$_nvm_source"
    # Optional: completions (Homebrew path)
    if command -v brew >/dev/null 2>&1; then
      local _nvm_comp
      _nvm_comp="$(brew --prefix)/opt/nvm/etc/bash_completion.d/nvm"
      [ -s "$_nvm_comp" ] && . "$_nvm_comp"
    fi
    unset -f nvm node npm npx _nvm_lazy_load
    "$@"
  }
  nvm()  { _nvm_lazy_load nvm "$@"; }
  node() { _nvm_lazy_load node "$@"; }
  npm()  { _nvm_lazy_load npm "$@"; }
  npx()  { _nvm_lazy_load npx "$@"; }
fi

# --- MiMac Update Check (every shell; fetches at most daily) ---
# `|| true`: a pull that a yes started and that failed is reported by
# check-updates itself, and its status must not become the prompt's.
[[ -x "$HOME/bin/check-updates" ]] && "$HOME/bin/check-updates" || true

# --- Shell Welcome ---
[[ -o login ]] && command -v fastfetch >/dev/null 2>&1 && fastfetch
