#!/bin/bash
set -e

source dev-container-features-test-lib

# Version options must actually take effect. Worth its own scenario: the
# default scenario would still pass if the pins were ignored.
check "go version pinned" bash -c "go version | grep -q 'go1\.26\.5 '"
check "golangci-lint version pinned" bash -c "golangci-lint --version | grep -q '2\.12\.2'"

reportResults
