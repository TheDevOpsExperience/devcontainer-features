#!/bin/bash
# list-attempts.sh [--json] — DNS lookups the sandboxed user attempted (captured
# by capture-dns.sh), deduplicated with attempt count + last-seen (from the
# session log) and first-seen (from the audit log). This is the "undecided
# denied" inbox: a domain leaves the list once it's resolved either way —
# allowed (now in the live allowlist; resolves via /etc/hosts, no more DNS) or
# ignored (muted via .firewall/ignored-domains.conf). Each resolved domain has a
# home elsewhere (Allowlist / Ignored views), so it's dropped here. No sudo.

set -eo pipefail

JSON=false
for a in "$@"; do [ "$a" = "--json" ] && JSON=true; done

SESSION="/var/log/firewall-dns.log"
AUDIT="/var/log/firewall-dns-audit.log"
FIREWALL_DIR="$(cat /usr/local/share/devcontainer/firewall-dir 2>/dev/null || echo /workspace/.devcontainer/.firewall)"
IGNORED_FILE="${FIREWALL_DIR}/ignored-domains.conf"

# Live allowlist values → drop attempts that are currently allowed.
declare -A allowed
if [ -x /usr/local/bin/list-domains.sh ]; then
    while IFS= read -r d; do
        [ -n "$d" ] && allowed["$d"]=1
    done < <(/usr/local/bin/list-domains.sh --json 2>/dev/null | jq -r '.[].value' 2>/dev/null)
fi

# Ignore-list patterns (exact + "*.suffix" wildcard) → drop muted attempts.
# Matches capture-dns.sh's is_ignored so the inbox mirrors what gets captured.
is_ignored() {
    local domain="$1" pattern
    [[ -f "$IGNORED_FILE" ]] || return 1
    while IFS= read -r pattern; do
        [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
        pattern="${pattern%%#*}"            # strip inline comments
        pattern="${pattern//[[:space:]]/}"  # strip whitespace
        [[ -z "$pattern" ]] && continue
        if [[ "$pattern" == \*.* ]]; then
            [[ "$domain" == *."${pattern#\*.}" ]] && return 0
        else
            [[ "$domain" == "$pattern" ]] && return 0
        fi
    done < "$IGNORED_FILE"
    return 1
}

declare -A count last first
if [ -r "$SESSION" ]; then
    while read -r date time dom _; do
        [[ -z "$dom" || "$date" == \#* ]] && continue
        count["$dom"]=$(( ${count["$dom"]:-0} + 1 ))
        last["$dom"]="$date $time"
    done < "$SESSION"
fi
if [ -r "$AUDIT" ]; then
    while read -r date time _tag dom _; do
        [ -n "$dom" ] && first["$dom"]="$date $time"
    done < "$AUDIT"
fi

# `grep .` drops blank lines; `|| true` so an empty result doesn't trip set -e.
domains="$(printf '%s\n' "${!count[@]}" "${!first[@]}" | sort -u | grep . || true)"

if $JSON; then
    {
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            [ -n "${allowed[$d]:-}" ] && continue   # resolved: allowed
            is_ignored "$d" && continue             # resolved: ignored
            jq -nc \
                --arg d "$d" \
                --argjson c "${count[$d]:-0}" \
                --arg last "${last[$d]:-}" \
                --arg first "${first[$d]:-}" \
                '{domain:$d, count:$c, last_seen:$last, first_seen:$first}'
        done <<< "$domains"
    } | jq -s 'sort_by(-.count)'
    exit 0
fi

printf '%-40s %6s  %s\n' "DOMAIN" "COUNT" "LAST SEEN"
while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -n "${allowed[$d]:-}" ] && continue
    is_ignored "$d" && continue
    printf '%-40s %6s  %s\n' "$d" "${count[$d]:-0}" "${last[$d]:-—}"
done <<< "$domains"
