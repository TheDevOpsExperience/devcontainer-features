#!/bin/bash
set -e

source dev-container-features-test-lib

check "buildctl installed" bash -c "command -v buildctl"
check "docker-build wrapper present" test -x /usr/local/bin/docker-build

reportResults
