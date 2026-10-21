#!/usr/bin/env bash
# Tests for bin/dotfiles and .githooks/pre-commit. Everything runs in scratch
# directories: a copy of this repo, a fake HOME, and throwaway git repos. It
# never touches the real home folder and never runs install/tools.sh.
#
#   test/dotfiles.sh        exits 1 if any case fails
#
# Token-shaped strings are built at run time, so this file passes the hook.
# Written for bash 3.2, the version macOS ships.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# "secret" in HOME's own path: name checks must only match below HOME.
H="$TMP/secret-home"
R="$H/src/dotfiles" # inside HOME, as the real clone is
failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}
# check DESC CMD...: pass when CMD succeeds.
check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}
# check_not DESC CMD...: pass when CMD fails.
check_not() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}
same_file() { cmp -s "$1" "$2"; }
has_line() { grep -qxF "$2" "$1"; }

D() { HOME="$H" XDG_STATE_HOME="$H/.local/state" DOTFILES_DIR="$R" "$R/bin/dotfiles" "$@"; }
state_is() { [ "$(D status "$1" | head -1 | awk '{print $1}')" = "$2" ]; }
g() { git -C "$R" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }
commit() { g -c core.hooksPath=.githooks commit -q -m test; }

# A copy of the repo's files in a fresh git repo, in an otherwise empty HOME.
mkdir -p "$R" "$H"
cp -R "$REPO/bin" "$REPO/home" "$REPO/install" "$REPO/.githooks" "$REPO/README.md" "$REPO/AGENTS.md" "$R/"
g init -q
printf 'one\ntwo\nthree\nfour\nfive\n' >"$R/home/.testrc"
T="$H/.testrc"
S="$R/home/.testrc"
BACKUPS="$H/.local/state/dotfiles/backup"

echo "# pre-commit hook: no false positives on the repo's own files"
g add -A
check "initial commit of the repo's files passes the hook" commit

echo "# states and direction guards"
check "missing before install" state_is "$T" missing
check "install one file" D install .testrc
check "  live copy matches the repo" same_file "$T" "$S"
check "  state same" state_is "$T" same
check "status accepts the repo path (repo under \$HOME)" state_is "$S" same

printf 'live-edit\n' >>"$T"
check "live edit is local" state_is "$T" local
check_not "install skips a local edit" D install .testrc
check "  and keeps it" has_line "$T" live-edit
check "install --force overwrites a local edit" D install --force .testrc
check "  live copy matches the repo" same_file "$T" "$S"
check "  the edit is in a backup" grep -rqx live-edit "$BACKUPS"

printf 'live-edit\n' >>"$T"
check "sync takes a local edit" D sync .testrc
check "  into the repo" has_line "$S" live-edit
check "  state same" state_is "$T" same

printf 'repo-edit\n' >>"$S"
check "repo update is repo" state_is "$T" repo
check_not "sync skips a repo update" D sync .testrc
check "  and keeps it" has_line "$S" repo-edit
check "install takes a repo update" D install .testrc
check "  into \$HOME" has_line "$T" repo-edit

printf 'override\n' >>"$S"
check "sync --force overwrites a repo update" D sync --force .testrc
check_not "  dropping it" has_line "$S" override

echo "# merge"
awk '{ sub(/^one$/, "one-live") } 1' "$T" >"$TMP/x" && mv "$TMP/x" "$T"
awk '{ sub(/^five$/, "five-repo") } 1' "$S" >"$TMP/x" && mv "$TMP/x" "$S"
check "edits on both sides are both" state_is "$T" both
check_not "install skips both" D install .testrc
check_not "sync skips both" D sync .testrc
check "clean merge succeeds" D merge .testrc
check "  both copies match" same_file "$T" "$S"
check "  with the live edit" has_line "$S" one-live
check "  and the repo edit" has_line "$T" five-repo
check "  state same" state_is "$T" same

awk '{ sub(/^three$/, "three-live") } 1' "$T" >"$TMP/x" && mv "$TMP/x" "$T"
awk '{ sub(/^three$/, "three-repo") } 1' "$S" >"$TMP/x" && mv "$TMP/x" "$S"
check_not "conflicting merge exits 1" D merge .testrc
check "  markers in the repo copy" grep -q '^<<<<<<< ' "$S"
check_not "  none in the live copy" grep -q '^<<<<<<< ' "$T"
check_not "install --force refuses a file with markers" D install --force .testrc
cp "$T" "$S" # resolve by keeping the live side
check "install --force after resolving" D install --force .testrc
check "  state same" state_is "$T" same
printf 'after-resolve\n' >>"$T"
check "a later live edit is local (baseline refreshed)" state_is "$T" local
D install --force .testrc >/dev/null 2>&1

printf 'no baseline\n' >"$R/home/.otherrc"
printf 'different\n' >"$H/.otherrc"
check "differing file with no baseline is differs" state_is "$H/.otherrc" differs
check_not "merge refuses a file with no baseline" D merge .otherrc
rm -f "$R/home/.otherrc" "$H/.otherrc"

