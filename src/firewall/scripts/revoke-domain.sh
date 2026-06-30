#!/bin/bash
# revoke-domain.sh — remove a session domain or IP/CIDR from the firewall at
# runtime. The inverse of allow-domain.sh.
# Usage: sudo revoke-domain.sh <domain|ip|cidr>
#
# Drops the target's IPs from the allowed-domains ipset and removes the matching
# "# managed-domain" lines from /etc/hosts. Only affects session (runtime) grants
# — feature and persistent-project domains come back on the next refresh (they
# are rebuilt from domains.d/ and .firewall/allowed-domains.conf), so revoking
# them here is futile; edit the config instead. Logged to firewall-changes.log.

set -euo pipefail

target="${1:-}"
if [ -z "$target" ]; then
    echo "Usage: revoke-domain.sh <domain|ip|cidr>"
    exit 1
fi

LOG="/var/log/firewall-changes.log"
HOSTS="/etc/hosts"

remove_hosts_lines() {
    # Strip every "# managed-domain" line matching the awk predicate in $1.
    local predicate="$1"
    awk "!($predicate && /# managed-domain/)" "$HOSTS" > /tmp/hosts.revoke
    cat /tmp/hosts.revoke > "$HOSTS"
    rm -f /tmp/hosts.revoke
}

# IP / CIDR — drop straight from the ipset, scrub any hosts line carrying it.
if [[ "$target" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
    ipset del allowed-domains "$target" 2>/dev/null || true
    remove_hosts_lines "\$1 == \"$target\""
    echo "$(date '+%Y-%m-%d %H:%M:%S') IP_REVOKED $target" >> "$LOG" 2>/dev/null || true
    echo "$target revoked."
    exit 0
fi

domain="$target"

# Collect the IPs this domain resolved to from the managed /etc/hosts lines, then
# pull each out of the ipset.
ips=$(awk -v d="$domain" '$2 == d && /# managed-domain/ {print $1}' "$HOSTS" | sort -u)
if [ -z "$ips" ]; then
    echo "No session entry found for $domain (not a runtime grant, or already gone)."
    exit 1
fi

for ip in $ips; do
    ipset del allowed-domains "$ip" 2>/dev/null || true
done

remove_hosts_lines "\$2 == \"$domain\""

echo "$(date '+%Y-%m-%d %H:%M:%S') DOMAIN_REVOKED $domain → $(echo "$ips" | tr '\n' ',' | sed 's/,$//')" >> "$LOG" 2>/dev/null || true
echo "$domain revoked."
