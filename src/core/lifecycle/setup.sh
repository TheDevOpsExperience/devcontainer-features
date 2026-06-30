#!/bin/bash
set -e

# Lifecycle scripts run with the workspace folder as cwd.
DEVCONTAINER_INIT_CONFIG="$PWD/.devcontainer/.init"

if [ -f "${DEVCONTAINER_INIT_CONFIG}/generated-ssh-config" ]; then
  echo "→ Setting up SSH config..."
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  cp "${DEVCONTAINER_INIT_CONFIG}/generated-ssh-config" "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"
  if [ -d "${DEVCONTAINER_INIT_CONFIG}/ssh-keys" ]; then
    cp "${DEVCONTAINER_INIT_CONFIG}/ssh-keys/"* "$HOME/.ssh/"
  fi
fi

# .init cleanup is owned by attach.sh (postAttachCommand) — it runs on every
# attach, including reconnect, where this postStart hook does not fire.

sudo /usr/local/bin/fix-ownership.sh "$(id -un)"
sudo /usr/local/bin/fix-volume-ownership.sh "$(id -un)"

# Idle-stop watchdog (opt-in via the `idle_stop` core option). Detaches itself;
# never fail the lifecycle if it can't start.
if [ -f /usr/local/share/devcontainer/core/idle-stop.enabled ]; then
  echo "→ Starting idle-stop watchdog..."
  sudo /usr/local/bin/idle-stop.sh --daemon || true
fi
