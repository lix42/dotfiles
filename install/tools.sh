#!/usr/bin/env bash
# Install command-line tools: each tool's official installer first, Homebrew as
# the fallback. Keeps going past failures, lists them at the end, and exits 1
# if any failed.
#
#   install/tools.sh [--dry-run]
#
# A tool already on PATH is skipped, so a re-run only fills gaps. To add a tool:
# brew-only tools go in home/.Brewfile; anything else gets a `tool` line below.
# Written for bash 3.2, the version macOS ships.
set -uo pipefail

DRY_RUN=0
# Anything else is refused: a mistyped --dry-run must not install for real.
case "$#:${1:-}" in
  0:) ;;
  1:--dry-run) DRY_RUN=1 ;;
  *)
    printf 'usage: install/tools.sh [--dry-run]\n' >&2
    exit 2
    ;;
esac
FAILED=""

# The shell config is managed by dotfiles. Put every tool's bin dir on PATH now:
# the bun and uv installers then skip editing rc files, and new tools are found.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.vite-plus/bin:$HOME/.bun/bin:$PATH"
# Install Vite+ where the rc files expect it, not its newer ~/.local/share default.
export VP_HOME="$HOME/.vite-plus"

log() { printf '\n==> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
fail() {
  FAILED="$FAILED  - $1"$'\n'
  printf '    FAILED: %s\n' "$1" >&2
}

# Run a shell snippet, or only print it with --dry-run.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    would run: %s\n' "$1"
    return 0
  fi
  # pipefail isn't inherited: without it, `curl … | sh` reports only sh's status,
  # so a failed download would count as success.
  bash -o pipefail -c "$1"
}

# True after a real run when CMD is now on PATH; always true in a dry run.
installed() { [ "$DRY_RUN" -eq 1 ] || have "$1"; }

# tool NAME CMD OFFICIAL [BREW_ARGS]
# Skip when CMD is on PATH. Otherwise run the OFFICIAL snippet, then fall back to
# `brew install BREW_ARGS` if that failed or did not put CMD on PATH.
tool() {
  local name="$1" cmd="$2" official="$3" brew_args="${4:-}"
  log "$name"
  if have "$cmd"; then
    printf '    already installed: %s\n' "$(command -v "$cmd")"
    return
  fi
  if run "$official" && installed "$cmd"; then return; fi
  if [ -n "$brew_args" ] && have brew; then
    printf '    official installer failed or did not put %s on PATH; falling back to: brew install %s\n' "$cmd" "$brew_args"
    if run "brew install $brew_args" && installed "$cmd"; then return; fi
  fi
  fail "$name"
}

# check NAME SNIPPET [FALLBACK]: run SNIPPET; if it fails, run FALLBACK.
check() {
  local name="$1" snippet="$2" fallback="${3:-}"
  log "$name"
  if run "$snippet"; then return; fi
  if [ -n "$fallback" ]; then
    printf '    falling back to: %s\n' "$fallback"
    if run "$fallback"; then return; fi
  fi
  fail "$name"
}

brew_env() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$b" ]; then
      eval "$("$b" shellenv)"
      return 0
    fi
  done
  return 1
}

# --- Homebrew: first, since every fallback needs it --------------------------
log "Homebrew"
if brew_env; then
  printf '    already installed: %s\n' "$(command -v brew)"
else
  # Interactive when run from a terminal, so it can ask for the sudo password.
  noninteractive=""
  if [ ! -t 0 ]; then noninteractive="NONINTERACTIVE=1 "; fi
  if run "${noninteractive}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" &&
    { [ "$DRY_RUN" -eq 1 ] || brew_env; }; then
    :
  else
    fail "Homebrew (later fallbacks to brew will fail too)"
  fi
fi

