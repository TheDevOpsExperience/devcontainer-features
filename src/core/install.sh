#!/bin/bash
set -e
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _REMOTE_USER / _REMOTE_USER_HOME are provided by the devcontainer CLI during feature install.
USERNAME="${USERNAME:-${_REMOTE_USER:-node}}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

# ── Baseline packages ─────────────────────────────────────────────────────────
# Works on any apt-based image. Each step is a no-op when the package is
# already present (e.g. when the optional cache image is used), so a prepared
# base image keeps installs fast without being required.
if ! command -v apt-get > /dev/null 2>&1; then
    echo "ERROR: The 'core' feature requires an apt-based base image (Debian/Ubuntu)." >&2
    exit 1
fi

apt_get_update() {
    if [ "$(find /var/lib/apt/lists/* -maxdepth 0 2>/dev/null | wc -l)" = "0" ]; then
        apt-get update -y
    fi
}

check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get install -y --no-install-recommends "$@"
    fi
}

# Baseline toolset other features in this collection rely on. Features may
# assume these exist once 'core' is installed.
check_packages \
    curl \
    wget \
    ca-certificates \
    git \
    jq \
    unzip \
    gpg \
    less \
    procps \
    sudo \
    zsh \
    openssh-client

# ── Helper scripts ────────────────────────────────────────────────────────────
# Always installed from the feature (single source of truth). The optional
# cache image does not ship these.
cp "$FEATURE_DIR/scripts/fix-ownership.sh"   /usr/local/bin/fix-ownership.sh
cp "$FEATURE_DIR/scripts/install-package.sh" /usr/local/bin/install-package.sh
cp "$FEATURE_DIR/scripts/fix-volume-ownership.sh" /usr/local/bin/fix-volume-ownership.sh
cp "$FEATURE_DIR/scripts/idle-stop.sh"       /usr/local/bin/idle-stop.sh
chmod +x \
    /usr/local/bin/fix-ownership.sh \
    /usr/local/bin/install-package.sh \
    /usr/local/bin/fix-volume-ownership.sh \
    /usr/local/bin/idle-stop.sh

# ── Lifecycle hooks ───────────────────────────────────────────────────────────
# Each feature contributes its own postCreate/postStart commands via its
# devcontainer-feature.json, pointing at scripts persisted here. They run in
# Feature installation order (every feature installsAfter core), so core's hooks
# run first. Persist outside the feature dir (install scripts aren't guaranteed
# to survive the build) and outside /tmp.
mkdir -p /usr/local/share/devcontainer/core
cp "$FEATURE_DIR/lifecycle/create.sh" /usr/local/share/devcontainer/core/create.sh
cp "$FEATURE_DIR/lifecycle/setup.sh"  /usr/local/share/devcontainer/core/setup.sh
cp "$FEATURE_DIR/lifecycle/attach.sh" /usr/local/share/devcontainer/core/attach.sh
chmod +x /usr/local/share/devcontainer/core/create.sh \
    /usr/local/share/devcontainer/core/setup.sh \
    /usr/local/share/devcontainer/core/attach.sh

# Marker so dependent features can verify core installed before them.
touch /usr/local/share/devcontainer/.core-installed

# ── Sudoers ───────────────────────────────────────────────────────────────────
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/fix-ownership.sh\n%s ALL=(root) NOPASSWD: /usr/local/bin/install-package.sh\n%s ALL=(root) NOPASSWD: /usr/local/bin/fix-volume-ownership.sh\n%s ALL=(root) NOPASSWD: /usr/local/bin/idle-stop.sh\n' \
    "$USERNAME" "$USERNAME" "$USERNAME" "$USERNAME" \
    > /etc/sudoers.d/core-feature
chmod 0440 /etc/sudoers.d/core-feature

# ── Idle-stop option flags ────────────────────────────────────────────────────
# Options are only visible here at install time, not at postStart. Bake them into
# flag files the watchdog + setup.sh read. Default OFF (core is mandatory — don't
# auto-stop every consumer's container unless they opt in).
if [ "${IDLE_STOP:-false}" = "true" ]; then
    touch /usr/local/share/devcontainer/core/idle-stop.enabled
fi
printf '%s\n' "${IDLE_GRACE:-120}" > /usr/local/share/devcontainer/core/idle-grace

# ── Shell setup ───────────────────────────────────────────────────────────────
# Make zsh the user's login shell (containerEnv sets SHELL=/bin/zsh).
usermod -s "$(command -v zsh)" "$USERNAME"

ZSHRC="${USER_HOME}/.zshrc"
BASHRC="${USER_HOME}/.bashrc"

# fzf — required by the Oh My Zsh fzf plugin. Checked by binary, not dpkg,
# because the cache image installs the latest release from GitHub.
if ! command -v fzf > /dev/null 2>&1; then
    apt_get_update
    apt-get install -y --no-install-recommends fzf
fi

