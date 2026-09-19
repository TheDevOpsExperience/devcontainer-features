#!/bin/bash
set -e

# Lifecycle scripts run with the workspace folder as cwd. All project-specific
# firewall files (allowlist, ignore list, capture log) live together under
# .devcontainer/.firewall/.
FIREWALL_DIR="$PWD/.devcontainer/.firewall"
mkdir -p "$FIREWALL_DIR"
ALLOWED_DOMAINS_FILE="$FIREWALL_DIR/allowed-domains.conf"

# ── Firewall ──────────────────────────────────────────────────────────────────
# enabled=false (firewall.enabled option) skips lockdown + refresh entirely —
# all outbound traffic flows normally. DNS capture below still runs either way,
# so requested domains stay logged even with enforcement off.
if [ -f /usr/local/share/devcontainer/firewall/enabled ]; then
    echo "Setting up firewall..."
    sudo /usr/local/bin/init-firewall.sh "$ALLOWED_DOMAINS_FILE"

    echo "→ Starting firewall IP refresh loop (every 30 min)..."
    # --daemon self-detaches into a --loop worker and returns; don't background
    # here. The script guards against a loop already running.
    sudo -n /usr/local/bin/refresh-firewall.sh --daemon "$ALLOWED_DOMAINS_FILE"
    echo "Firewall refresh started"
else
    echo "Firewall disabled (enabled=false) — all outbound traffic is allowed."
    echo "DNS capture still runs, so requested domains are still logged (see below)."
fi

# ── DNS capture ───────────────────────────────────────────────────────────────
# Always runs, enabled or not. With the firewall off, nothing pre-populates
# /etc/hosts, so every domain does a real DNS lookup — the capture log ends up
# recording ALL requested domains, not just the denied/unknown ones.
ERRLOG="/tmp/capture-dns-start.log"
echo "Starting DNS capture daemon..."
# --daemon self-detaches into a --foreground worker and returns immediately; do
# NOT background it here. Backgrounding ties the worker to this postStart process
# group, which is reaped when the lifecycle command finishes.
sudo -n /usr/local/bin/capture-dns.sh --daemon "$FIREWALL_DIR" >>"$ERRLOG" 2>&1
echo "DNS capture started (log → $ERRLOG)"

# ── Firewall Monitor extension ────────────────────────────────────────────────
# install.sh copied the bundled .vsix; install it via the server MANAGEMENT CLI
# `code-server`, NOT the `remote-cli/code` wrapper. The wrapper is an IPC
# forwarder that needs VSCODE_IPC_HOOK_CLI (set only inside the integrated
# terminal); in a lifecycle hook that var is unset, so it just prints "Command
# is only available in WSL or inside a Visual Studio Code terminal" and exits 0
# without installing. `code-server --install-extension` runs headless and works.
# Done at postStart (before the editor attaches) so the extension is on disk when
# the extension host first enumerates → loads on first attach, no reload needed.
# Best effort — never fail the lifecycle. Logged to /tmp for debugging.
VSIX="/usr/local/share/devcontainer/firewall/firewall-monitor.vsix"
EXT_LOG="/tmp/firewall-extension.log"
EXT_ID="thedevopsexperience.firewall-monitor"
if [ -f /usr/local/share/devcontainer/firewall/install-extension.enabled ] && [ -f "$VSIX" ]; then
  {
    echo "=== $(date) firewall-monitor extension install (postStart) ==="
    CODE_SERVER="$(ls -t \
      "$HOME"/.vscode-server/bin/*/bin/code-server \
      /vscode/vscode-server/bin/*/bin/code-server \
      2>/dev/null | head -1 || true)"
    echo "CODE_SERVER=${CODE_SERVER:-<none>}"
    if [ -z "$CODE_SERVER" ]; then
      echo "code-server CLI not found — skipping extension install"
    elif "$CODE_SERVER" --list-extensions 2>/dev/null | grep -qix "$EXT_ID"; then
      echo "already installed — skip"
    else
      "$CODE_SERVER" --install-extension "$VSIX" --force || echo "install failed"
      echo "after: $("$CODE_SERVER" --list-extensions 2>&1 | tr '\n' ' ')"
    fi
  } >>"$EXT_LOG" 2>&1
fi