echo "# add guards"
mkdir -p "$H/.config/zsh" "$H/.ssh" "$H/.aws" "$H/.docker"
for f in .config/zsh/local.zsh .config/zsh/secrets.zsh .ssh/config .aws/credentials .docker/config.json \
  .netrc .npmrc .gitconfig .plainrc; do
  printf 'x\n' >"$H/$f"
done
check_not "add refuses local.zsh" D add "$H/.config/zsh/local.zsh"
check_not "add refuses local.zsh via ./" D add "$H/.config/zsh/./local.zsh"
check_not "add refuses local.zsh via //" D add "$H/.config/zsh//local.zsh"
check_not "add refuses secrets.zsh" D add "$H/.config/zsh/secrets.zsh"
check_not "add refuses ~/.ssh" D add "$H/.ssh/config"
check_not "add refuses ~/.ssh via ./" D add "$H/./.ssh/config"
ln -s "$H/.ssh" "$H/sshlink"
check_not "add refuses ~/.ssh via a symlinked directory" D add "$H/sshlink/config"
check_not "add refuses ~/.aws" D add "$H/.aws/credentials"
check_not "add refuses ~/.docker/config.json via //" D add "$H/.docker//config.json"
check_not "add refuses ~/.netrc" D add "$H/.netrc"
if [ -e "$H/.NETRC" ]; then # case-insensitive file system, as macOS usually is
  check_not "add refuses ~/.NETRC (same file)" D add "$H/.NETRC"
fi
check_not "add refuses ~/.npmrc" D add "$H/.npmrc"
# Only the '..' guard can refuse this: it resolves to an addable ~/.gitconfig.
check_not "add refuses a path with .." D add "$H/.config/../.gitconfig"
check_not "add refuses a path outside \$HOME" D add /etc/hosts
check_not "add refuses a managed file" D add "$T"
ln -s "$H/.gitconfig" "$H/.link"
check_not "add refuses a symlink" D add "$H/.link"
printf 'export MY_TOKEN="%s"\n' "$(printf 'a%.0s' $(seq 24))" >"$H/.toolrc"
check_not "add refuses a file with a secret" D add "$H/.toolrc"
check "add accepts a plain file" D add "$H/.gitconfig"
printf 'x\n' >"$H/-dash"
check "add accepts a top-level name starting with -" D add "$H/-dash"
mkdir -p "$H/.colordir"
printf 'x\n' >"$H/.colordir/f"
add_with_forced_colour() { CLICOLOR=1 CLICOLOR_FORCE=1 D add "$H/.colordir/f"; }
check "add works with CLICOLOR_FORCE set" add_with_forced_colour
check "  copied into the repo" same_file "$H/.gitconfig" "$R/home/.gitconfig"
check_not "  local.zsh never reached the repo" test -e "$R/home/.config/zsh/local.zsh"
check_not "  nor did the Docker config" test -e "$R/home/.docker/config.json"
check_not "add refuses a lookalike name (ſ for s)" D add "$H/.docker/config.j"$'\xc5\xbf'"on"

mkdir -p "$H/real-config" "$TMP/outside"
printf 'x\n' >"$H/real-config/app.conf"
printf 'x\n' >"$TMP/outside/tool.conf"
ln -s "$H/real-config" "$H/.appconfig"
ln -s "$TMP/outside" "$H/.external"
check "add accepts a file under a symlinked directory" D add "$H/.appconfig/app.conf"
check "  managed at the path as typed" test -f "$R/home/.appconfig/app.conf"
check "  and status finds it there" state_is "$H/.appconfig/app.conf" same
check "add accepts a file under a directory linked outside \$HOME" D add "$H/.external/tool.conf"
check_not "add refuses a second path to a managed file" D add "$H/real-config/app.conf"

# Other spellings of credential paths: refused by identity, not by text.
mkdir -p "$H/.ssh/keys" "$H/old/.ssh"
printf 'x\n' >"$H/.ssh/keys/notes.txt"
printf 'x\n' >"$H/old/.ssh/config"
printf 'x\n' >"$H/MySECRET.txt"
ln -s "$H/.ssh/keys" "$H/keylink"
check_not "add refuses a file in a subdirectory of ~/.ssh, via a symlink" D add "$H/keylink/notes.txt"
check_not "add refuses a backup copy of ~/.ssh, by name" D add "$H/old/.ssh/config"
check_not "add refuses an upper-case sensitive name" D add "$H/MySECRET.txt"
lookalike_dir="$H/."$'\xc5\xbf'"sh"
if [ -e "$lookalike_dir/config" ]; then # file system folds ſ to s, as APFS does
  check_not "add refuses a lookalike directory name (.ſsh)" D add "$lookalike_dir/config"
