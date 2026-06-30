#!/bin/bash
set -euo pipefail

# init-firewall.sh — build the default-deny egress firewall from scratch.
#
# Strategy: drop everything by default, then poke holes for (a) the container's
# own DNS resolver, (b) the Docker host subnet, (c) loopback, and (d) the IPs
# behind the allowlisted domains (tracked in the `allowed-domains` ipset). DNS
# itself is locked to the resolver so it can't be used as a covert channel.

EXTRA_DOMAINS_FILE="${1:-}"

# Remember the project's .firewall dir (where allowed-domains.conf lives) so the
# runtime helpers (list-domains.sh, capture-dns.sh) don't have to guess the path.
if [ -n "$EXTRA_DOMAINS_FILE" ]; then
    dirname "$EXTRA_DOMAINS_FILE" > /usr/local/share/devcontainer/firewall-dir
fi

# shellcheck source=firewall-lib.sh
source "$(dirname "$0")/firewall-lib.sh"

# Docker injects its embedded-DNS plumbing (127.0.0.11) into the nat table. We
# are about to flush everything, so grab those entries first and replay them
# afterwards — otherwise name resolution inside the container dies. Save the
# chain declarations separately because iptables-restore needs the chains to
# exist before any rule references them.
NAT_DUMP=$(iptables-save -t nat)
DNS_CHAIN_DEFS=$(echo "$NAT_DUMP" | grep "^:DOCKER_" || true)
DNS_NAT_RULES=$(echo "$NAT_DUMP" | grep -E "127\.0\.0\.11|-j DOCKER_" || true)

# Wipe the slate: all three tables plus the domain ipset.
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# There is no IPv6 allowlist, so a reachable IPv6 stack would be an open back
# door around all of this. Where ip6tables exists, slam it shut (loopback aside).
if command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1; then
    ip6tables -F
    ip6tables -X
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
    echo "IPv6 traffic blocked (loopback allowed)"
else
    echo "ip6tables unavailable — skipping IPv6 rules (IPv6 likely disabled in kernel)"
fi

# Replay the Docker DNS nat entries captured above. Feed them through
# iptables-restore (not a shell loop) so multi-token rules parse correctly.
if [ -n "$DNS_CHAIN_DEFS" ] || [ -n "$DNS_NAT_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    {
        printf '*nat\n'
        [ -n "$DNS_CHAIN_DEFS" ] && printf '%s\n' "$DNS_CHAIN_DEFS"
        [ -n "$DNS_NAT_RULES" ]  && printf '%s\n' "$DNS_NAT_RULES"
        printf 'COMMIT\n'
    } | iptables-restore --noflush
else
    echo "No Docker DNS rules to restore"
fi

# Permit DNS (53/udp+tcp) only toward the resolvers named in resolv.conf. Any
# other destination port 53 stays blocked, which closes off DNS tunnelling.
for dns_ip in $(grep '^nameserver' /etc/resolv.conf | awk '{print $2}'); do
    iptables -A OUTPUT -p udp --dport 53 -d "$dns_ip" -j ACCEPT
    iptables -A INPUT -p udp --sport 53 -s "$dns_ip" -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -d "$dns_ip" -j ACCEPT
    iptables -A INPUT -p tcp --sport 53 -s "$dns_ip" -j ACCEPT
done
# resolv.conf doesn't always list Docker's embedded resolver — allow it too.
iptables -A OUTPUT -p udp --dport 53 -d 127.0.0.11 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -s 127.0.0.11 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d 127.0.0.11 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -s 127.0.0.11 -j ACCEPT

# The allowlist set holds both single IPs and CIDR blocks (hash:net).
ipset create allowed-domains hash:net 2>/dev/null || true

iptables -A OUTPUT -p tcp --dport 22 -m set --match-set allowed-domains dst -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT

# Loopback is always fine.
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Resolve every configured domain into the ipset and mirror the results into
# /etc/hosts. RESOLVED_PAIRS holds "<ip> <domain>" lines for reuse below.
mapfile -t RESOLVED_PAIRS < <(resolve_all_domains allowed-domains "$EXTRA_DOMAINS_FILE")
write_hosts_entries "${RESOLVED_PAIRS[@]}"

# Keep the container reachable from its host / sibling containers. Derive the
# real subnet from the default interface's kernel-scope route rather than
# munging the gateway address — string-editing the gateway breaks whenever the
# third octet isn't zero (e.g. Docker Desktop's 192.168.65.0/24).
GATEWAY_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$GATEWAY_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
LOCAL_SUBNET=$(ip -o -f inet route show dev "$DEFAULT_IFACE" proto kernel scope link | awk '{print $1}' | head -n1)
if [ -z "$LOCAL_SUBNET" ]; then
    LOCAL_SUBNET="${GATEWAY_IP}/32"
fi
echo "Host network detected as: $LOCAL_SUBNET"

iptables -A INPUT -s "$LOCAL_SUBNET" -j ACCEPT
iptables -A OUTPUT -d "$LOCAL_SUBNET" -j ACCEPT

# Flip the defaults to deny now that the allow rules are in place.
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Let return traffic for already-open connections through.
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# The actual allowlist: outbound to any IP in the set.
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Anything not explicitly allowed is rejected (with an ICMP notice, not a silent drop).
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# Belt-and-suspenders: stop the sandbox user from talking DNS to anything but
# the rules above. The raw table runs ahead of Docker's nat redirect, so this
# bites first. Running under sudo, SUDO_UID is the human user that invoked us.
SANDBOX_UID="${SUDO_UID:-1000}"
iptables -t raw -I OUTPUT 1 -m owner --uid-owner "$SANDBOX_UID" -p udp --dport 53 -j DROP
iptables -t raw -I OUTPUT 2 -m owner --uid-owner "$SANDBOX_UID" -p tcp --dport 53 -j DROP
echo "DNS blocked for uid $SANDBOX_UID."

# ── Sanity checks ─────────────────────────────────────────────────────────────
echo "Verifying firewall..."

# A site that is NOT on the allowlist must fail.
echo "  Testing blocked site (example.com)..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - able to reach example.com"
    exit 1
else
    echo "  ✓ Traffic to example.com is blocked"
fi

# The allowlist should not be empty (don't pin the check to a specific domain).
ALLOWED_IP_COUNT=$(ipset list allowed-domains | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
if [ "$ALLOWED_IP_COUNT" -eq 0 ]; then
    echo "  WARNING: allowed-domains ipset is empty — no domains were allowlisted"
else
    echo "  ✓ $ALLOWED_IP_COUNT IP(s) in allowed-domains ipset"
fi

# Probe the first domain we already resolved (reuse RESOLVED_PAIRS, don't re-scan).
PROBE_DOMAIN=""
for _pair in "${RESOLVED_PAIRS[@]}"; do
    PROBE_DOMAIN=$(awk '{print $2}' <<< "$_pair")
    [ -n "$PROBE_DOMAIN" ] && break
done

if [ -n "$PROBE_DOMAIN" ]; then
    echo "  Testing allowed domain ($PROBE_DOMAIN)..."
    # No -f: any successful TCP+TLS handshake counts, regardless of HTTP status —
    # we're testing reachability, not what the server returns.
    if curl --connect-timeout 5 --silent "https://${PROBE_DOMAIN}" -o /dev/null 2>&1; then
        echo "  ✓ $PROBE_DOMAIN is reachable"
    else
        echo "ERROR: Firewall verification failed — unable to reach $PROBE_DOMAIN"
        exit 1
    fi
else
    echo "  (no domains resolved — skipping allowed-domain connectivity test)"
fi

echo "Firewall configuration complete"
