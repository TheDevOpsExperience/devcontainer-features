#!/bin/bash
set -euo pipefail

# Refreshes the allowed-domains ipset and /etc/hosts without touching iptables rules.
# Uses ipset swap for atomic replacement — no protection gap.
#
# Rebuilds only from domains.d/ and the extra-domains file. Session domains
# added via allow-domain.sh are intentionally dropped — they are temporary by
# design and live only until the next refresh or container restart.

MODE=oneshot
EXTRA_DOMAINS_FILE=""
for arg in "$@"; do
  case "$arg" in
    --daemon) MODE=daemon ;;
    --loop)   MODE=loop ;;
    *)        EXTRA_DOMAINS_FILE="$arg" ;;
  esac
done

PID_FILE="/tmp/refresh-firewall.pid"
RUN_LOG="/tmp/refresh-firewall-daemon.log"
INTERVAL=1800

# --daemon: self-detach into a --loop worker, then return immediately (same
# pattern as capture-dns.sh). Backgrounding the loop from the caller would tie it
# to the postStart process group, which is reaped when the lifecycle command
# finishes. nohup + stdin from /dev/null orphans the worker so it survives.
if [ "$MODE" = daemon ]; then
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "refresh-firewall loop already running (PID $(cat "$PID_FILE"))" >&2
    exit 0
  fi
  nohup "$0" --loop "$EXTRA_DOMAINS_FILE" </dev/null >>"$RUN_LOG" 2>&1 &
  echo $! > "$PID_FILE"
  echo "refresh-firewall loop started with PID $(cat "$PID_FILE")" >&2
  exit 0
fi

# --loop: the detached worker. Re-invokes this script in oneshot mode every
# INTERVAL. The loop already runs as root, so no nested sudo is needed.
if [ "$MODE" = loop ]; then
  echo $$ > "$PID_FILE"
  while true; do
    sleep "$INTERVAL"
    "$0" "$EXTRA_DOMAINS_FILE" 2>&1 | logger -t firewall-refresh || true
  done
fi

# shellcheck source=firewall-lib.sh
source "$(dirname "$0")/firewall-lib.sh"

echo "[firewall-refresh] Starting IP refresh..."

# Destroy any leftover temp set from a previous crashed run before creating a fresh one
ipset destroy allowed-domains-new 2>/dev/null || true
ipset create allowed-domains-new hash:net

mapfile -t HOSTS_ENTRIES < <(resolve_all_domains allowed-domains-new "$EXTRA_DOMAINS_FILE")

ipset swap allowed-domains allowed-domains-new
ipset destroy allowed-domains-new

write_hosts_entries "${HOSTS_ENTRIES[@]}"

echo "[firewall-refresh] Done"
