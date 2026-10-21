# dotfiles

Config shared by all my machines. The repo is a normal clone at `~/src/dotfiles`
(override with `DOTFILES_DIR`). Files under `home/` are **copied** to the same
path under `$HOME`; nothing is symlinked. `bin/dotfiles` copies them in either
direction and shows where the repo and `$HOME` differ.

Copies, not links, because installers and tools edit config in place: an
installer appending to `~/.zshrc` changes only the live copy, `dotfiles status`
shows it, and you decide whether to keep it (`sync`) or drop it (`install`).

Agents: read [AGENTS.md](AGENTS.md) before changing anything.

## New machine

```sh
git clone https://github.com/lix42/dotfiles.git ~/src/dotfiles
~/src/dotfiles/bin/dotfiles setup
```

The repo is public, so cloning needs no credentials. Pushing does: run
`gh auth login` and `gh auth setup-git` (installed by `setup`), or use an SSH
key. Run `setup` in your own terminal: the Homebrew installer asks for your
password.

`setup` runs `dotfiles install`, then `install/tools.sh`, then sets the Claude
Code status line again (it needs `jq`, which `tools.sh` may have just
installed), then `dotfiles status`. A tool that fails to install doesn't stop
the others: the failures are listed at the end and `setup` exits 1. Fix them
and re-run; installed tools are skipped. Then fill in
`~/.config/zsh/secrets.zsh`. `setup` and `install/tools.sh` accept only
`--dry-run` and refuse anything else before changing anything.

## Commands

| Command | Does |
|---|---|
| `dotfiles status [file…]` | Which side changed each managed file since its last install or sync (states below) |
| `dotfiles diff [file…]` | Diff, repo (`-`) against `$HOME` (`+`) |
| `dotfiles install [--dry-run] [--force] [file…]` | Copy repo → `$HOME`. Skips `local` and `both` unless `--force`. Replaced files go to `~/.local/state/dotfiles/backup/<timestamp>-<pid>/`, one directory per run. With no files, also sets up machine state (below) |
| `dotfiles sync [--dry-run] [--force] [file…]` | Copy `$HOME` → repo. Skips `repo` and `both` unless `--force` |
| `dotfiles merge [file…]` | Three-way merge files in state `both` (details below) |
| `dotfiles add <file…>` | Start managing a file from `$HOME` |
| `dotfiles log [-p] [file…]` | History of installs, syncs and merges on this machine |
| `dotfiles setup [--dry-run]` | New machine: install, tools, status |

`install`, `sync` and `merge` exit 1 when they skip a file or leave conflicts.

### Which side changed

Every `install`, `sync`, `merge` and `add` records the file as it was in both
copies in a **baseline**: a local git repo in `~/.local/state/dotfiles/base/`
that is never pushed. The GitHub repo stays the source of truth; the baseline
only lets `status` tell which side changed since then:

| State | Meaning | Next step |
|---|---|---|
| `same` | Both copies match | none |
| `local` | Edited in `$HOME` (by you or an installer) | `sync` to keep it, or `install --force` to drop it |
| `repo` | Updated in the repo, for example by `git pull` | `install` |
| `both` | Changed on both sides | `merge` |
| `differs` | No baseline yet, so the direction is unknown | `diff`, then `install` or `sync` |
| `missing` | Not in `$HOME` | `install` |
| `link` | A symlink in `$HOME`, perhaps from another dotfiles manager | `install`, which moves the link (not its target) to the backup and puts a copy in its place; `sync` skips it |

`merge` runs `git merge-file` with the baseline as the common ancestor. A clean
result is written to both copies. On conflicts, the conflict markers go into
the repo copy (`home/<path>`) and the live file is left working. Resolve the
markers there, then run `dotfiles install --force <file>`; `install` refuses a
file that still has markers.

`dotfiles log -p ~/.zshrc` shows what each install or sync changed in that file.

Machine state set up by a full `install` (all idempotent):

- `~/.config/zsh/local.zsh` and `~/.config/zsh/secrets.zsh` (mode 600), created
  if missing from `secrets.zsh.example`
