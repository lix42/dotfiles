# Homebrew: Apple Silicon, Intel macOS, then Linux
for brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  if [ -x "$brew" ]; then eval "$("$brew" shellenv)"; break; fi
done
unset brew

# Vite+ again: its env script moves its bin back in front of Homebrew's
if [ -r "$HOME/.vite-plus/env" ]; then . "$HOME/.vite-plus/env"; fi
