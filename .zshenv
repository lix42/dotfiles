if [ -r "$HOME/.cargo/env" ]; then . "$HOME/.cargo/env"; fi

# Vite+ bin (https://viteplus.dev)
if [ -r "$HOME/.vite-plus/env" ]; then . "$HOME/.vite-plus/env"; fi

# ~/.local/bin (uv, claude, dotcfg): here so non-interactive shells have it too
if [ -r "$HOME/.local/bin/env" ]; then . "$HOME/.local/bin/env"; fi

# API keys: untracked, names listed in ~/.config/zsh/secrets.zsh.example
if [ -r "$HOME/.config/zsh/secrets.zsh" ]; then . "$HOME/.config/zsh/secrets.zsh"; fi
