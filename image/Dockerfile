# ── Base ──────────────────────────────────────────────────────────────────────
# NODE_VERSION drives the base tag and the published image's node<ver> tags.
# Tools below track latest at build time — for a frozen base, pin the published
# image by digest downstream (tde-base@sha256:…), not the tool versions here.
ARG NODE_VERSION=24
FROM node:${NODE_VERSION}-bookworm-slim

# IMAGE_VERSION is the published image's semantic version. Not used in the build
# — read by build-image.yml to drive the OCI semver tag and the tde-base-v<ver>
# git release tag. Bump on every image change; CI fails if this version was
# already tagged on a different commit.
ARG IMAGE_VERSION=1.0.0

# ── OS packages ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
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
  vim \
  openssh-client \
  nano \
  locales \
  && sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && locale-gen

# ── GitHub CLI ────────────────────────────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | gpg --dearmor > /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh

# ── fzf ──────────────────────────────────────────────────────────────────────
# Latest tag resolved from the /releases/latest redirect — avoids api.github.com
# and its 60 req/hr unauthenticated rate limit.
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
  && FZF_VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/junegunn/fzf/releases/latest \
  | sed 's|.*/tag/v\{0,1\}||') \
  && curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${ARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin \
  && mkdir -p /usr/share/doc/fzf/examples \
  && curl -fsSL "https://raw.githubusercontent.com/junegunn/fzf/v${FZF_VERSION}/shell/key-bindings.zsh" \
  -o /usr/share/doc/fzf/examples/key-bindings.zsh \
  && curl -fsSL "https://raw.githubusercontent.com/junegunn/fzf/v${FZF_VERSION}/shell/completion.zsh" \
  -o /usr/share/doc/fzf/examples/completion.zsh

# ── yq ───────────────────────────────────────────────────────────────────────
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
  && curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" \
  -o /usr/local/bin/yq \
  && chmod +x /usr/local/bin/yq

# NOTE: This image is an optional build-time cache for the features under
# ../src. Everything functional (lifecycle runners, sudoers, shell setup,
# Oh My Zsh, profile.d sourcing, history wiring) is installed by the 'core'
# feature, which works on any apt-based image. This image only pre-bakes the
# slow parts — apt packages, gh, fzf, yq — so the feature installs become
# no-ops or near no-ops.