- `~/.local/bin/dotfiles` → `bin/dotfiles`
- `core.hooksPath=.githooks` in this repo
- `statusLine` in `~/.claude/settings.json`, merged with `jq` by
  `install/claude-settings.sh` (Claude Code rewrites that file, so it isn't a copy)

## Layout

| Path | Purpose |
|---|---|
| `home/.zshenv` | Every zsh: cargo, Vite+ and `~/.local/bin` on PATH; loads `secrets.zsh` |
| `home/.zprofile` | Login shells: Homebrew, then `~/.local/bin` first again |
| `home/.zshrc` | Interactive shells: Oh My Zsh, tools, aliases; loads `local.zsh` last |
| `home/.config/zsh/secrets.zsh.example` | Names of the secrets each machine needs |
| `home/.claude/statusline-command.sh` | Claude Code status line (needs `jq`, `git`) |
| `home/.Brewfile` | Homebrew packages and casks (Ghostty, FiraCode Nerd Font), for `brew bundle --global` |
| `home/.config/ghostty/config.ghostty` | Ghostty settings. Ghostty also reads `~/Library/Application Support/com.mitchellh.ghostty/` and lets it override this file, so keep that folder empty |
| `install/tools.sh` | Installs tools: official installer first, Homebrew as fallback |
| `install/claude-settings.sh` | Merges `statusLine` into Claude Code settings |
| `.githooks/pre-commit`, `.githooks/secret-patterns` | Blocks commits that look like they contain a credential |
| `test/dotfiles.sh` | Tests for `bin/dotfiles` and the pre-commit hook, in scratch directories |

## Tools

`install/tools.sh` skips anything already on PATH, and installs in this order:

1. Homebrew: its official script.
2. Oh My Zsh: its official script, with `--unattended` (no login-shell change)
   and `--keep-zshrc` (keeps the dotfiles' `~/.zshrc`). Skipped when
   `~/.oh-my-zsh` is already there.
3. Toolchains, from their official installers:
   - rustup, with no brew fallback
   - Vite+, kept in `~/.vite-plus`, with no brew fallback (the formula depends
     on Homebrew's node). Its shims provide Node, npm, pnpm, Yarn and Bun;
     bun's own installer is the fallback.
   - uv
   - Claude Code, with the `claude-code` cask as fallback
4. starship, from its official script.
5. Everything in `home/.Brewfile`, via `brew bundle install --global`,
   including the Ghostty and FiraCode Nerd Font casks. An app already in
   `/Applications` that Homebrew didn't install makes the cask fail; take it
   over once with `brew install --cask --adopt <cask>`.
6. Cargo crates, after rustup so brew never installs its own Rust: tlrc
   (`tldr`), tree-sitter-cli, cargo-generate, cargo-machete, rustlings.
7. npm globals, into Vite+'s current Node: agent-browser, then its browser
   download (`agent-browser install`) as a separate step, so a failed download
   is retried on the next run. Global npm packages appear to be tied to one
   Node version, so re-run `install/tools.sh` after changing the default Node.
8. Neovim config: clones [lix42/kickstart.nvim](https://github.com/lix42/kickstart.nvim)
   into `~/.config/nvim`. Skipped when that folder already exists; update it
   with `git -C ~/.config/nvim pull`.

Vite+'s installer edits shell config files whatever you tell it. rustup and uv
are told not to, and bun's installer skips the edit because `tools.sh` already
has `~/.bun/bin` on PATH. Check `dotfiles status` afterwards.

## Machine-specific settings and secrets

| File | Holds |
|---|---|
| `~/.config/zsh/local.zsh` | This machine only: `DOTNET_ROOT`, unusual paths, work tools |
| `~/.config/zsh/secrets.zsh` | API keys and tokens; mode 600 |

Neither is ever copied into the repo: `dotfiles add` refuses them, and
`.gitignore` covers them in case they're copied under `home/` by hand. When you
add a secret, add its name to `home/.config/zsh/secrets.zsh.example`.

The pre-commit hook rejects staged lines that match `.githooks/secret-patterns`:
GitHub, npm, OpenAI-style, Slack and AWS tokens, private keys, and names
containing `token`, `secret`, `password` or `api_key` (in any case) assigned a
literal value with `=` or `:`. It refuses to commit if the patterns can't be
read or don't compile, and `dotfiles add`, `sync` and `merge` refuse to run.
`dotfiles add` refuses files that match, and `sync` and `merge` warn. It's a
safety net, not a guarantee: it misses formats such as `.netrc` lines and
Docker `auth` blobs. That's why `add` also refuses credential locations
(`~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker/config.json`, `~/.netrc`,
`~/.npmrc`, `~/.git-credentials`) whatever the path is spelled as, comparing
files by identity. This repo is public, so check `git diff --cached` before
every commit.
