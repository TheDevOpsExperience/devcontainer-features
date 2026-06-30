#!/bin/bash
set -e

source dev-container-features-test-lib

# Scenario: core installed with idle_stop=true, idle_grace=45.
check "idle-stop enabled flag present" \
  test -f /usr/local/share/devcontainer/core/idle-stop.enabled
check "idle-grace honours the option (45)" \
  bash -c "grep -qx 45 /usr/local/share/devcontainer/core/idle-grace"

reportResults
