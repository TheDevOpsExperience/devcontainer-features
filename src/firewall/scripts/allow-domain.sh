#!/bin/bash
# allow-domain.sh — add a domain to the firewall whitelist at runtime.
# Usage: sudo allow-domain.sh <domain> [ip]
#        sudo allow-domain.sh <ip|cidr>
#
# Resolves the domain to IP addresses (via DNS), adds them to the allowed-domains
# ipset and writes /etc/hosts entries so the name resolves without further DNS.
# When DNS can't resolve the name (split-horizon / hosts-only names such as
# metadata.google.internal), pass the IP explicitly as a second argument to
# bypass resolution and write the hosts entry directly.
#
# Changes are deliberately temporary: they are cleared by the next periodic
# firewall refresh (every 30 min) or container restart, whichever comes first.
# Add the domain to .devcontainer/.firewall/allowed-domains.conf for persistence.

set -euo pipefail

target="${1:-}"
explicit_ip="${2:-}"

is_ip() { [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; }

if [ -z "$target" ]; then
    echo "Usage: allow-domain.sh <domain> [ip]   |   allow-domain.sh <ip|cidr>" >&2
    exit 1
fi

# Single IP/CIDR argument: add directly to the ipset (no hosts entry needed).
if [ -z "$explicit_ip" ] && is_ip "$target"; then
    echo "Adding IP/CIDR directly: $target"
    ipset add allowed-domains "$target" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') IP_ADDED $target" >> /var/log/firewall-changes.log 2>/dev/null || true
    echo "$target is now accessible."
    exit 0
fi

domain="$target"

# Two-argument form: domain + explicit IP. Bypass DNS, trust the caller's IP,
# add it to the ipset and write the hosts entry so the name resolves.
if [ -n "$explicit_ip" ]; then
    if ! is_ip "$explicit_ip"; then
        echo "Second argument must be an IP or CIDR, got: $explicit_ip" >&2
        exit 1
    fi
    ipset add allowed-domains "$explicit_ip" 2>/dev/null || true
    grep -qF "$explicit_ip $domain" /etc/hosts 2>/dev/null || echo "$explicit_ip $domain # managed-domain" >> /etc/hosts
    echo "$(date '+%Y-%m-%d %H:%M:%S') DOMAIN_ADDED $domain → $explicit_ip (explicit)" >> /var/log/firewall-changes.log 2>/dev/null || true
    echo "$domain → $explicit_ip is now accessible."
    exit 0
fi

# Resolve via DNS. `|| true` keeps a failed lookup from tripping `set -e` before
# we can report it — pipefail would otherwise abort the script silently here.
ips=$(dig +short A "$domain" | grep -E '^[0-9]' | sort -u) || true
if [ -z "$ips" ]; then
    echo "Failed to resolve $domain via DNS." >&2
    echo "If this name is hosts-only (e.g. metadata.google.internal), pass the IP explicitly:" >&2
    echo "    sudo allow-domain.sh $domain <ip>" >&2
    exit 1
fi

echo "Resolving $domain → $(echo "$ips" | tr '\n' ', ' | sed 's/,$//')"

for ip in $ips; do
    ipset add allowed-domains "$ip" 2>/dev/null || true
    grep -qF "$ip $domain" /etc/hosts 2>/dev/null || echo "$ip $domain # managed-domain" >> /etc/hosts
done

echo "$(date '+%Y-%m-%d %H:%M:%S') DOMAIN_ADDED $domain → $ips" >> /var/log/firewall-changes.log 2>/dev/null || true
echo "$domain is now accessible."
