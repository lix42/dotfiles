#!/bin/sh
# Merge the dotfiles' settings into ~/.claude/settings.json, leaving every other
# key alone. Claude Code rewrites that file, so it is not managed as a copy.
set -eu

settings="$HOME/.claude/settings.json"
want='{"type":"command","command":"bash ~/.claude/statusline-command.sh"}'

if ! command -v jq >/dev/null 2>&1; then
  printf 'dotfiles: jq not found; skipped the Claude Code statusLine (re-run: dotfiles install)\n' >&2
  exit 0
fi

mkdir -p "$HOME/.claude"
[ -s "$settings" ] || printf '{}\n' >"$settings"
# Must hold exactly one JSON object. jq's own error, left on stderr, says where
# a broken file breaks; -s -e also rejects empty files, several values, and
# non-objects.
if ! jq -s -e 'length == 1 and (.[0] | type == "object")' "$settings" >/dev/null; then
  printf 'dotfiles: %s is not a JSON object; fix it, then re-run: dotfiles install\n' "$settings" >&2
  exit 1
fi
if [ "$(jq -c '.statusLine // empty' "$settings")" != "$(printf '%s' "$want" | jq -c .)" ]; then
  backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$settings" "$backup"
  tmp="$(mktemp "$settings.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  jq --argjson sl "$want" '.statusLine = $sl' "$settings" >"$tmp"
  mv "$tmp" "$settings"
  printf '==> Set statusLine in %s (backup: %s)\n' "$settings" "$backup"
fi
