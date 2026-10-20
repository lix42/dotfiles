# dotfiles

Config shared by all my machines, tracked as a bare Git repo whose work tree is
`$HOME`. Files live where the tools expect them: no symlinks, no extra tooling.

One `main` branch holds only what is common to every machine. Machine-specific
settings and secrets stay in local, untracked files (see below).

## What's tracked

| Path | Purpose |
|---|---|
| `.claude/statusline-command.sh` | Claude Code status line (needs `jq`, `git`) |
| `.local/bin/dotcfg` | `git` for this repo; works in every shell and script |
| `.zshenv` | Every zsh: cargo, Vite+ and `~/.local/bin` on PATH, loads `secrets.zsh` |
| `.zprofile` | Login shells: Homebrew (Apple Silicon, Intel, or Linux), then `~/.local/bin` first again |
| `.zshrc` | Interactive shells: Oh My Zsh (must be installed), tools, aliases, loads `local.zsh` |
| `.config/zsh/secrets.zsh.example` | Names of the secrets each machine needs |
| `.config/dotfiles/bootstrap.sh` | Sets up a new machine; safe to re-run |
| `.config/dotfiles/hooks/pre-commit` | Blocks commits that look like they contain a credential |
| `.github/README.md` | This file (GitHub renders it as the repo README) |

## New machine

The repo is private, so Git needs GitHub credentials first
(`gh auth login && gh auth setup-git`, or an SSH key).

```sh
git clone --bare https://github.com/lix42/dotfiles.git ~/.cfg
git --git-dir="$HOME/.cfg" show main:.config/dotfiles/bootstrap.sh | sh
```

`bootstrap.sh`:

1. Clones the bare repo to `~/.cfg` if it is not there yet.
2. Configures it: hides untracked files from `status`, tracks `origin`, and
   enables the pre-commit hook.
3. Lists the local-only files in `~/.cfg/info/exclude`.
4. On the first run only, moves any existing file that the repo would overwrite
   to `~/.cfg-backup/<timestamp>/`, then checks out `main`.
5. Creates `~/.config/zsh/local.zsh` and `~/.config/zsh/secrets.zsh` (mode 600)
   if they are missing.
6. Sets `statusLine` in `~/.claude/settings.json`, leaving every other setting
   as it is, and backs up the file first.

Then open a new shell. `dotcfg` is `~/.local/bin/dotcfg`, which `~/.zshenv`
puts on PATH for every zsh, including non-interactive ones such as scripts and
Claude Code's `!` commands. Interactive shells also define a `dotcfg` alias
with the same meaning, because git's tab completion only finds the repo when
`--git-dir` and `--work-tree` appear on the command line.

## Daily use

```sh
dotcfg status                 # tracked files only
dotcfg add ~/.zshrc           # start tracking a file: always name it explicitly
dotcfg commit -m "…"
dotcfg pull
dotcfg push
```

Never run `dotcfg add .`, `dotcfg add -A`, or `dotcfg clean`: the work tree is
your whole home directory.

## Machine-specific settings and secrets

Shared zsh files load two local files that are never committed:

| File | Holds |
|---|---|
| `~/.config/zsh/local.zsh` | Machine-specific settings: `ARCHFLAGS`, unusual install paths, work-only tools |
| `~/.config/zsh/secrets.zsh` | API keys and tokens; mode 600 |

Load them from the shared files. Use `if`, not `[ -r … ] && .`: when the file
is missing, the `&&` form leaves status 1 behind, and the first prompt shows a
failure.

```sh
# ~/.zshenv: secrets, so non-interactive shells get them too
if [ -r "$HOME/.config/zsh/secrets.zsh" ]; then . "$HOME/.config/zsh/secrets.zsh"; fi

# end of ~/.zshrc: machine-specific settings, so they win over shared defaults
if [ -r "$HOME/.config/zsh/local.zsh" ]; then . "$HOME/.config/zsh/local.zsh"; fi
```

Rules for the shared files:

- Use `$HOME`, never `/Users/<name>`.
- Set up a tool only if it is installed, for example
  `if [ -d "$HOME/.bun" ]; then …; fi` or
  `if (( $+commands[starship] )); then eval "$(starship init zsh)"; fi`.
- When you add a secret, add its name to `secrets.zsh.example`.

The pre-commit hook rejects staged lines that look like GitHub, OpenAI-style,
Slack, or AWS tokens, private keys, or literal `*TOKEN=` / `*SECRET=` /
`*PASSWORD=` / `*API_KEY=` values. It is a safety net, not a guarantee; check
`dotcfg diff --cached` before committing.
