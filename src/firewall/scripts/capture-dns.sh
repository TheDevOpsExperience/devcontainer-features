#!/usr/bin/env bash
# Capture all DNS lookups attempted by the sandboxed user.
#
# DNS queries from the sandboxed user are rejected by iptables before they
# reach the network interface, so tcpdump on a real interface never sees them.
# This script inserts a temporary iptables NFLOG rule (non-terminating) that
# mirrors the packets into a netlink queue *before* the REJECT fires.
# tcpdump reads from that queue via "-i nflog:GROUP".
#
# Usage: sudo capture-dns.sh [--daemon] [firewall-dir]
#   --daemon       background mode: no summary on exit (interactive prints on Ctrl-C)
#   firewall-dir   where ignored-domains.conf is read from (default: the dir
#                  recorded by init-firewall.sh, falling back to
#                  /workspace/.devcontainer/.firewall)
#
# Two logs (both /var/log, root-owned so the sandbox user can't tamper, ephemeral
# — reset on container rebuild):
#   /var/log/firewall-dns.log        session log — EVERY attempt with a full
#                                    timestamp; TRUNCATED on each start. Drives the
#                                    extension's count + last-seen.
#   /var/log/firewall-dns-audit.log  audit log — deduped, append-only, one
#                                    first-seen line per domain; survives stop/start
#                                    within a build (SEEN is seeded from it).
#
# The script runs via sudo — SUDO_UID identifies the sandboxed user to capture.
# PID file: /tmp/dns-capture.pid

set -euo pipefail

DAEMON=false
FOREGROUND=false
# Default: the dir recorded by init-firewall.sh at container start; /workspace
# only as last resort. An explicit argument overrides both.
FIREWALL_DIR="$(cat /usr/local/share/devcontainer/firewall-dir 2>/dev/null || echo /workspace/.devcontainer/.firewall)"
for arg in "$@"; do
  case "$arg" in
    --daemon) DAEMON=true ;;
    --foreground) FOREGROUND=true ;;
    *) FIREWALL_DIR="$arg" ;;
  esac
done

CAPTURE_UID="${SUDO_UID:-1000}"
RUN_LOG="/tmp/capture-dns-daemon.log"
LOG="/var/log/firewall-dns.log"
AUDIT="/var/log/firewall-dns-audit.log"
IGNORED_FILE="${FIREWALL_DIR}/ignored-domains.conf"
PID_FILE="/tmp/dns-capture.pid"
mkdir -p "$FIREWALL_DIR"
NFLOG_GROUP=53
TCPDUMP_PID=""

# --daemon: self-detach into a --foreground worker, then return immediately.
# Running the capture loop inline under --daemon ties it to the caller's process
# group, so the postStart lifecycle command reaps it when it finishes. nohup +
# stdin from /dev/null orphans the worker so it survives.
if $DAEMON; then
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "capture-dns.sh is already running (PID $(cat "$PID_FILE"))" >&2
    exit 0
  fi
  nohup "$0" --foreground "$FIREWALL_DIR" </dev/null >>"$RUN_LOG" 2>&1 &
  echo $! > "$PID_FILE"
  echo "capture-dns daemon started with PID $(cat "$PID_FILE")" >&2
  exit 0
fi

SEEN=$(mktemp)
# Seed the dedup set from the audit log so first-seen tracking spans restarts
# (the audit log is append-only and survives stop/start within a build).
[ -f "$AUDIT" ] && awk '{print $NF}' "$AUDIT" >> "$SEEN" 2>/dev/null || true
FIFO=$(mktemp -u /tmp/dns-fifo-XXXXXX)
mkfifo "$FIFO"

