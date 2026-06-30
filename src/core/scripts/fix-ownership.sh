#!/bin/bash
# Usage: sudo fix-ownership.sh [username]
# Defaults to "node" when no argument supplied.
USERNAME="${1:-node}"
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}" || true
