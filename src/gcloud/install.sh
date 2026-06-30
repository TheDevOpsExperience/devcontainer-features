#!/bin/bash
set -e

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

# Install the gcloud CLI from Google's apt repository using the modern signed-by
# keyring method. (The community dhoeric feature uses the removed `apt-key` and
# breaks on modern Ubuntu/Debian, so this feature installs directly.)
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor > /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-cli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Domains — runtime control-plane only. The apt repo (packages.cloud.google.com)
# is build-time, before the firewall. The OAuth consent page is host-browser.
mkdir -p /usr/local/share/devcontainer/domains.d
cat > /usr/local/share/devcontainer/domains.d/gcloud.conf << 'EOF'
oauth2.googleapis.com
www.googleapis.com
cloudresourcemanager.googleapis.com
storage.googleapis.com
EOF
# NOTE: per-service APIs (e.g. run.googleapis.com, compute.googleapis.com,
# artifactregistry.googleapis.com) are NOT included — add the ones your project
# uses, since gcloud spans every Google Cloud API.