# Oh My Zsh (robbyrussell theme, git + fzf plugins). Skipped when the base
# image already provides it. Writes the user's .zshrc, so this must run
# before the wiring blocks below.
if [ ! -d "${USER_HOME}/.oh-my-zsh" ]; then
    # Resolve the tag from the /releases/latest redirect — avoids api.github.com
    # and its 60 req/hr unauthenticated rate limit.
    ZSH_IN_DOCKER_VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/deluan/zsh-in-docker/releases/latest \
        | sed 's|.*/tag/v\{0,1\}||')
    curl -fsSL "https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh" \
        -o /tmp/zsh-in-docker.sh
    HOME="$USER_HOME" sh /tmp/zsh-in-docker.sh \
        -p git \
        -p fzf \
        -t robbyrussell
    rm /tmp/zsh-in-docker.sh
    chown -R ${USERNAME}:${USERNAME} "${USER_HOME}/.oh-my-zsh"
fi

touch "$ZSHRC" "$BASHRC"

# Source /etc/profile.d/*.sh in .zshrc so env vars written by features are
# available in VS Code terminals (VS Code opens a non-login zsh, so profile.d
# is never sourced automatically). Skipped when the base image already wired it.
if ! grep -qs '/etc/profile.d' "$ZSHRC"; then
    echo 'for _f in /etc/profile.d/*.sh(N); do [ -r "$_f" ] && . "$_f"; done; unset _f' >> "$ZSHRC"
fi

# History persistence into the /dc-volumes/commandhistory volume. Skipped when
# the base image already wired it.
if ! grep -qs 'HISTFILE=' "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'
export HISTFILE=/dc-volumes/commandhistory/.zsh_history
export HISTSIZE=50000
export SAVEHIST=50000
EOF
fi
if ! grep -qs 'HISTFILE=' "$BASHRC"; then
    echo "export PROMPT_COMMAND='history -a' && export HISTFILE=/dc-volumes/commandhistory/.bash_history" >> "$BASHRC"
fi

mkdir -p /dc-volumes/commandhistory
touch /dc-volumes/commandhistory/.bash_history \
    /dc-volumes/commandhistory/.zsh_history \
    /dc-volumes/commandhistory/.zsh_profile
chown -R ${USERNAME}:${USERNAME} /dc-volumes/commandhistory
chown ${USERNAME}:${USERNAME} "$ZSHRC" "$BASHRC"

# oh-my-zsh plugin registry. Features drop <feature>.conf here (one plugin
# name per line); core's create.sh merges every .conf into the .zshrc
# plugins=() array at container-create (after all installs have run). The
# user's own list comes from the zsh_plugins option.
mkdir -p /usr/local/share/devcontainer/zsh-plugins.d
if [ -n "${ZSH_PLUGINS:-}" ]; then
    printf '%s\n' ${ZSH_PLUGINS} > /usr/local/share/devcontainer/zsh-plugins.d/user-plugins.conf
fi

# ── Config volume ─────────────────────────────────────────────────────────────
# Config directory — user-neutral volume mount target, symlinked into the
# user's home. Feature mounts can't reference the remote user, so the volume
# targets /dc-volumes/config; Docker seeds a fresh volume with this dir's
# ownership. The symlink keeps ~/.config working for any user.
mkdir -p /dc-volumes/config
if [ -d "${USER_HOME}/.config" ] && [ ! -L "${USER_HOME}/.config" ]; then
    cp -a "${USER_HOME}/.config/." /dc-volumes/config/
    rm -rf "${USER_HOME}/.config"
fi
ln -sfn /dc-volumes/config "${USER_HOME}/.config"
chown -R ${USERNAME}:${USERNAME} /dc-volumes/config
chown -h ${USERNAME}:${USERNAME} "${USER_HOME}/.config"

# Domains
mkdir -p /usr/local/share/devcontainer/domains.d
# Runtime essentials only. Baseline apt packages install at build time (before
# the firewall), so deb.debian.org is here for runtime `install-package.sh`/apt.
# The VS Code hosts are required because the VS Code Server installs *after*
# container start (firewall already active) when attaching. SchemaStore is a
# narrow, dedicated host that powers JSON/YAML editor validation across the many
# config files in a typical sandbox — kept on for day-to-day editing.
cat > /usr/local/share/devcontainer/domains.d/core.conf << 'EOF'
deb.debian.org
www.schemastore.org
json.schemastore.org
marketplace.visualstudio.com
vscode.blob.core.windows.net
update.code.visualstudio.com
EOF

echo "NOTE: 'core' feature ships a host-init script. Add this to .devcontainer/hooks/on-init.sh:" >&2
echo "  source <(curl -fsSL https://raw.githubusercontent.com/TheDevOpsExperience/devcontainer-features/main/src/core/host/on-init.sh)" >&2
echo "" >&2
echo "NOTE: the host-init script writes secrets to .devcontainer/.init/devcontainer.env." >&2
echo "      For Docker to load them, add this runArg to devcontainer.json (read once at create, then core deletes .init/):" >&2
echo '        "runArgs": ["--env-file", ".devcontainer/.init/devcontainer.env"]' >&2
