#!/bin/bash
set -e

# Runs on every attach (create, start, AND reconnect) — the only in-container
# hook that fires on reconnect. on-init.sh (host) regenerates .devcontainer/.init
# on every open, but postStart only runs on real starts, so a reconnect would
# leave the regenerated .init (secrets) orphaned in the workspace. This cleans it
# unconditionally. Runs after postStart, so setup.sh has already consumed .init.
#
# Workspace path is passed explicitly (postAttachCommand arg) — do not trust $PWD,
# the cwd of feature lifecycle hooks is not guaranteed to be the workspace folder.
WS="$1"
case "$WS" in ''|*'${'*) WS="$PWD";; esac  # fallback if substitution unsupported

rm -rf "$WS/.devcontainer/.init"
