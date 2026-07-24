#!/bin/bash
set -e
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _REMOTE_USER / _REMOTE_USER_HOME are provided by the devcontainer CLI during feature install.
USERNAME="${USERNAME:-${_REMOTE_USER:-node}}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

KUBECTL_VERSION="${KUBECTL_VERSION:-latest}"
HELM_VERSION="${HELM_VERSION:-latest}"
KUBECTX_VERSION="${KUBECTX_VERSION:-latest}"

ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

# Resolve the release tag of a GitHub repo's latest release from the
# /releases/latest redirect — avoids api.github.com and its 60 req/hr
# unauthenticated rate limit.
latest_github_tag() {
    curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
        | sed 's|.*/tag/||'
}

# kubectl
echo "Installing kubectl..."
if [ "$KUBECTL_VERSION" = "latest" ]; then
    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
fi
KUBECTL_VERSION="v${KUBECTL_VERSION#v}"
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# helm
echo "Installing helm..."
if [ "$HELM_VERSION" = "latest" ]; then
    HELM_VERSION=$(curl -fsSL https://get.helm.sh/helm-latest-version)
fi
HELM_VERSION="v${HELM_VERSION#v}"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 "linux-${ARCH}/helm"

# kubectx + kubens
echo "Installing kubectx and kubens..."
if [ "$KUBECTX_VERSION" = "latest" ]; then
    KUBECTX_VERSION=$(latest_github_tag ahmetb/kubectx)
fi
KUBECTX_VERSION="v${KUBECTX_VERSION#v}"
# kubectx assets use x86_64/arm64 (GoReleaser), not amd64
KUBECTX_ARCH=$(uname -m | sed 's/aarch64/arm64/')
curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_${KUBECTX_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin kubectx
curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens_${KUBECTX_VERSION}_linux_${KUBECTX_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin kubens

echo "kubectl ${KUBECTL_VERSION}, helm ${HELM_VERSION}, kubectx/kubens ${KUBECTX_VERSION} installed."

# Config directory — user-neutral volume mount target, symlinked into the
# user's home. Feature mounts can't reference the remote user, so the volume
# targets /dc-volumes/kube; Docker seeds a fresh volume with this dir's
# ownership. The symlink keeps ~/.kube working for any user, and kubectl's
# default config path ($HOME/.kube/config) resolves through it — no env var
# needed. Persists kubeconfig (contexts, kubectx_mapping-relevant names) across
# rebuilds.
mkdir -p /dc-volumes/kube
if [ -d "${USER_HOME}/.kube" ] && [ ! -L "${USER_HOME}/.kube" ]; then
    cp -a "${USER_HOME}/.kube/." /dc-volumes/kube/
    rm -rf "${USER_HOME}/.kube"
fi
ln -sfn /dc-volumes/kube "${USER_HOME}/.kube"
chown -R ${USERNAME}:${USERNAME} /dc-volumes/kube
chown -h ${USERNAME}:${USERNAME} "${USER_HOME}/.kube"

# Enable the matching oh-my-zsh plugins. Core merges this into the .zshrc
# plugins=() array at create time; no core config needed.
#   kubectl/helm — aliases + completion.
#   kubectx      — provides kubectx_prompt_info() for the prompt segment below.
mkdir -p /usr/local/share/devcontainer/zsh-plugins.d
printf '%s\n' kubectl helm kubectx > /usr/local/share/devcontainer/zsh-plugins.d/k8s.conf

# Show the active kube-context on the left prompt (PROMPT), via core's
# zshrc.d drop-in (sourced after the theme, so the kubectx plugin's
# kubectx_prompt_info is already defined, and appending here composes with
# whatever the theme already set, e.g. robbyrussell's own git segment).
# Opt out with K8S_HIDE_CONTEXT=1, or set your own PROMPT in
# .devcontainer/zshrc.d/.overrides.zsh (sourced last) to override entirely.
mkdir -p /usr/local/share/devcontainer/zshrc.d
cat > /usr/local/share/devcontainer/zshrc.d/kube-context.zsh << 'EOF'
# kube_context_prompt — reusable prompt segment. Echoes " ⎈ <context>:<namespace>"
# (namespace omitted if unset), or nothing when there's no context / no kubectl /
# K8S_HIDE_CONTEXT is set. Safe in PROMPT_SUBST. Public: call it from your own
# PROMPT/RPROMPT in .devcontainer/zshrc.d/.overrides.zsh to reuse this piece.
kube_context_prompt() {
  [[ -n "$K8S_HIDE_CONTEXT" ]] && return
  (( $+functions[kubectx_prompt_info] )) || return
  local ctx; ctx=$(kubectx_prompt_info) || return   # context (honors kubectx_mapping)
  [[ -n "$ctx" ]] || return
  # kubectl is present (kubectx_prompt_info already checked); append namespace.
  local ns; ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)
  echo " ⎈ ${ctx}${ns:+:$ns}"
}
PROMPT+='$(kube_context_prompt)'

# ktx/kns — short aliases for kubectx/kubens, with tab-completion for
# context/namespace names. Upstream ships real completion (ahmetb/kubectx
# completion/_kubectx.zsh, _kubens.zsh) but only as fpath-autoload files —
# not in the release tarball we install from (.goreleaser.yml: binary +
# LICENSE only), and not a binary subcommand either. Their delivery method
# (drop in $fpath, let compinit's startup scan discover the #compdef header)
# doesn't fit here: compinit already ran earlier in oh-my-zsh init, before
# this drop-in loads, so a file landing in fpath this late wouldn't be
# autoloaded without re-running compinit. Transcribed logic below, registered
# via an explicit compdef instead — same escape hatch oh-my-zsh's own plugins
# use for exactly this timing problem.
alias ktx=kubectx
alias kns=kubens

_ktx() {
  local -a context_array
  context_array=(${(f)"$(kubectl config get-contexts --output=name 2>/dev/null)"})
  local -a all_contexts
  all_contexts=(${(q)context_array})
  if [[ -f "${HOME}/.kube/kubectx" ]]; then
    # A previous context is saved — offer '-' to switch back to it.
    _arguments \
      "-d:*: :(${all_contexts})" \
      "(- *): :(- ${all_contexts})"
  else
    _arguments \
      "-d:*: :(${all_contexts})" \
      "(- *): :(${all_contexts})"
  fi
}
compdef _ktx kubectx
compdef _ktx ktx

_kns() {
  _arguments "1: :(- $(kubectl get namespaces -o=jsonpath='{range .items[*].metadata.name}{@}{"\n"}{end}' 2>/dev/null))"
}
compdef _kns kubens
compdef _kns kns
EOF
