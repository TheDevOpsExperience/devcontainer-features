#!/usr/bin/env bash
# idle-stop.sh — stop the container once VS Code has been gone for a grace
# period, so nothing runs unattended. Must run as root (it signals PID 1).
#
# Usage: sudo idle-stop.sh [--daemon]
#   --daemon   self-detach into a background worker, then return (nohup
#              orphaning pattern, so the postStart lifecycle command doesn't reap
#              the loop).
#
# Config (baked into flag files by core/install.sh from feature options):
#   <SHARE>/idle-stop.enabled   presence = enabled
#   <SHARE>/idle-grace          grace period in seconds (default 120)
#
# WHY a watchdog and not just devcontainer.json `shutdownAction`: shutdownAction
# only fires on VS Code *window close*; it does nothing for CLI-launched
# (`devcontainer up`) containers. This covers both.

set -euo pipefail

SHARE="/usr/local/share/devcontainer/core"
ENABLED_FLAG="$SHARE/idle-stop.enabled"
GRACE_FILE="$SHARE/idle-grace"
PID_FILE="/tmp/idle-stop.pid"
LOG="/var/log/idle-stop.log"
POLL=15

[ -f "$ENABLED_FLAG" ] || { echo "idle-stop disabled — not starting" >&2; exit 0; }

GRACE=120
[ -r "$GRACE_FILE" ] && GRACE="$(tr -dc '0-9' < "$GRACE_FILE")"
[ -n "$GRACE" ] || GRACE=120

DAEMON=false
for arg in "$@"; do
    case "$arg" in --daemon) DAEMON=true ;; esac
done

if $DAEMON; then
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "idle-stop already running (PID $(cat "$PID_FILE"))" >&2
        exit 0
    fi
    nohup "$0" </dev/null >>"$LOG" 2>&1 &
    echo $! > "$PID_FILE"
    echo "idle-stop watchdog started with PID $(cat "$PID_FILE"), grace ${GRACE}s" >&2
    exit 0
fi

echo $$ > "$PID_FILE"

# vscode_alive — is a VS Code server attached?
#
# The remote server LISTENS on /tmp/vscode-ipc-*.sock while connected; stale
# socket files left after disconnect have no listener, so file presence is not a
# liveness signal — we probe for an actual listener/connection.
#   1. ss (iproute2)  — accurate: a listening unix socket means the server is up.
#   2. socat          — connect-probe the newest socket (stale → connection fails).
#   3. pgrep (procps) — fallback; coarser, the server lingers briefly after
#                       disconnect, so grace is effectively a bit longer.
vscode_alive() {
    if command -v ss >/dev/null 2>&1; then
        ss -xln 2>/dev/null | grep -q 'vscode-ipc-.*\.sock' && return 0
        return 1
    fi
    if command -v socat >/dev/null 2>&1; then
        local sock
        sock=$(ls -t /tmp/vscode-ipc-*.sock 2>/dev/null | head -1) || true
        [ -n "$sock" ] && socat -u /dev/null "UNIX-CONNECT:$sock" 2>/dev/null && return 0
        return 1
    fi
    pgrep -f 'vscode-server' >/dev/null 2>&1 && return 0
    return 1
}

# Treat startup as "alive" so a slow first attach doesn't trip the timer.
last_alive=$(date +%s)

while true; do
    if vscode_alive; then
        last_alive=$(date +%s)
    else
        now=$(date +%s)
        if [ $((now - last_alive)) -ge "$GRACE" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') no VS Code for ${GRACE}s → stopping container" \
                | tee -a "$LOG" >&2 || true
            kill -TERM 1
            exit 0
        fi
    fi
    sleep "$POLL"
done
