#!/bin/bash
set -e

source dev-container-features-test-lib

check "firebase CLI installed" bash -c "command -v firebase"
check "java runtime installed" bash -c "command -v java"
check "firebase domains registered" test -f /usr/local/share/devcontainer/domains.d/firebase.conf

reportResults
