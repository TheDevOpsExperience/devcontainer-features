#!/bin/bash
set -e
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="${USERNAME:-node}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

KUBECTL_VERSION="${KUBECTL_VERSION:-latest}"
HELM_VERSION="${HELM_VERSION:-latest}"
KUBECTX_VERSION="${KUBECTX_VERSION:-latest}"

ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

# Resolve the release tag of a GitHub repo's latest release from the
# /releases/latest redirect — avoids api.github.com and its 60 req/hr
# unauthenticated rate limit.
latest_github_tag() {
    curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
        | sed 's|.*/tag/||'
}

# kubectl
echo "Installing kubectl..."
if [ "$KUBECTL_VERSION" = "latest" ]; then
    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
fi
KUBECTL_VERSION="v${KUBECTL_VERSION#v}"
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# helm
echo "Installing helm..."
if [ "$HELM_VERSION" = "latest" ]; then
    HELM_VERSION=$(curl -fsSL https://get.helm.sh/helm-latest-version)
fi
HELM_VERSION="v${HELM_VERSION#v}"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 "linux-${ARCH}/helm"

# kubectx + kubens
echo "Installing kubectx and kubens..."
if [ "$KUBECTX_VERSION" = "latest" ]; then
    KUBECTX_VERSION=$(latest_github_tag ahmetb/kubectx)
fi
KUBECTX_VERSION="v${KUBECTX_VERSION#v}"
# kubectx assets use x86_64/arm64 (GoReleaser), not amd64
KUBECTX_ARCH=$(uname -m | sed 's/aarch64/arm64/')
curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_${KUBECTX_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin kubectx
curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens_${KUBECTX_VERSION}_linux_${KUBECTX_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin kubens

echo "kubectl ${KUBECTL_VERSION}, helm ${HELM_VERSION}, kubectx/kubens ${KUBECTX_VERSION} installed."
