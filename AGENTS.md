# Agent instructions

This repo holds shared config for all of the user's machines. Files under
`home/` are copied to the same path under `$HOME` by `bin/dotfiles`; see
[README.md](README.md) for the commands and layout.

Two copies of every managed file exist: the repo's (`home/<path>`) and the live
one (`~/<path>`). `dotfiles status` tells which side changed since the last
install or sync (`local`, `repo`, `both`), using a local baseline in
`~/.local/state/dotfiles/base/`. README.md explains each state. For `differs`
(no baseline yet), decide the direction by reading the diff, and ask the user
when it's unclear.

## Rules

- **The repo is public: everything committed, on any branch, can be read by
  anyone, and stays in the history.** Keep out secrets, internal hostnames, and
  employer-specific details.
- **Never copy secrets into the repo.** `~/.config/zsh/secrets.zsh` and
  `~/.config/zsh/local.zsh` are never managed. Don't read `secrets.zsh`; to see
  which secrets exist, list variable names only, for example
  `sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p'`.
  If a managed file holds a secret value, move it to `secrets.zsh` and its name
  to `home/.config/zsh/secrets.zsh.example`.
- **Machine-specific settings go in `~/.config/zsh/local.zsh`**, not in
  `home/`: anything that only exists on one machine, such as work tools, a
  hard-coded install path, or a CPU-specific flag.
- **Show the diff and get the user's OK before `dotfiles install` replaces a
  file, before `dotfiles sync`, and before `dotfiles merge`.** `--dry-run` shows
  what `install` or `sync` would do. Never pass `--force` without the user's OK:
  it discards one side's changes.
- **Leave conflict resolution to the user** unless they ask you to do it. Show
  them the markers in `home/<path>`.
- **Never edit `~/.local/state/dotfiles/base/` directly.** The commands
  maintain it.
- **Never commit, push, or open a PR unless the user asks.** Staging is fine.
- Shared files must work on every machine: use `$HOME`, never `/Users/<name>`,
  and load optional tools and files only when present, with
  `if [ -r … ]; then …; fi`. Avoid `[ -r … ] && …` as the last line of an rc
  file: it leaves status 1 when the file is missing.
- `bin/dotfiles` and `install/tools.sh` must run on bash 3.2, the version macOS
  ships: no associative arrays, `mapfile`, or `${var,,}`.

## Workflows

### Set up a new machine

1. Clone to `~/src/dotfiles` (README has the command) and run
   `bin/dotfiles setup --dry-run` to show the user what will happen.
2. Ask the user to run `~/src/dotfiles/bin/dotfiles setup` in their own
   terminal. The Homebrew installer needs a password prompt, which an agent's
   shell can't answer.
3. Read the summary. For each failed tool, find the cause in the output above it
   and fix it, or report it to the user.
4. Run `dotfiles status`. Vite+'s installer has no opt-out and may have edited
   `~/.zshrc` or `~/.zshenv`, which then show as `local`. Show the diff and, with the user's OK, restore the repo copy with
   `dotfiles install --force <file>`.

### Update this machine from the repo

1. `git -C ~/src/dotfiles pull --ff-only`
2. `dotfiles status`.
3. Files in state `repo`: show `dotfiles diff`, then `dotfiles install` with
   the user's OK. It skips `local` and `both` files on its own.
4. Files in state `both`: show the diff and run `dotfiles merge` with the user's
   OK. On conflicts, hand the markers in `home/<path>` to the user.

### Capture local edits into the repo

1. `dotfiles status`, then `dotfiles diff <file>` for files in state `local`.
2. Machine-specific or secret lines go to `local.zsh` or `secrets.zsh` instead;
   edit the live file, then diff again.
3. With the user's OK, `dotfiles sync <file>`, then show `git diff`.

### Start managing a file

`dotfiles add ~/<path>`. It refuses `local.zsh` and `secrets.zsh`; credential
locations (`~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker/config.json`,
`~/.netrc`, `~/.npmrc`, `~/.git-credentials`), by file identity, so symlinks and
other spellings don't get past; files with those names anywhere, such as a backup
of `~/.ssh`; names containing `secret` or ending in `.pem` or `.key`; a second
path to a file it already manages; and files that match
`.githooks/secret-patterns`. Add a row for the file to the Layout table in
README.md.

### Add a tool

- Check the tool's official install docs; don't rely on memory.
- If Homebrew is the recommended macOS method, add `brew "<name>"` to
  `home/.Brewfile`.
- Otherwise add a `tool` line to `install/tools.sh` in the matching section:
  the official command with its unattended and no-rc-edit flags, then the brew
  fallback. Cargo crates and npm globals go after the toolchains they need.
- Update the Tools list in README.md.

## Checks before handing back

```sh
# One file per call: `bash -n a b` checks only a, passing b to it as an argument.
for f in bin/dotfiles install/tools.sh .githooks/pre-commit test/dotfiles.sh; do bash -n "$f"; done
sh -n install/claude-settings.sh
for f in home/.zshrc home/.zshenv home/.zprofile; do zsh -n "$f"; done
shellcheck bin/dotfiles install/*.sh .githooks/pre-commit test/dotfiles.sh   # if installed
test/dotfiles.sh
bin/dotfiles setup --dry-run
bin/dotfiles status
```

`test/dotfiles.sh` covers the CLI and the pre-commit hook in a scratch `HOME`
and scratch repos; add a case there when you change either. To try `install` or
`sync` by hand without touching the real home folder, run them with `HOME` set
to a scratch directory.

Test `install/tools.sh` only with `--dry-run`. A fake `HOME` does not isolate
it: it finds the real Homebrew in `/opt/homebrew`, and any failing official
installer falls back to a real `brew install`.
