#!/bin/bash
set -euo pipefail

# install-package.sh — a narrow front door for apt inside the container.
# Usage: sudo install-package.sh <package> [<package> ...]
#
# We hand the sandbox user passwordless sudo for *this* script only, never for
# apt-get directly. The reason: apt-get's `-o` option can set config like
# APT::Update::Pre-Invoke, which runs an arbitrary command as root — so raw
# `sudo apt-get` is effectively `sudo anything`. By accepting bare package names
# and rejecting anything that looks like an option, this wrapper keeps the
# install capability without handing over a root shell.

if [ $# -eq 0 ]; then
    echo "Usage: install-package.sh <package> [<package> ...]"
    exit 1
fi

# Every argument must look like a Debian package name and nothing else.
# Reject leading dashes outright (catches options like -o / --foo).
pkg_name_re='^[a-z0-9][a-z0-9.+-]*$'
for arg in "$@"; do
    if [[ "$arg" == -* ]] || [[ ! "$arg" =~ $pkg_name_re ]]; then
        echo "Error: '$arg' is not a valid package name (no options or special characters allowed)." >&2
        exit 1
    fi
done

apt-get update -qq
apt-get install -y --no-install-recommends "$@"
