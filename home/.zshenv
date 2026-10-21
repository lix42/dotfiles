# Put a bin dir first on PATH when it exists and isn't there yet. Done here
# rather than by sourcing installers' env scripts: run without letting them edit
# rc files (as install/tools.sh does), uv doesn't write ~/.local/bin/env.
prepend_path() { if [[ -d $1 && ${path[(Ie)$1]} -eq 0 ]]; then path=("$1" $path); fi; }

# Rust (rustup)
prepend_path "$HOME/.cargo/bin"

# Vite+ bin (https://viteplus.dev)
if [ -r "$HOME/.vite-plus/env" ]; then . "$HOME/.vite-plus/env"; fi

# ~/.local/bin (uv, claude, starship, dotfiles): here so non-interactive shells have it too
prepend_path "$HOME/.local/bin"

unfunction prepend_path

# API keys: untracked, names listed in ~/.config/zsh/secrets.zsh.example
if [ -r "$HOME/.config/zsh/secrets.zsh" ]; then . "$HOME/.config/zsh/secrets.zsh"; fi
