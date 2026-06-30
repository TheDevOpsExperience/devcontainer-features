#!/bin/bash
# list-domains.sh — list all firewall-allowed domains with their persistence tier.
# No sudo required.
#
# Tiers:
#   feature    — registered by a devcontainer feature in domains.d/
#   persistent — listed in <workspace>/.devcontainer/.firewall/allowed-domains.conf
#   session    — added at runtime via allow-domain.sh; deliberately temporary,
#                cleared by the next periodic firewall refresh (every 30 min)
#                or container restart

set -eo pipefail

# --json emits machine-readable porcelain (consumed by the firewall-monitor
# VS Code extension) instead of the human-coloured report. Same classification.
JSON=false
for arg in "$@"; do
    case "$arg" in
        --json) JSON=true ;;
    esac
done

DOMAINS_D="/usr/local/share/devcontainer/domains.d"
# Firewall dir: env override > dir recorded by init-firewall.sh at
# container start > /workspace fallback.
if [ -z "${FIREWALL_DIR:-}" ]; then
    FIREWALL_DIR="$(cat /usr/local/share/devcontainer/firewall-dir 2>/dev/null || echo /workspace/.devcontainer/.firewall)"
fi
ALLOWED_DOMAINS_FILE="${FIREWALL_DIR}/allowed-domains.conf"
FIREWALL_LOG="/var/log/firewall-changes.log"

BOLD='\033[1m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

# ── Collect feature domains ───────────────────────────────────────────────────
declare -A feature_for_domain  # domain → feature-name
if [ -d "$DOMAINS_D" ]; then
    for conf in "$DOMAINS_D"/*.conf; do
        [ -f "$conf" ] || continue
        feature_name=$(basename "$conf" .conf)
        while IFS= read -r domain; do
            [[ -z "$domain" || "$domain" == \#* ]] && continue
            feature_for_domain["$domain"]="$feature_name"
        done < "$conf"
    done
fi

# ── Collect persistent project domains ───────────────────────────────────────
declare -A is_persistent
if [ -f "$ALLOWED_DOMAINS_FILE" ]; then
    while IFS= read -r domain; do
        [[ -z "$domain" || "$domain" == \#* ]] && continue
        is_persistent["$domain"]=1
    done < "$ALLOWED_DOMAINS_FILE"
fi

# ── Collect active domain→IP mappings from /etc/hosts ────────────────────────
# Line format (written by firewall scripts): "<ip> <domain> # managed-domain"
declare -A host_ips  # domain → "ip1, ip2, ..."
while IFS= read -r line; do
    [[ "$line" == *"# managed-domain"* ]] || continue
    ip=$(awk '{print $1}' <<< "$line")
    domain=$(awk '{print $2}' <<< "$line")
    [[ -z "$ip" || -z "$domain" ]] && continue
    if [ -n "${host_ips[$domain]+_}" ]; then
        host_ips["$domain"]="${host_ips[$domain]}, $ip"
    else
        host_ips["$domain"]="$ip"
    fi
done < /etc/hosts

# ── Classify session-only domains ────────────────────────────────────────────
declare -A is_session
for domain in "${!host_ips[@]}"; do
    if [ -z "${feature_for_domain[$domain]+_}" ] && [ -z "${is_persistent[$domain]+_}" ]; then
        is_session["$domain"]=1
    fi
done

# ── JSON porcelain ────────────────────────────────────────────────────────────
# Emit one object per allowlist entry: {value, tier, ips[], feature?}. Session
# IPs/CIDRs come from the change-log, netting out anything later IP_REVOKED so a
# revoked direct-IP grant stops showing. Domain tiers come from /etc/hosts (which
# revoke-domain.sh keeps accurate), so they need no such netting.
if $JSON; then
    {
        for domain in "${!feature_for_domain[@]}"; do
            jq -nc --arg v "$domain" --arg feat "${feature_for_domain[$domain]}" --arg ips "${host_ips[$domain]:-}" \
                '{value:$v, tier:"feature", feature:$feat, ips:(if $ips=="" then [] else ($ips|split(", ")) end)}'
        done
        for domain in "${!is_persistent[@]}"; do
            jq -nc --arg v "$domain" --arg ips "${host_ips[$domain]:-}" \
                '{value:$v, tier:"persistent", ips:(if $ips=="" then [] else ($ips|split(", ")) end)}'
        done
        for domain in "${!is_session[@]}"; do
            jq -nc --arg v "$domain" --arg ips "${host_ips[$domain]:-}" \
                '{value:$v, tier:"session", ips:(if $ips=="" then [] else ($ips|split(", ")) end)}'
        done
        if [ -r "$FIREWALL_LOG" ]; then
            awk '/IP_ADDED|IP_REVOKED/ { last[$NF]=$3 } END { for (ip in last) if (last[ip]=="IP_ADDED") print ip }' "$FIREWALL_LOG" \
            | while IFS= read -r ip; do
                [ -n "$ip" ] || continue
                jq -nc --arg v "$ip" '{value:$v, tier:"session", ips:[$v]}'
            done
        fi
    } | jq -s .
    exit 0
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
print_domain() {
    local domain="$1"
    if [ -n "${host_ips[$domain]+_}" ]; then
        printf "  %-42s ${DIM}%s${NC}\n" "$domain" "${host_ips[$domain]}"
    else
        printf "  %-42s ${DIM}not active${NC}\n" "$domain"
    fi
}

section() {
    local color="$1" label="$2"
    printf "\n${color}${BOLD}%s${NC}\n" "$label"
}

# ── Render ────────────────────────────────────────────────────────────────────
printf "\n${BOLD}Firewall allowlist${NC}\n"
printf '%0.s─' {1..60}; printf '\n'

# Feature domains — grouped by feature, alphabetically sorted within each
declare -A feature_domain_list  # feature → newline-separated domains
for domain in "${!feature_for_domain[@]}"; do
    feat="${feature_for_domain[$domain]}"
    feature_domain_list["$feat"]+="${domain}"$'\n'
done

if [ "${#feature_domain_list[@]}" -gt 0 ]; then
    for feat in $(printf '%s\n' "${!feature_domain_list[@]}" | sort); do
        section "$BLUE" "Feature: $feat"
        while IFS= read -r domain; do
            [ -n "$domain" ] || continue
            print_domain "$domain"
        done < <(printf '%s' "${feature_domain_list[$feat]}" | sort)
    done
fi

# Persistent project domains
if [ "${#is_persistent[@]}" -gt 0 ]; then
    section "$GREEN" "Persistent  (.firewall/allowed-domains.conf)"
    for domain in $(printf '%s\n' "${!is_persistent[@]}" | sort); do
        print_domain "$domain"
    done
fi

# Session-only domains
if [ "${#is_session[@]}" -gt 0 ]; then
    section "$YELLOW" "Session-only  (until next refresh or restart)"
    for domain in $(printf '%s\n' "${!is_session[@]}" | sort); do
        print_domain "$domain"
    done
fi

# Session-only IP/CIDR direct additions from firewall log
if [ -r "$FIREWALL_LOG" ]; then
    ip_entries=$(grep "IP_ADDED" "$FIREWALL_LOG" 2>/dev/null | awk '{print $NF}' | sort -u || true)
    if [ -n "$ip_entries" ]; then
        section "$YELLOW" "Session-only IPs/CIDRs  (until next refresh or restart)"
        while IFS= read -r ip; do
            printf "  %s\n" "$ip"
        done <<< "$ip_entries"
    fi
fi

printf '\n'
