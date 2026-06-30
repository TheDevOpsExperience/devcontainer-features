#!/bin/bash
# fetch-op-token.sh — reads a service account token from 1Password and appends
# it to devcontainer.env as OP_SERVICE_ACCOUNT_TOKEN. Runs on the HOST (called
# from on-init.sh).
#
# Required env vars:
#   INIT_CONFIG_DIR - path to the .init directory
#   OP_ACCOUNT      - 1Password account shorthand (see 'op account list')
#   OP_SA_ITEM_PATH - op:// path to the service account token
set -e

OP_SERVICE_ACCOUNT_TOKEN="$(op read "$OP_SA_ITEM_PATH" --account "$OP_ACCOUNT" 2>/dev/null || true)"
if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
  # Skip the append so the container gets an unset var, not an empty string.
  echo "Warning: 1Password SA token not found at $OP_SA_ITEM_PATH (account: $OP_ACCOUNT); not writing OP_SERVICE_ACCOUNT_TOKEN" >&2
else
  echo "OP_SERVICE_ACCOUNT_TOKEN=${OP_SERVICE_ACCOUNT_TOKEN}" >> "${INIT_CONFIG_DIR}/devcontainer.env"
fi
