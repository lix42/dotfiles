#!/bin/sh
# Set up the dotfiles bare repo on this machine. Safe to re-run.
#
#   git clone --bare https://github.com/lix42/dotfiles.git ~/.cfg
#   git --git-dir="$HOME/.cfg" show main:.config/dotfiles/bootstrap.sh | sh
#
# Overrides: DOTFILES_REPO, DOTFILES_DIR (default ~/.cfg), DOTFILES_BRANCH (default main).
set -eu

REPO="${DOTFILES_REPO:-https://github.com/lix42/dotfiles.git}"
CFG_DIR="${DOTFILES_DIR:-$HOME/.cfg}"
BRANCH="${DOTFILES_BRANCH:-main}"
STAMP="$(date +%Y%m%d-%H%M%S)"

dotcfg() { git --git-dir="$CFG_DIR" --work-tree="$HOME" "$@"; }
log() { printf '==> %s\n' "$*"; }

# --- Repo -------------------------------------------------------------------
if [ ! -d "$CFG_DIR" ]; then
  log "Cloning $REPO into $CFG_DIR"
  git clone --bare --quiet "$REPO" "$CFG_DIR"
fi

dotcfg config status.showUntrackedFiles no
dotcfg config core.hooksPath "$HOME/.config/dotfiles/hooks"
# A bare clone has no fetch refspec, so pull/push would not track origin.
dotcfg config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
dotcfg fetch --quiet origin
dotcfg branch --quiet --set-upstream-to="origin/$BRANCH" "$BRANCH"

# Keep machine-local files out of `dotcfg add` by accident.
exclude="$CFG_DIR/info/exclude"
mkdir -p "$CFG_DIR/info"
for p in /.cfg/ /.cfg-backup/ /.config/zsh/local.zsh /.config/zsh/secrets.zsh; do
  grep -qxF "$p" "$exclude" 2>/dev/null || printf '%s\n' "$p" >>"$exclude"
done

# --- First checkout ---------------------------------------------------------
# Only on the first run: later runs must not touch uncommitted edits.
if [ ! -f "$CFG_DIR/index" ]; then
  backup="$HOME/.cfg-backup/$STAMP"
  dotcfg ls-tree -r "$BRANCH" | while read -r _mode _type blob path; do
    f="$HOME/$path"
    if [ ! -e "$f" ] && [ ! -L "$f" ]; then
      continue
    fi
    if [ -f "$f" ] && [ ! -L "$f" ] && [ "$(git hash-object "$f")" = "$blob" ]; then
      continue
    fi
    mkdir -p "$(dirname "$backup/$path")"
    mv "$f" "$backup/$path"
    log "Moved existing ~/$path to $backup/"
  done
  dotcfg checkout --quiet -f "$BRANCH"
  log "Checked out $BRANCH into $HOME"
fi

# --- Machine-local zsh files (never committed) -------------------------------
mkdir -p "$HOME/.config/zsh"
[ -e "$HOME/.config/zsh/local.zsh" ] || : >"$HOME/.config/zsh/local.zsh"
secrets="$HOME/.config/zsh/secrets.zsh"
if [ ! -e "$secrets" ]; then
  (umask 077 && cp "$HOME/.config/zsh/secrets.zsh.example" "$secrets")
  log "Created $secrets from the example; fill in the values"
fi
chmod 600 "$secrets"

# --- Claude Code status line ------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  settings="$HOME/.claude/settings.json"
  want='{"type":"command","command":"bash ~/.claude/statusline-command.sh"}'
  mkdir -p "$HOME/.claude"
  [ -s "$settings" ] || printf '{}\n' >"$settings"
  if [ "$(jq -c '.statusLine // empty' "$settings")" != "$(printf '%s' "$want" | jq -c .)" ]; then
    cp "$settings" "$settings.bak-$STAMP"
    tmp="$(mktemp "$settings.XXXXXX")"
    jq --argjson sl "$want" '.statusLine = $sl' "$settings" >"$tmp"
    mv "$tmp" "$settings"
    log "Set statusLine in $settings (backup: $settings.bak-$STAMP)"
  fi
else
  log "jq not found; skipped the Claude Code statusLine setting"
fi

log "Done. Open a new shell to get dotcfg (~/.local/bin/dotcfg) on PATH."
