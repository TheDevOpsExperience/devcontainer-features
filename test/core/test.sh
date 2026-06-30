#!/bin/bash
set -e

source dev-container-features-test-lib

check "core marker exists" test -f /usr/local/share/devcontainer/.core-installed
check "zsh installed" bash -c "command -v zsh"
check "git installed" bash -c "command -v git"
check "jq installed" bash -c "command -v jq"
check "gpg installed" bash -c "command -v gpg"
check "sudo installed" bash -c "command -v sudo"
check "install-package.sh present" test -x /usr/local/bin/install-package.sh

# ── idle-stop (default OFF) ───────────────────────────────────────────────────
check "idle-stop.sh present" test -x /usr/local/bin/idle-stop.sh
check "sudoers grants idle-stop.sh" \
  bash -c "sudo -n grep -q '/usr/local/bin/idle-stop.sh' /etc/sudoers.d/core-feature"
check "idle-grace defaults to 120" \
  bash -c "grep -qx 120 /usr/local/share/devcontainer/core/idle-grace"
check "idle-stop disabled by default (no enabled flag)" \
  bash -c "! test -f /usr/local/share/devcontainer/core/idle-stop.enabled"
check "idle-stop.sh exits when disabled" \
  bash -c "sudo -n /usr/local/bin/idle-stop.sh 2>&1 | grep -q 'disabled'"

reportResults
