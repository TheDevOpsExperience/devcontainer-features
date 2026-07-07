#!/bin/bash
set -e

if [ ! -f /dc-volumes/commandhistory/.zsh_profile ]; then
  touch /dc-volumes/commandhistory/.zsh_profile
fi

cat /dc-volumes/commandhistory/.zsh_profile >> ~/.zshrc

# Merge the oh-my-zsh plugin registry into the .zshrc plugins=() array.
# Runs after every feature's install.sh, so all <feature>.conf files are
# present. git/fzf are core's always-on baseline. Regenerated from the
# registry each create, so it's idempotent across rebuilds.
PLUGDIR=/usr/local/share/devcontainer/zsh-plugins.d
if [ -f ~/.zshrc ] && grep -q '^plugins=(' ~/.zshrc; then
  plugins=$( { printf 'git\nfzf\n'; [ -d "$PLUGDIR" ] && cat "$PLUGDIR"/*.conf 2>/dev/null; } \
    | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ *$//' )
  sed -i "s/^plugins=(.*)/plugins=($plugins)/" ~/.zshrc
fi