# --- Oh My Zsh: ~/.zshrc sources it ------------------------------------------
# After Homebrew, which brings the Command Line Tools' git the installer needs.
# --unattended: don't change the login shell or start zsh. --keep-zshrc: the
# dotfiles' ~/.zshrc is already installed; don't replace it with the template.
log "Oh My Zsh"
omz="$HOME/.oh-my-zsh/oh-my-zsh.sh"
# shellcheck disable=SC2016 # $(curl …) must expand in run's child shell
if [ -r "$omz" ]; then
  printf '    already installed: %s\n' "$HOME/.oh-my-zsh"
elif run 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc' &&
  { [ "$DRY_RUN" -eq 1 ] || [ -r "$omz" ]; }; then
  :
else
  fail "Oh My Zsh"
fi

# --- Toolchains ---------------------------------------------------------------
# No brew fallback for rustup: Homebrew's rustup needs its own PATH entry.
tool "Rust (rustup)" rustup \
  "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"

# No brew fallback for Vite+: the formula depends on Homebrew's node.
tool "Vite+" vp "curl -fsSL https://vite.plus | CI=1 VP_NODE_MANAGER=yes VP_PM_MANAGER=yes bash"

log "Vite+ shims (node, npm, pnpm, yarn, bun)"
if ! have vp && [ "$DRY_RUN" -eq 0 ]; then
  fail "Vite+ shims: vp is not installed"
elif [ -e "$VP_HOME/bin/node" ] && [ -e "$VP_HOME/bin/pnpm" ] && [ -e "$VP_HOME/bin/bun" ]; then
  printf '    already set up in %s/bin\n' "$VP_HOME"
else
  run "vp env setup" || fail "Vite+ shims (vp env setup)"
fi

# The first run of each shim downloads the runtime; Node is the latest LTS
# unless `vp env default` sets another version.
check "Node.js (via Vite+)" "node --version"
check "pnpm (via Vite+)" "pnpm --version"
check "Bun (via Vite+)" "bun --version" "curl -fsSL https://bun.com/install | bash"

tool uv uv "curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh" uv

tool "Claude Code" claude "curl -fsSL https://claude.ai/install.sh | bash" "--cask claude-code"

# --- Tools with their own recommended installer -------------------------------
tool starship starship \
  "mkdir -p ~/.local/bin && curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b ~/.local/bin" starship

# --- Homebrew packages ---------------------------------------------------------
log "Homebrew packages (~/.Brewfile)"
if ! have brew && [ "$DRY_RUN" -eq 0 ]; then
  fail "Homebrew packages: brew is not installed"
elif [ ! -f "$HOME/.Brewfile" ] && [ "$DRY_RUN" -eq 0 ]; then
  fail "Homebrew packages: ~/.Brewfile is missing (run: dotfiles install)"
else
  run "brew bundle install --global" || fail "Homebrew packages (brew bundle install --global)"
fi

# --- Cargo crates: after rustup, so brew never installs its own Rust ----------
tool tlrc tldr "cargo install --locked tlrc" tlrc
tool tree-sitter-cli tree-sitter "cargo install --locked tree-sitter-cli" tree-sitter-cli
tool cargo-generate cargo-generate "cargo install --locked cargo-generate"
tool cargo-machete cargo-machete "cargo install --locked cargo-machete"
tool rustlings rustlings "cargo install --locked rustlings"

# --- npm globals: installed into Vite+'s current Node --------------------------
# Global npm packages appear to be tied to one Node version; after changing the
# default Node, re-run this script to reinstall them.
tool agent-browser agent-browser "npm install -g agent-browser" agent-browser
# Its own step, so a failed browser download is reported, and retried on a re-run
# even though the agent-browser command is already installed.
if have agent-browser || [ "$DRY_RUN" -eq 1 ]; then
  check "agent-browser browser (Chrome for Testing, unless one is found)" "agent-browser install"
fi

# --- Summary ------------------------------------------------------------------
if [ -n "$FAILED" ]; then
  printf '\n==> Failed:\n%s' "$FAILED" >&2
  exit 1
fi
log "All tools are installed."
