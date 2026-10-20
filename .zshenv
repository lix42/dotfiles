if [ -r "$HOME/.cargo/env" ]; then . "$HOME/.cargo/env"; fi

# Vite+ bin (https://viteplus.dev)
if [ -r "$HOME/.vite-plus/env" ]; then . "$HOME/.vite-plus/env"; fi

# API keys: untracked, names listed in ~/.config/zsh/secrets.zsh.example
if [ -r "$HOME/.config/zsh/secrets.zsh" ]; then . "$HOME/.config/zsh/secrets.zsh"; fi
