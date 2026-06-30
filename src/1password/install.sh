#!/bin/bash
set -e

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

# Install the 1Password CLI (op) from the official apt repository. There is no
# maintained upstream devcontainer feature for it, so this feature installs it
# directly rather than via dependsOn.
curl -sS https://downloads.1password.com/linux/keys/1password.asc \
    | gpg --dearmor \
    > /usr/share/keyrings/1password-archive-keyring.gpg
chmod 644 /usr/share/keyrings/1password-archive-keyring.gpg

ARCH=$(dpkg --print-architecture)
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${ARCH} stable main" \
    > /etc/apt/sources.list.d/1password.list

apt-get update -y && apt-get install -y --no-install-recommends 1password-cli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Domains — runtime only. The op CLI dials the 1Password API to authenticate
# (SA token) and read secrets. The apt repo (downloads.1password.com) is only
# used at build time, before the firewall.
mkdir -p /usr/local/share/devcontainer/domains.d
cat > /usr/local/share/devcontainer/domains.d/1password.conf << 'EOF'
api.1password.com
api.eu.1password.com
api.ca.1password.com
EOF

echo "NOTE: '1password' feature ships a host-init script. Add this to .devcontainer/hooks/on-init.sh:" >&2
echo "  source <(curl -fsSL https://raw.githubusercontent.com/TheDevOpsExperience/devcontainer-features/main/src/1password/host/on-init.sh)" >&2
