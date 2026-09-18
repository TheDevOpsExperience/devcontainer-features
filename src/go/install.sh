#!/bin/bash
set -eo pipefail
# _REMOTE_USER / _REMOTE_USER_HOME are provided by the devcontainer CLI during feature install.
USERNAME="${USERNAME:-${_REMOTE_USER:-node}}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

GO_VERSION="${GO_VERSION:-latest}"
GOLANGCI_LINT_VERSION="${GOLANGCI_LINT_VERSION:-latest}"
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

# Resolve the release tag of a GitHub repo's latest release from the
# /releases/latest redirect — avoids api.github.com and its 60 req/hr
# unauthenticated rate limit.
latest_github_tag() {
    curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
        | sed 's|.*/tag/||'
}

# Official, unauthenticated, no-rate-limit endpoint for the latest Go release
# (https://go.dev/doc/devel/release#policy) — returns e.g. "go1.26.0".
if [ "$GO_VERSION" = "latest" ]; then
    GO_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -n1)
    [ -n "$GO_VERSION" ] || { echo "ERROR: could not resolve the latest Go version from go.dev." >&2; exit 1; }
else
    GO_VERSION="go${GO_VERSION#go}"
fi

echo "Installing ${GO_VERSION}..."
# Remove any pre-baked toolchain first — untarring over it merges the two trees
# and leaves stale files from the old version behind.
rm -rf /usr/local/go
curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -xz -C /usr/local
export PATH=/usr/local/go/bin:$PATH

# Volume layout — two subdirs so the module/build caches don't clutter the
# GOPATH tree (`~/go` stays a normal-looking GOPATH: pkg/, bin/, src/):
#   gopath/  — GOPATH: module cache (pkg/mod) + `go install`ed binaries (bin/)
#   cache/   — GOCACHE (build/) and GOLANGCI_LINT_CACHE (golangci-lint/), kept
#              alongside but out of gopath/ since they're pure caches, not
#              GOPATH-shaped content
# User-neutral volume mount target, symlinked into the user's home — feature
# mounts can't reference the remote user, so the volume targets
# /dc-volumes/go; Docker seeds a fresh volume with this dir's ownership.
# GOPATH/GOCACHE/GOLANGCI_LINT_CACHE (containerEnv) point at the volume
# directly so the tools use it without relying on the symlink; the symlink
# keeps ~/go working too, same pattern as claude/k8s.
mkdir -p /dc-volumes/go/gopath/bin /dc-volumes/go/cache/build /dc-volumes/go/cache/golangci-lint
if [ -d "${USER_HOME}/go" ] && [ ! -L "${USER_HOME}/go" ]; then
    cp -a "${USER_HOME}/go/." /dc-volumes/go/gopath/
    rm -rf "${USER_HOME}/go"
fi
ln -sfn /dc-volumes/go/gopath "${USER_HOME}/go"
chown -R ${USERNAME}:${USERNAME} /dc-volumes/go
chown -h ${USERNAME}:${USERNAME} "${USER_HOME}/go"

echo "export PATH=/usr/local/go/bin:\$PATH" > /etc/profile.d/go-env.sh
# GOPATH/bin so runtime-`go install`ed binaries run directly. Spelled out
# rather than \$HOME/go/bin: the symlink only exists in the remote user's
# home, so a root/sudo login shell would otherwise lose these.
echo "export PATH=/dc-volumes/go/gopath/bin:\$PATH" >> /etc/profile.d/go-env.sh

# gopls and delve are deliberately NOT installed here. The VS Code Go
# extension (recommended by this feature) installs them on demand, and at
# runtime GOPATH is the volume — so they land in gopath/bin (on PATH above)
# and persist across rebuilds without this feature owning their versions.
# Fetching them needs only proxy.golang.org, which the feature already
# allowlists, so the on-demand install works behind the firewall. Users
# outside VS Code run the same `go install` by hand.
#
# golangci-lint can't work that way, so it stays pinned in the image:
# `go install` is the wrong install path for it (see below), the install
# script's GitHub hosts are intentionally build-time only and not
# allowlisted at runtime, and its version should match CI — lint version
# drift between the container and CI produces false greens.
#
# It goes into the IMAGE (/usr/local/bin), never under /dc-volumes/go.
# install.sh runs at build time, when /dc-volumes/go is still a plain image
# directory — the named volume mounts over it at container create and only
# seeds itself from the image when it's empty. A binary installed under the
# volume path would therefore be shadowed by any pre-existing volume, so
# bumping golangci_lint_version and rebuilding would silently keep the old one.
#
# Installed via their official pinned-download script rather
# than `go install` — upstream recommends against `go install` for it (build
# doesn't stamp version info / plugin replacements correctly). Resolve
# `latest` ourselves first so the script never has to hit api.github.com.
# The script is fetched from HEAD (per upstream's documented install command)
# — the repo's default branch name isn't a stable URL component.
if [ "$GOLANGCI_LINT_VERSION" = "latest" ]; then
    GOLANGCI_LINT_VERSION=$(latest_github_tag golangci/golangci-lint)
    [ -n "$GOLANGCI_LINT_VERSION" ] || { echo "ERROR: could not resolve the latest golangci-lint release." >&2; exit 1; }
else
    GOLANGCI_LINT_VERSION="v${GOLANGCI_LINT_VERSION#v}"
fi
echo "Installing golangci-lint (${GOLANGCI_LINT_VERSION})..."
curl -fsSL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
    | sh -s -- -b /usr/local/bin "${GOLANGCI_LINT_VERSION}"

# Enable the matching oh-my-zsh plugin (completion + aliases for `go`). Core
# merges this into the .zshrc plugins=() array at create time.
mkdir -p /usr/local/share/devcontainer/zsh-plugins.d
printf '%s\n' golang > /usr/local/share/devcontainer/zsh-plugins.d/go.conf

# Domains — module proxy + checksum db, hit by `go get`/`go mod
# download`/`go build`/`go install` at runtime whenever a module isn't
# already cached, by Go 1.21+'s GOTOOLCHAIN auto-download when go.mod
# requires a newer toolchain than what's installed, and by the on-demand
# gopls/delve install described above
# (https://go.dev/ref/mod#module-proxy,
# https://go.dev/ref/mod#authenticating-modules). go.dev and the GitHub
# release hosts above are build-time only (this install script) and
# intentionally omitted.
mkdir -p /usr/local/share/devcontainer/domains.d
cat > /usr/local/share/devcontainer/domains.d/go.conf << 'EOF'
proxy.golang.org
sum.golang.org
EOF
# NOTE: storage.googleapis.com backs the module proxy for some requests but
# also serves countless unrelated buckets — broad, so kept out of the
# always-on allowlist. Allow it per-session with `allow-domain.sh` if module
# downloads fail against it specifically.

echo "${GO_VERSION}, golangci-lint ${GOLANGCI_LINT_VERSION} installed."
