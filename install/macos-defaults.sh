#!/bin/sh
# Apply macOS preferences. They live in each user's preferences, not in files
# under home/, so they are set with `defaults` rather than copied. No admin
# rights needed. Does nothing on other systems, and writes only what differs.
set -eu

if [ "$(uname -s)" != Darwin ]; then exit 0; fi

restart_dock=0

# set_bool DOMAIN KEY VALUE: VALUE is true or false.
set_bool() {
  want=0
  if [ "$3" = true ]; then want=1; fi
  if [ "$(defaults read "$1" "$2" 2>/dev/null || true)" != "$want" ]; then
    defaults write "$1" "$2" -bool "$3"
    printf '==> Set %s %s to %s\n' "$1" "$2" "$3"
    if [ "$1" = com.apple.dock ]; then restart_dock=1; fi
  fi
}

# Show the ⌘⇥ app switcher on every display, not only the one with the Dock.
set_bool com.apple.dock appswitcher-all-displays true

# The Dock applies its settings on restart; open windows are unaffected.
if [ "$restart_dock" -eq 1 ]; then killall Dock || true; fi
