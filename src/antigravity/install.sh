#!/bin/bash
set -e
# _REMOTE_USER / _REMOTE_USER_HOME are provided by the devcontainer CLI during feature install.
USERNAME="${USERNAME:-${_REMOTE_USER:-node}}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

# Mutually exclusive with the 'gemini' feature — enable only one. Whichever
# installs second sees the other's marker and fails the build.
if [ -f /usr/local/share/devcontainer/.gemini-installed ]; then
    echo "ERROR: 'antigravity' and 'gemini' are mutually exclusive — enable only one." >&2; exit 1
fi
touch /usr/local/share/devcontainer/.antigravity-installed

# Install the official Antigravity CLI via Google's bootstrapper. It detects the
# platform (linux/darwin, amd64/arm64, musl), downloads the SHA512-verified
# native binary `agy` into $HOME/.local/bin, then runs `agy install`. No Node
# required — it's a native Go binary. This runs at build time (before the
# firewall), so the build-time hosts (antigravity.google, the *.run.app updater,
# storage.googleapis.com for the tarball) don't need allowlisting.
curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/agy-install.sh
su -s /bin/bash "${USERNAME}" -c "HOME='${USER_HOME}' bash /tmp/agy-install.sh"
rm -f /tmp/agy-install.sh

# Config directory — the Antigravity CLI stores its config under
# ~/.gemini/antigravity-cli, i.e. inside ~/.gemini (the Gemini CLI's directory).
# Persist the whole ~/.gemini on a volume so login survives rebuilds. The volume
# is shared with the 'gemini' feature (the two are mutually exclusive, so only
# one ever writes it; sharing means a gemini<->antigravity switch keeps the
# login). Feature mounts can't reference the remote user, so the volume targets
# /dc-volumes/gemini and the home path is symlinked to it.
mkdir -p /dc-volumes/gemini
if [ -d "${USER_HOME}/.gemini" ] && [ ! -L "${USER_HOME}/.gemini" ]; then
    cp -a "${USER_HOME}/.gemini/." /dc-volumes/gemini/
    rm -rf "${USER_HOME}/.gemini"
fi
ln -sfn /dc-volumes/gemini "${USER_HOME}/.gemini"
chown -R ${USERNAME}:${USERNAME} /dc-volumes/gemini
chown -h ${USERNAME}:${USERNAME} "${USER_HOME}/.gemini"

# Put ~/.local/bin on PATH for login shells (VS Code sources /etc/profile.d via
# core's .zshrc wiring).
echo "export PATH=${USER_HOME}/.local/bin:\$PATH" > /etc/profile.d/antigravity-env.sh

# Lifecycle hook (postCreateCommand → devcontainer-feature.json)
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p /usr/local/share/devcontainer/antigravity
cp "$FEATURE_DIR/lifecycle/create.sh" /usr/local/share/devcontainer/antigravity/create.sh
cp "$FEATURE_DIR/lifecycle/setup.sh"  /usr/local/share/devcontainer/antigravity/setup.sh
chmod +x /usr/local/share/devcontainer/antigravity/create.sh \
    /usr/local/share/devcontainer/antigravity/setup.sh

# Devcontainer rule files consumed by create.sh (seeds antigravity's AGENTS.md).
# Namespaced under the feature dir to avoid colliding with other features.
cp "$FEATURE_DIR/config/rules-base.md" /usr/local/share/devcontainer/antigravity/rules-base.md
cp "$FEATURE_DIR/config/rules-firewall.md" /usr/local/share/devcontainer/antigravity/rules-firewall.md

# Bake the skip_permissions option into a flag file so the create-time script can
# read it (feature options are only available during install.sh).
if [ "${SKIP_PERMISSIONS:-false}" = "true" ]; then
    touch /usr/local/share/devcontainer/.antigravity-skip-permissions
else
    rm -f /usr/local/share/devcontainer/.antigravity-skip-permissions
fi

# Domains — runtime only. The CLI self-updates in the background during normal
# runs: it polls the manifest on the Cloud Run updater and pulls new binaries
# from the public GCS bucket. Both are needed at runtime.
mkdir -p /usr/local/share/devcontainer/domains.d
cat > /usr/local/share/devcontainer/domains.d/antigravity.conf << 'EOF'
antigravity-cli-auto-updater-974169037036.us-central1.run.app
storage.googleapis.com
oauth2.googleapis.com
daily-cloudcode-pa.googleapis.com
lh3.googleusercontent.com
EOF
# NOTE: the inference + account-auth endpoints the CLI dials are baked into the
# binary and not yet captured here. On first `agy` run, watch the firewall
# reject log for blocked hosts (likely oauth2.googleapis.com plus a Gemini/Code
# Assist backend) and add them — to this file, or per-session via allow-domain.sh.
