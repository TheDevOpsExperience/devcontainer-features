#!/bin/bash
set -e

source dev-container-features-test-lib

check "init-firewall.sh present" test -x /usr/local/bin/init-firewall.sh
check "allow-domain.sh present" test -x /usr/local/bin/allow-domain.sh
check "revoke-domain.sh present" test -x /usr/local/bin/revoke-domain.sh
check "list-domains.sh present" test -x /usr/local/bin/list-domains.sh
check "refresh-firewall.sh present" test -x /usr/local/bin/refresh-firewall.sh
check "capture-dns.sh present" test -x /usr/local/bin/capture-dns.sh

# ── revoke-domain.sh + list-domains --json ────────────────────────────────────
check "sudoers grants revoke-domain.sh" \
  bash -c "sudo -n grep -q '/usr/local/bin/revoke-domain.sh' /etc/sudoers.d/firewall"
check "list-domains --json emits a JSON array" \
  bash -c "/usr/local/bin/list-domains.sh --json | jq -e 'type == \"array\"'"
check "revoke-domain.sh with no arg fails" \
  bash -c "! /usr/local/bin/revoke-domain.sh"
check "revoke-domain.sh on unknown domain fails cleanly" \
  bash -c "! /usr/local/bin/revoke-domain.sh nonexistent.example.invalid"

# ── capture-dns logs + list-attempts (v2) ─────────────────────────────────────
check "list-attempts.sh present" test -x /usr/local/bin/list-attempts.sh
check "capture-dns.sh writes session log to /var/log" \
  grep -q "/var/log/firewall-dns.log" /usr/local/bin/capture-dns.sh
check "capture-dns.sh writes audit log to /var/log" \
  grep -q "/var/log/firewall-dns-audit.log" /usr/local/bin/capture-dns.sh
check "list-attempts --json emits a JSON array" \
  bash -c "/usr/local/bin/list-attempts.sh --json | jq -e 'type == \"array\"'"

# ── .firewall/ layout: installed scripts must use the new bucket + marker ──────
check "list-domains.sh uses allowed-domains.conf" \
  grep -q "allowed-domains.conf" /usr/local/bin/list-domains.sh
check "capture-dns.sh uses ignored-domains.conf" \
  grep -q "ignored-domains.conf" /usr/local/bin/capture-dns.sh
check "list-domains.sh reads firewall-dir marker" \
  grep -q "devcontainer/firewall-dir" /usr/local/bin/list-domains.sh
check "capture-dns.sh reads firewall-dir marker" \
  grep -q "devcontainer/firewall-dir" /usr/local/bin/capture-dns.sh
check "capture-dns.sh falls back to .firewall dir" \
  grep -q "/workspace/.devcontainer/.firewall" /usr/local/bin/capture-dns.sh

# ── No stale pre-.firewall names survive in installed scripts ─────────────────
check "no legacy .allowed-domains reference" \
  bash -c '! grep -lq "\.allowed-domains" /usr/local/bin/*.sh'
check "no legacy .ignored-domains reference" \
  bash -c '! grep -lq "\.ignored-domains" /usr/local/bin/*.sh'
check "no legacy devcontainer-dir marker" \
  bash -c '! grep -lq "devcontainer/devcontainer-dir" /usr/local/bin/*.sh'

reportResults
