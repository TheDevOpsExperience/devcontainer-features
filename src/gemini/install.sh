#!/bin/bash
set -e
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _REMOTE_USER / _REMOTE_USER_HOME are provided by the devcontainer CLI during feature install.
USERNAME="${USERNAME:-${_REMOTE_USER:-node}}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

# Mutually exclusive with the 'antigravity' feature — enable only one. Whichever
# installs second sees the other's marker and fails the build.
if [ -f /usr/local/share/devcontainer/.antigravity-installed ]; then
    echo "ERROR: 'gemini' and 'antigravity' are mutually exclusive — enable only one." >&2; exit 1
fi
touch /usr/local/share/devcontainer/.gemini-installed

if ! command -v npm > /dev/null 2>&1; then
    echo "ERROR: 'npm' not found. This feature requires Node.js in the base image." >&2
    echo "       Add 'ghcr.io/devcontainers/features/node' to your devcontainer.json features." >&2
    exit 1
fi

npm install -g @google/gemini-cli

# Config directory — user-neutral volume mount target, symlinked into the
# user's home. Feature mounts can't reference the remote user, so the volume
# targets /dc-volumes/gemini; Docker seeds a fresh volume with this dir's
# ownership. The symlink keeps ~/.gemini working for any user.
mkdir -p /dc-volumes/gemini
if [ -d "${USER_HOME}/.gemini" ] && [ ! -L "${USER_HOME}/.gemini" ]; then
    cp -a "${USER_HOME}/.gemini/." /dc-volumes/gemini/
    rm -rf "${USER_HOME}/.gemini"
fi
ln -sfn /dc-volumes/gemini "${USER_HOME}/.gemini"
chown -R ${USERNAME}:${USERNAME} /dc-volumes/gemini
chown -h ${USERNAME}:${USERNAME} "${USER_HOME}/.gemini"

# Lifecycle hook (postCreateCommand → devcontainer-feature.json)
mkdir -p /usr/local/share/devcontainer/gemini
cp "$FEATURE_DIR/lifecycle/create.sh" /usr/local/share/devcontainer/gemini/create.sh
cp "$FEATURE_DIR/lifecycle/setup.sh"  /usr/local/share/devcontainer/gemini/setup.sh
chmod +x /usr/local/share/devcontainer/gemini/create.sh \
    /usr/local/share/devcontainer/gemini/setup.sh

# Devcontainer rule files consumed by create.sh (seeds GEMINI.md). Namespaced
# under the feature dir to avoid colliding with other features' rule files.
cp "$FEATURE_DIR/config/rules-base.md" /usr/local/share/devcontainer/gemini/rules-base.md
cp "$FEATURE_DIR/config/rules-firewall.md" /usr/local/share/devcontainer/gemini/rules-firewall.md

# Bake the yolo option into a flag file so the create-time script can read it
# (feature options are only available during install.sh, not at postCreateCommand time).
if [ "${SKIP_PERMISSIONS:-false}" = "true" ]; then
    touch /usr/local/share/devcontainer/.gemini-skip-permissions
else
    rm -f /usr/local/share/devcontainer/.gemini-skip-permissions
fi

# Domains — runtime only, minimal by default. Omitted (host-browser, not dialed
# by the CLI in-container): accounts.google.com (OAuth consent) and
# aistudio.google.com (AI Studio web UI / API-key page). oauth2.googleapis.com
# (token exchange/refresh) is in-container and stays. Add more per-session with
# allow-domain.sh if a workflow needs them.
mkdir -p /usr/local/share/devcontainer/domains.d
cat > /usr/local/share/devcontainer/domains.d/gemini.conf << 'EOF'
generativelanguage.googleapis.com
oauth2.googleapis.com
EOF
