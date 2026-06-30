#!/bin/bash
# Usage: sudo fix-volume-ownership.sh [username]
# Defaults to "node" when no argument supplied.
#
# Feature volumes mount under the user-neutral /dc-volumes path and are
# reached via symlinks from the home dir — chown -R on $HOME doesn't traverse
# symlinks, so their ownership is fixed here.
USERNAME="${1:-node}"
if [ -d /dc-volumes ]; then
    chown -R "${USERNAME}:${USERNAME}" /dc-volumes || true
fi
