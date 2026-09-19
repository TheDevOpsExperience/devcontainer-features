#!/bin/bash
set -e
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _REMOTE_USER is provided by the devcontainer CLI during feature install.
USERNAME="${USERNAME:-${_REMOTE_USER:-node}}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    tcpdump \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

cp "$FEATURE_DIR/scripts/firewall-lib.sh" /usr/local/bin/firewall-lib.sh
cp "$FEATURE_DIR/scripts/init-firewall.sh" /usr/local/bin/init-firewall.sh
cp "$FEATURE_DIR/scripts/refresh-firewall.sh" /usr/local/bin/refresh-firewall.sh
cp "$FEATURE_DIR/scripts/allow-domain.sh" /usr/local/bin/allow-domain.sh
cp "$FEATURE_DIR/scripts/revoke-domain.sh" /usr/local/bin/revoke-domain.sh
cp "$FEATURE_DIR/scripts/list-domains.sh" /usr/local/bin/list-domains.sh
cp "$FEATURE_DIR/scripts/list-attempts.sh" /usr/local/bin/list-attempts.sh
chmod +x \
    /usr/local/bin/firewall-lib.sh \
    /usr/local/bin/init-firewall.sh \
    /usr/local/bin/refresh-firewall.sh \
    /usr/local/bin/allow-domain.sh \
    /usr/local/bin/revoke-domain.sh \
    /usr/local/bin/list-domains.sh \
    /usr/local/bin/list-attempts.sh

cp "$FEATURE_DIR/scripts/capture-dns.sh" /usr/local/bin/capture-dns.sh
chmod +x /usr/local/bin/capture-dns.sh

# Lifecycle hook (postStartCommand → devcontainer-feature.json)
mkdir -p /usr/local/share/devcontainer/firewall
cp "$FEATURE_DIR/lifecycle/setup.sh" /usr/local/share/devcontainer/firewall/setup.sh
chmod +x /usr/local/share/devcontainer/firewall/setup.sh

# ── Firewall Monitor VS Code extension (optional) ─────────────────────────────
# The .vsix is built in CI and bundled INSIDE this feature's OCI artifact
# (release workflow drops it into extension/ before publish). We just copy it
# here for setup.sh to `code --install-extension`. The extension is 1:1 coupled
# to the feature — no standalone release/version to keep in sync, and the OCI
# pull already integrity-checks the artifact (no separate checksum needed).
# Any failure is non-fatal: the extension is convenience, not a hard dependency.
# Locally (devcontainer features test) no .vsix is bundled → gracefully skipped.
VSIX_DEST="/usr/local/share/devcontainer/firewall/firewall-monitor.vsix"
if [ "${INSTALL_EXTENSION:-true}" = "true" ]; then
    touch /usr/local/share/devcontainer/firewall/install-extension.enabled
    VSIX_SRC="$(ls "$FEATURE_DIR"/extension/*.vsix 2>/dev/null | head -1 || true)"
    if [ -n "$VSIX_SRC" ]; then
        cp "$VSIX_SRC" "$VSIX_DEST"
    else
        echo "WARNING: no bundled firewall-monitor .vsix — extension will be skipped" >&2
    fi
fi

# ── Enforcement toggle ─────────────────────────────────────────────────────────
# Option only visible here at install time, not at postStart. Bake into a flag
# file setup.sh reads to decide whether to run init-firewall.sh (lockdown) at
# all. DNS capture always runs regardless — see setup.sh.
if [ "${ENABLED:-true}" = "true" ]; then
    touch /usr/local/share/devcontainer/firewall/enabled
fi

# Sudoers
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh\n%s ALL=(root) NOPASSWD: /usr/local/bin/refresh-firewall.sh\n%s ALL=(root) NOPASSWD: /usr/local/bin/allow-domain.sh\n%s ALL=(root) NOPASSWD: /usr/local/bin/revoke-domain.sh\n%s ALL=(root) NOPASSWD: /usr/local/bin/capture-dns.sh\n' \
    "$USERNAME" "$USERNAME" "$USERNAME" "$USERNAME" "$USERNAME" \
    > /etc/sudoers.d/firewall
chmod 0440 /etc/sudoers.d/firewall
