#!/bin/bash
# firewall-lib.sh — shared functions for init-firewall.sh and refresh-firewall.sh.
# Source this file; do not execute it directly.

# resolve_all_domains <ipset_name> <extra_domains_file>
# Loads base domains (written by each feature during image build into
# /usr/local/share/devcontainer/domains.d/) plus any extra domains from
# <extra_domains_file>, resolves each via DNS (requires root), adds them to <ipset_name>,
# and prints "<ip> <domain>" lines to stdout for the caller to pass to write_hosts_entries.
resolve_all_domains() {
    local ipset_name="$1"
    local extra_domains_file="$2"

    local all_domains=()

    # Tier 1: base domains written by each feature during image build
    local domains_dir="/usr/local/share/devcontainer/domains.d"
    if [ -d "$domains_dir" ]; then
        for conf_file in "$domains_dir"/*.conf; do
            [ -f "$conf_file" ] || continue
            while IFS= read -r domain; do
                [[ -z "$domain" || "$domain" == \#* ]] && continue
                all_domains+=("$domain")
            done < "$conf_file"
        done
    fi

    # Tier 2: project-specific extra domains
    if [ -f "$extra_domains_file" ]; then
        echo "Loading extra domains from $extra_domains_file..." >&2
        while IFS= read -r domain; do
            [[ -z "$domain" || "$domain" == \#* ]] && continue
            all_domains+=("$domain")
            echo "  + $domain" >&2
        done < "$extra_domains_file"
    fi

    for entry in "${all_domains[@]}"; do
        # If the entry is a bare IPv4 address or CIDR range, add it directly — no DNS needed.
        if [[ "$entry" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
            echo "Adding IP/CIDR directly: $entry" >&2
            ipset add "$ipset_name" "$entry" 2>/dev/null || true
            continue
        fi

        local domain="$entry"
        echo "Resolving $domain..." >&2
        local ips
        ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
        if [ -z "$ips" ]; then
            echo "WARNING: Failed to resolve $domain, skipping" >&2
            continue
        fi
        while read -r ip; do
            if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "ERROR: Invalid IP from DNS for $domain: $ip" >&2
                return 1
            fi
            ipset add "$ipset_name" "$ip" 2>/dev/null || true
            echo "$ip $domain"
        done < <(echo "$ips")
    done
}

# write_hosts_entries <entry...>
# Atomically replaces the managed block in /etc/hosts with the given
# "<ip> <domain> # managed-domain" lines.
write_hosts_entries() {
    local entries=("$@")
    grep -v '# managed-domain' /etc/hosts > /tmp/hosts.clean || true
    cp /tmp/hosts.clean /etc/hosts
    rm -f /tmp/hosts.clean
    for entry in "${entries[@]}"; do
        echo "$entry # managed-domain" >> /etc/hosts
    done
}