is_ignored() {
  local domain="$1"
  [[ -f "$IGNORED_FILE" ]] || return 1
  while IFS= read -r pattern; do
    [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
    pattern="${pattern%%#*}"          # strip inline comments
    pattern="${pattern//[[:space:]]/}" # strip whitespace
    [[ -z "$pattern" ]] && continue
    if [[ "$pattern" == \*.* ]]; then
      [[ "$domain" == *."${pattern#\*.}" ]] && return 0
    else
      [[ "$domain" == "$pattern" ]] && return 0
    fi
  done < "$IGNORED_FILE"
  return 1
}

cleanup() {
  # Kill tcpdump explicitly — it's a child process in the pipeline and won't
  # die automatically when the script exits via a signal.
  [[ -n "$TCPDUMP_PID" ]] && kill "$TCPDUMP_PID" 2>/dev/null || true
  rm -f "$FIFO" "$SEEN"
  # Loop to remove ALL copies of our rules (handles duplicates from past crashes)
  while iptables -t raw -D OUTPUT -m owner --uid-owner "$CAPTURE_UID" -p udp --dport 53 \
        -j NFLOG --nflog-group "$NFLOG_GROUP" 2>/dev/null; do :; done
  while iptables -t raw -D OUTPUT -m owner --uid-owner "$CAPTURE_UID" -p tcp --dport 53 \
        -j NFLOG --nflog-group "$NFLOG_GROUP" 2>/dev/null; do :; done
  if ! $DAEMON; then
    echo ""
    echo "--- Unique domains captured (audit) ---"
    awk '{print $NF}' "$AUDIT" 2>/dev/null | sort -u | grep . || echo "(none)"
    echo "--- Session log: $LOG   Audit log: $AUDIT ---"
  fi
}
trap cleanup EXIT INT TERM HUP

# Kill any leftover tcpdump from a previous crashed run holding this nflog group,
# then remove any duplicate rules it may have left behind.
pkill -f "tcpdump.*nflog:${NFLOG_GROUP}" 2>/dev/null || true
sleep 0.2
while iptables -t raw -D OUTPUT -m owner --uid-owner "$CAPTURE_UID" -p udp --dport 53 \
      -j NFLOG --nflog-group "$NFLOG_GROUP" 2>/dev/null; do :; done
while iptables -t raw -D OUTPUT -m owner --uid-owner "$CAPTURE_UID" -p tcp --dport 53 \
      -j NFLOG --nflog-group "$NFLOG_GROUP" 2>/dev/null; do :; done

# Insert NFLOG rules in the raw table so they fire BEFORE Docker's NAT redirects
# DNS queries from port 53 to an internal port (which would make them invisible to
# the filter table where NFLOG previously lived).
iptables -t raw -I OUTPUT 1 -m owner --uid-owner "$CAPTURE_UID" -p udp --dport 53 \
         -j NFLOG --nflog-group "$NFLOG_GROUP"
iptables -t raw -I OUTPUT 2 -m owner --uid-owner "$CAPTURE_UID" -p tcp --dport 53 \
         -j NFLOG --nflog-group "$NFLOG_GROUP"

# Truncate the session log on each start; the audit log is append-only.
: > "$LOG"
echo "# DNS session capture started $(date)" >> "$LOG"
touch "$AUDIT"
echo $$ > "$PID_FILE"

$DAEMON || echo "Capturing DNS queries → $LOG  (Ctrl-C to stop)"

# Watchdog: restart the entire pipeline if tcpdump dies for any reason.
# SEEN persists across restarts so domains are not re-logged after each restart.
while true; do
  tcpdump -i "nflog:${NFLOG_GROUP}" -n -l > "$FIFO" 2>/dev/null &
  TCPDUMP_PID=$!

  grep --line-buffered -oP '(?<=[\s>])[A-Za-z0-9._-]+(?=\.\s+\(|\.\s*$)' "$FIFO" \
    | grep --line-buffered -v '^\.' \
    | while IFS= read -r domain; do
        domain="${domain%.}"
        if [[ "$domain" =~ \. ]] && ! [[ "$domain" =~ ^[0-9.]+$ ]]; then
          is_ignored "$domain" && continue
          ts="$(date '+%Y-%m-%d %H:%M:%S')"
          # Session log: every attempt (count + last-seen). Quiet in the detached
          # worker; echo to the terminal when run interactively.
          if $FOREGROUND; then echo "$ts  $domain" >> "$LOG"; else echo "$ts  $domain" | tee -a "$LOG"; fi
          # Audit log: first sighting only, deduped across restarts via SEEN.
          if ! grep -qxF "$domain" "$SEEN" 2>/dev/null; then
            echo "$domain" >> "$SEEN"
            echo "$ts  first-seen  $domain" >> "$AUDIT"
          fi
        fi
      done || true

  # Pipeline exited — log and restart after a short pause.
  # Trap fires on EXIT/INT/TERM/HUP and kills tcpdump before we loop again.
  echo "$(date '+%H:%M:%S')  [capture-dns] tcpdump pipeline exited, restarting in 2s..." >&2
  sleep 2
done
