#!/bin/bash
set -e

source dev-container-features-test-lib

check "go installed" bash -c "command -v go"
check "gofmt installed" bash -c "command -v gofmt"
check "golangci-lint installed" bash -c "command -v golangci-lint"

# gopls/delve are NOT installed by the feature — the VS Code Go extension
# installs them on demand into gopath/bin, which is on the volume and so
# persists across rebuilds. Baking them into the image would just pin
# versions the editor already manages. See src/go/install.sh.
check "gopls not preinstalled" bash -c "! command -v gopls"
check "dlv not preinstalled" bash -c "! command -v dlv"
check "GOPATH set" bash -c "[ \"\$(go env GOPATH)\" = \"/dc-volumes/go/gopath\" ]"
check "GOCACHE set" bash -c "[ \"\$(go env GOCACHE)\" = \"/dc-volumes/go/cache/build\" ]"
check "GOLANGCI_LINT_CACHE set" bash -c "[ \"\$GOLANGCI_LINT_CACHE\" = \"/dc-volumes/go/cache/golangci-lint\" ]"
check "go home symlink" bash -c "[ -L \$HOME/go ]"

# The feature's own tools must live in the image, not under /dc-volumes/go —
# the volume shadows that path once it exists, so a binary installed there
# can't be updated by a rebuild. See src/go/install.sh.
check "go toolchain in image, not volume" bash -c "[ \"\$(command -v go)\" = /usr/local/go/bin/go ]"
check "golangci-lint in image, not volume" bash -c "[ \"\$(command -v golangci-lint)\" = /usr/local/bin/golangci-lint ]"

# GOPATH/bin on PATH for runtime `go install`s, for any user (not via ~/go)
check "gopath bin on PATH" bash -c "echo \$PATH | grep -q /dc-volumes/go/gopath/bin"
check "gopath bin on PATH for root" bash -c "sudo -i sh -c 'echo \$PATH' | grep -q /dc-volumes/go/gopath/bin"

check "golang zsh plugin registered" bash -c "grep -qx golang /usr/local/share/devcontainer/zsh-plugins.d/go.conf"
check "firewall domains registered" bash -c "grep -qx proxy.golang.org /usr/local/share/devcontainer/domains.d/go.conf"

reportResults
