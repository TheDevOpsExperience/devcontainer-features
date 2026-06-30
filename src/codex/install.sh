#!/bin/bash
set -e
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _REMOTE_USER / _REMOTE_USER_HOME are provided by the devcontainer CLI during feature install.
USERNAME="${USERNAME:-${_REMOTE_USER:-node}}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

# The official installer verifies the download against codex-package_SHA256SUMS
# with an awk interval regex (/^[0-9a-fA-F]{64}$/). Debian/Ubuntu's default mawk
# build doesn't support {n} interval expressions, so that match silently fails
# and the install aborts with "Could not find SHA-256 digest ... in
# codex-package_SHA256SUMS". Ensure an interval-capable awk (gawk) is the default.
if ! printf 'x\n' | awk '$0 ~ /^x{1}$/ { ok = 1 } END { exit ok ? 0 : 1 }' 2>/dev/null; then
    apt-get update && apt-get install -y --no-install-recommends gawk \
        && apt-get clean && rm -rf /var/lib/apt/lists/*
    if command -v update-alternatives > /dev/null 2>&1 && [ -x /usr/bin/gawk ]; then
        update-alternatives --set awk /usr/bin/gawk 2>/dev/null \
            || update-alternatives --install /usr/bin/awk awk /usr/bin/gawk 100
    fi
fi

# Install the official Codex CLI via OpenAI's bootstrapper. It detects the
# platform (linux/darwin, x86_64/aarch64-musl), downloads the SHA-256-verified
# native binary into $HOME/.local/bin/codex, and stores the standalone package
# under $HOME/.codex/packages. No Node required — it's a native Rust binary.
# CODEX_NON_INTERACTIVE=1 skips the post-install "Start Codex now?" prompt. This
# runs at build time (before the firewall), so the build-time hosts (chatgpt.com,
# github.com / api.github.com, the release-asset CDN) don't need allowlisting.
curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/codex-install.sh
su -s /bin/bash "${USERNAME}" -c "HOME='${USER_HOME}' CODEX_NON_INTERACTIVE=1 sh /tmp/codex-install.sh"
rm -f /tmp/codex-install.sh

# Config directory — the Codex CLI keeps auth (auth.json), config (config.toml)
# AND the installed standalone binary packages under ~/.codex. Persist the whole
# dir on a volume so login + the installed binary survive rebuilds. Feature
# mounts can't reference the remote user, so the volume targets /dc-volumes/codex
# and the home path is symlinked to it. The ~/.local/bin/codex symlink (created
# by the installer in the image layer) resolves through ~/.codex into the volume.
mkdir -p /dc-volumes/codex
if [ -d "${USER_HOME}/.codex" ] && [ ! -L "${USER_HOME}/.codex" ]; then
    cp -a "${USER_HOME}/.codex/." /dc-volumes/codex/
    rm -rf "${USER_HOME}/.codex"
fi
ln -sfn /dc-volumes/codex "${USER_HOME}/.codex"
chown -R ${USERNAME}:${USERNAME} /dc-volumes/codex
chown -h ${USERNAME}:${USERNAME} "${USER_HOME}/.codex"

# Skills and personal plugin marketplaces the user installs at runtime live under
# ~/.agents (Codex's USER scope: ~/.agents/skills, ~/.agents/plugins/marketplace.json).
# Keep the whole dir on the codex volume via a symlink so they survive rebuilds
# without mounting ~/.agents separately — Codex follows the symlink when scanning.
# Plugin bundles + config.toml already persist under ~/.codex (also on the volume).
mkdir -p /dc-volumes/codex/agents
if [ -d "${USER_HOME}/.agents" ] && [ ! -L "${USER_HOME}/.agents" ]; then
    cp -a "${USER_HOME}/.agents/." /dc-volumes/codex/agents/
    rm -rf "${USER_HOME}/.agents"
fi
ln -sfn /dc-volumes/codex/agents "${USER_HOME}/.agents"
chown -R ${USERNAME}:${USERNAME} /dc-volumes/codex/agents
chown -h ${USERNAME}:${USERNAME} "${USER_HOME}/.agents"

# Put ~/.local/bin on PATH for login shells (VS Code sources /etc/profile.d via
# core's .zshrc wiring). The installer also appends a PATH block to a shell
# profile, but that profile lives in the ephemeral home — this is the durable one.
echo "export PATH=${USER_HOME}/.local/bin:\$PATH" > /etc/profile.d/codex-env.sh

# Lifecycle hook (postCreateCommand → devcontainer-feature.json)
mkdir -p /usr/local/share/devcontainer/codex
cp "$FEATURE_DIR/lifecycle/create.sh" /usr/local/share/devcontainer/codex/create.sh
cp "$FEATURE_DIR/lifecycle/setup.sh"  /usr/local/share/devcontainer/codex/setup.sh
chmod +x /usr/local/share/devcontainer/codex/create.sh \
    /usr/local/share/devcontainer/codex/setup.sh

# Devcontainer rule files consumed by create.sh (merged into AGENTS.md).
# Namespaced under the feature dir to avoid colliding with other features.
cp "$FEATURE_DIR/config/rules-base.md" /usr/local/share/devcontainer/codex/rules-base.md
cp "$FEATURE_DIR/config/rules-firewall.md" /usr/local/share/devcontainer/codex/rules-firewall.md

# Bake the skip_permissions option into a flag file so the create-time script can
# read it (feature options are only available during install.sh, not at
# postCreateCommand time).
if [ "${SKIP_PERMISSIONS:-false}" = "true" ]; then
    touch /usr/local/share/devcontainer/.codex-skip-permissions
else
    rm -f /usr/local/share/devcontainer/.codex-skip-permissions
fi

# Domains — runtime only. The CLI dials api.openai.com (Responses API, used by
# API-key auth) and chatgpt.com (the backend-api used by ChatGPT-account auth);
# auth.openai.com handles the in-container token refresh. The OAuth *consent*
# page is opened in the host browser, so it doesn't need allowlisting here. Add
# more per-session with allow-domain.sh if a workflow needs them.
mkdir -p /usr/local/share/devcontainer/domains.d
cat > /usr/local/share/devcontainer/domains.d/codex.conf << 'EOF'
api.openai.com
chatgpt.com
auth.openai.com
EOF
# NOTE: installing skills or plugins at runtime (e.g. $skill-installer, or
# `codex plugin marketplace add owner/repo`) clones from GitHub — allow per-session:
#   sudo allow-domain.sh github.com codeload.github.com
# Anything installed lands under ~/.codex or ~/.agents (both on the volume) and
# survives rebuilds.
