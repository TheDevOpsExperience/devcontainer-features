#!/bin/bash
set -e

# If the skip_permissions option was set at image-build time, alias `codex` to
# pass --dangerously-bypass-approvals-and-sandbox (skips approval prompts and the
# built-in sandbox). Appropriate for sandboxed devcontainers where the firewall
# replaces the permission system. Absolute path in the alias avoids alias
# self-recursion. When the option is off, no alias is needed — `codex` is already
# on PATH via /etc/profile.d. (Alias is appended at create time, not every start,
# to avoid duplicating the line in ~/.zshrc on restart.)
if [ -f /usr/local/share/devcontainer/.codex-skip-permissions ]; then
  echo 'alias codex="$HOME/.local/bin/codex --yolo"' >> ~/.zshrc
fi
