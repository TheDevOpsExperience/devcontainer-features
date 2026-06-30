#!/bin/bash
set -e

source dev-container-features-test-lib

check "op CLI installed" bash -c "command -v op"
check "1password domains registered" test -f /usr/local/share/devcontainer/domains.d/1password.conf

reportResults
