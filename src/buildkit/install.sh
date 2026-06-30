#!/bin/bash
set -e
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="${USERNAME:-node}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

BUILDKIT_VERSION="${VERSION:-latest}"
if [ "$BUILDKIT_VERSION" = "latest" ]; then
    # Resolve the tag from the /releases/latest redirect — avoids api.github.com
    # and its 60 req/hr unauthenticated rate limit.
    BUILDKIT_VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/moby/buildkit/releases/latest \
        | sed 's|.*/tag/||')
fi
BUILDKIT_VERSION="v${BUILDKIT_VERSION#v}"
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
# Only the client is needed — buildkitd runs on the host in a separate
# container (started by host/on-init.sh). Extract buildctl alone instead of
# the full toolchain (buildkitd, buildkit-runc, ...).
curl -fsSL "https://github.com/moby/buildkit/releases/download/${BUILDKIT_VERSION}/buildkit-${BUILDKIT_VERSION}.linux-${ARCH}.tar.gz" \
    | tar -xz -C /usr/local bin/buildctl

# Install docker-build / docker-push as standalone executables (available on PATH, no .zshrc sourcing needed)
cp "$FEATURE_DIR/scripts/docker-build.sh" /usr/local/bin/docker-build
cp "$FEATURE_DIR/scripts/docker-push.sh" /usr/local/bin/docker-push
chmod +x /usr/local/bin/docker-build /usr/local/bin/docker-push

# Set BUILDKIT_HOST from feature options
echo "export BUILDKIT_HOST=tcp://${DAEMON_HOST}:${DAEMON_PORT}" > /etc/profile.d/buildkit-env.sh

# Domains
mkdir -p /usr/local/share/devcontainer/domains.d
# Registered always-on:
#   - ${DAEMON_HOST}: the universal client->buildkitd connection.
#   - Docker Hub auth + registry API (auth.docker.io, registry-1.docker.io): the
#     client performs the registry auth handshake and base-image manifest
#     resolution from THIS container, so they pass through the firewall. Docker
#     Hub is the implicit default registry for unqualified `FROM` images
#     (node, ubuntu, ...), so this is the one registry worth a sane default.
#     The layer blobs are pulled by the buildkitd sidecar (not firewalled), so
#     the blob CDN (production.cloudflare.docker.com) is intentionally omitted.
# NOT registered (consumer-specific): other registries depend on the project —
# GHCR (ghcr.io, pkg-containers.githubusercontent.com), GitLab, ECR, ... Add
# yours via .devcontainer/.firewall/allowed-domains.conf or your own domains.d file. Pushing to
# a registry also needs its auth host allowlisted here. See the feature README.
cat > /usr/local/share/devcontainer/domains.d/buildkit.conf << EOF
${DAEMON_HOST}
auth.docker.io
registry-1.docker.io
EOF

echo "NOTE: 'buildkit' feature ships a host-init script. Add this to .devcontainer/hooks/on-init.sh:" >&2
echo "  curl -fsSL https://raw.githubusercontent.com/TheDevOpsExperience/devcontainer-features/main/src/buildkit/host/on-init.sh | bash" >&2
