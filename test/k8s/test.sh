#!/bin/bash
set -e

source dev-container-features-test-lib

check "kubectl installed" bash -c "command -v kubectl"
check "helm installed" bash -c "command -v helm"
check "kubectx installed" bash -c "command -v kubectx"
check "kubens installed" bash -c "command -v kubens"

reportResults