fi
mkdir -p "$H/my-secrets"
printf 'x\n' >"$H/my-secrets/x.conf"
printf 'x\n' >"$H/mysecret.txt"
ln -s "$H/my-secrets" "$H/s"
ln -s "$H/old/.ssh" "$H/sshbak"
check_not "add refuses a sensitive real name behind a symlinked directory" D add "$H/s/x.conf"
check_not "add refuses a backup copy of ~/.ssh behind a symlink" D add "$H/sshbak/config"
ln -s "$H/my-"$'\xc5\xbf'"ecrets" "$H/s2" # target written with a lookalike letter
if [ -e "$H/s2/x.conf" ]; then
  check_not "add refuses a sensitive real name behind a lookalike link target" D add "$H/s2/x.conf"
fi
lookalike_file="$H/my"$'\xc5\xbf'"ecret.txt"
if [ -e "$lookalike_file" ]; then
  check_not "add refuses a lookalike spelling of a sensitive name" D add "$lookalike_file"
fi
data_home="/System/Volumes/Data$(cd -P "$H" && pwd -P)"
if [ -d "$data_home" ]; then # macOS firmlink: another spelling of the same path
  ln -s "$data_home/.docker" "$H/firmlink"
  check_not "add refuses ~/.docker/config.json via /System/Volumes/Data" D add "$H/firmlink/config.json"
fi

printf '(unbalanced\n' >>"$R/.githooks/secret-patterns"
check_not "add refuses when a secret pattern is invalid" D add "$H/.plainrc"
check_not "sync refuses when a secret pattern is invalid" D sync .testrc
printf '# harmless\n' >>"$R/home/.zshrc"
g add home/.zshrc
hook_refuses_bad_pattern() {
  local out rc=0
  out="$(commit 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"grep failed"* ]]
}
check "hook refuses when a secret pattern is invalid" hook_refuses_bad_pattern
g checkout -q HEAD -- home/.zshrc .githooks/secret-patterns

echo "# Claude Code settings"
if command -v jq >/dev/null 2>&1; then
  C="$TMP/claude-home"
  mkdir -p "$C/.claude"
  settings_run() { HOME="$C" "$R/install/claude-settings.sh"; }
  printf '\n' >"$C/.claude/settings.json"
  check_not "refuses a whitespace-only settings.json" settings_run
  check "  and leaves it alone" test "$(cat "$C/.claude/settings.json")" = ""
  check "  with no temp file left" test "$(cd "$C/.claude" && echo *)" = settings.json
  printf '{"a":1}\n{"b":2}\n' >"$C/.claude/settings.json"
  check_not "refuses a settings.json with two JSON values" settings_run
  printf '{"model":"x"}\n' >"$C/.claude/settings.json"
  check "sets statusLine in a valid settings.json" settings_run
  check "  keeping other keys" test "$(jq -r .model "$C/.claude/settings.json")" = x
  check "  and the status line command" test "$(jq -r .statusLine.command "$C/.claude/settings.json")" = "bash ~/.claude/statusline-command.sh"
else
  printf 'skip Claude Code settings: jq is not installed\n'
fi

echo "# log"
# Capture first: under pipefail, `D log | grep -q` can fail on SIGPIPE.
log_has_merge() {
  local out
  out="$(D log .testrc)" && [[ "$out" == *"merge: .testrc"* ]]
}
check "log lists the test file's history" log_has_merge

echo "# pre-commit hook"
gh_token="ghp_$(printf 'A%.0s' $(seq 36))"
npm_token="npm_$(printf 'B%.0s' $(seq 36))"
pw_word="pass""word"
# blocks DESC PATH CONTENT: committing CONTENT at PATH must be refused by the
# hook, which must name PATH; a commit failing for another reason doesn't count.
blocks() {
  local out rc=0
  mkdir -p "$(dirname "$R/$2")"
  printf '%s\n' "$3" >"$R/$2"
  g add -- "$2"
  if g diff --cached --quiet; then
    fail "$1 (nothing was staged)"
  else
    out="$(commit 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ] && [[ "$out" == *"  $2"* ]]; then pass "$1"; else fail "$1"; fi
  fi
  g rm -q -r --cached -- "$2" >/dev/null 2>&1
  rm -f "$R/$2"
}
blocks "blocks a GitHub token in a new file" home/plain "export X=\"$gh_token\""
blocks "blocks one in a path with spaces" "home/Library/Application Support/x.json" "{\"t\": \"$gh_token\"}"
blocks "blocks one in a non-ASCII path" "home/café.txt" "$gh_token"
blocks "blocks an npm token" home/.npmrc-like "//registry.npmjs.org/:_authToken=$npm_token"
blocks "blocks a lowercase spaced assignment" home/.tool.conf "$pw_word = \"$(printf 'c%.0s' $(seq 20))\""
blocks "blocks an added line that starts with ++" home/.plusrc "++ $gh_token"
printf 'export X="%s"\n' "$gh_token" >>"$R/home/.zshrc"
g add home/.zshrc
check_not "blocks a token added to a tracked file" commit
g checkout -q HEAD -- home/.zshrc
printf '# a harmless comment\n' >>"$R/home/.zshrc"
g add home/.zshrc
check "allows a clean change" commit

if [ "$failures" -ne 0 ]; then
  printf '\n%d failed\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
