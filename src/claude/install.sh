#!/bin/bash
set -e
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _REMOTE_USER / _REMOTE_USER_HOME are provided by the devcontainer CLI during feature install.
USERNAME="${USERNAME:-${_REMOTE_USER:-node}}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

# Config defaults consumed by the lifecycle scripts (CLAUDE.md, statusline.sh, settings.json)
cp -r "$FEATURE_DIR/config/." /usr/local/share/devcontainer/

# Lifecycle hooks (postCreate/postStart → devcontainer-feature.json)
mkdir -p /usr/local/share/devcontainer/claude
cp "$FEATURE_DIR/lifecycle/create.sh" /usr/local/share/devcontainer/claude/create.sh
cp "$FEATURE_DIR/lifecycle/setup.sh"  /usr/local/share/devcontainer/claude/setup.sh
chmod +x /usr/local/share/devcontainer/claude/create.sh \
    /usr/local/share/devcontainer/claude/setup.sh

# Bake feature options into flag files so the create-time script can read them
# (feature options are only available during install.sh, not at postCreateCommand time).
if [ "${SKIP_PERMISSIONS:-false}" = "true" ]; then
    touch /usr/local/share/devcontainer/.claude-skip-permissions
else
    rm -f /usr/local/share/devcontainer/.claude-skip-permissions
fi

# Domains — per the official Claude Code network requirements
# (https://code.claude.com/docs/en/network-config). Optional telemetry hosts
# (Statsig/Sentry) are intentionally omitted: not required, and disable-able.
mkdir -p /usr/local/share/devcontainer/domains.d
cat > /usr/local/share/devcontainer/domains.d/claude.conf << 'EOF'
api.anthropic.com
claude.ai
platform.claude.com
downloads.claude.ai
EOF
# NOTE: non-essential / broad hosts (serving every repo or bucket) are kept out
# of the always-on allowlist. Allow them per-session with `allow-domain.sh` when
# needed:
#   - raw.githubusercontent.com → release-notes/changelog feed
#   - github.com / codeload.github.com / raw.githubusercontent.com → installing
#     plugins from a GitHub marketplace at runtime (plugins land in ~/.claude,
#     on the volume, so they persist across rebuilds)
#   - storage.googleapis.com → native auto-updater on CLI versions < 2.1.116
#     (recent installs update via downloads.claude.ai instead)

# Config directory — user-neutral volume mount target, symlinked into the
# user's home. Feature mounts can't reference the remote user, so the volume
# targets /dc-volumes/claude; Docker seeds a fresh volume with this dir's
# ownership. CLAUDE_CONFIG_DIR (containerEnv) points at it directly; the
# symlink keeps ~/.claude working for everything else.
mkdir -p /dc-volumes/claude
if [ -d "${USER_HOME}/.claude" ] && [ ! -L "${USER_HOME}/.claude" ]; then
    cp -a "${USER_HOME}/.claude/." /dc-volumes/claude/
    rm -rf "${USER_HOME}/.claude"
fi
ln -sfn /dc-volumes/claude "${USER_HOME}/.claude"
chown -R ${USERNAME}:${USERNAME} /dc-volumes/claude
chown -h ${USERNAME}:${USERNAME} "${USER_HOME}/.claude"

# User-level: install Claude Code CLI (runs as the remote user)
curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
su -s /bin/bash "${USERNAME}" << 'EOF'
bash /tmp/claude-install.sh
EOF
rm /tmp/claude-install.sh

echo "export PATH=${USER_HOME}/.local/bin:\$PATH" > /etc/profile.d/claude-env.sh
