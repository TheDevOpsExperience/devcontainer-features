#!/bin/bash
set -e

source dev-container-features-test-lib

check "gcloud CLI installed" bash -c "command -v gcloud"
check "gcloud domains registered" test -f /usr/local/share/devcontainer/domains.d/gcloud.conf

reportResults
