#!/bin/bash
set -e

# If the skip_permissions option was set at image-build time, alias `agy` to pass
# --dangerously-skip-permissions (skips confirmation prompts). Appropriate for
# sandboxed devcontainers where the firewall replaces the permission system.
# Absolute path in the alias avoids alias self-recursion. When the option is off,
# no alias is needed — `agy` is already on PATH via /etc/profile.d. (Alias is
# appended at create time, not every start, to avoid duplicating the line in
# ~/.zshrc on restart.)
if [ -f /usr/local/share/devcontainer/.antigravity-skip-permissions ]; then
  echo 'alias agy="$HOME/.local/bin/agy --dangerously-skip-permissions"' >> ~/.zshrc
fi
