## Prerequisites

Requires the `core` feature.

## Tools installed

| Tool | Version option | Default |
|------|----------------|---------|
| `kubectl` | `kubectl_version` | latest stable |
| `helm` | `helm_version` | latest stable |
| `kubectx` / `kubens` | `kubectx_version` | latest stable |

Pin versions for reproducible builds (without `v` prefix):

```json
"features": {
  "./features/k8s": {
    "kubectl_version": "1.31.4",
    "helm_version": "3.16.2"
  }
}
```

`latest` is resolved without `api.github.com` (no unauthenticated rate-limit issues). Both `amd64` and `arm64` are supported.

## Kubeconfig persistence

`~/.kube` is symlinked to the `kube-${localWorkspaceFolderBasename}` volume (mounted at `/dc-volumes/kube`), same pattern as the `claude`/`gemini`/`codex` features — contexts, clusters, and users in `~/.kube/config` survive container rebuilds instead of needing `kubectl config set-cluster`/`set-credentials` redone each time. An existing `~/.kube` from the base image is copied in on first install, then replaced with the symlink.

## Shell integration

Enables the `kubectl`, `helm`, and `kubectx` oh-my-zsh plugins via core's plugin registry — no config needed. `kubectl`/`helm` give aliases + completion; `kubectx` provides `kubectx_prompt_info` for the prompt. See core's `zsh_plugins` option to add your own on top.

Also adds `ktx`/`kns` aliases for `kubectx`/`kubens`, with tab-completion for context/namespace names (queried live from `kubectl` — the `kubectx`/`kubens` binaries don't ship their own completion).

Also shows the **active kube-context and namespace on the left prompt** (`PROMPT`, as a robbyrussell-style bracketed segment `k8s:(context:namespace)`, color-matched to the theme's own git segment — blue label, magenta context, white separator), via core's `zshrc.d` drop-in — context from `kubectx_prompt_info` when the plugin's loaded (honors `kubectx_mapping`), else a raw `kubectl config current-context` fallback; namespace from `kubectl config view --minify` — omitted (just `k8s:(context)`) when no namespace is selected. Same as the theme's own git segment: shows nothing when there's no active context, rather than an empty/placeholder segment. It's prepended ahead of whatever the theme already set (first in the prompt chain, e.g. before robbyrussell's own arrow + cwd + git segments), deliberately on the left since it's high-consequence (which cluster you're pointed at) and easy to miss on the right edge of a narrow terminal. Set short context names with `kubectx_mapping[long-context-name]=short`. Silence it with `export K8S_HIDE_CONTEXT=1` (e.g. in `.devcontainer/zshrc.d/.overrides.zsh`), or set your own prompt there to override — e.g. drop your host `PROMPT`/`RPROMPT` in verbatim, since `.overrides.zsh` is sourced last.

**Reusing the segment in a custom prompt.** The segment is a public shell function, `kube_context_prompt`, that echoes ` k8s:(<context>:<namespace>)` (namespace part omitted when unset), or nothing when there's no active context / no `kubectl` / `K8S_HIDE_CONTEXT` is set. Call it from your own `PROMPT`/`RPROMPT` in `.overrides.zsh` to keep this piece while building the rest yourself — e.g. to move it to the right prompt instead:

```zsh
# .devcontainer/zshrc.d/.overrides.zsh
PROMPT='%~ %# '                # drop the feature's default (left) placement
RPROMPT='$(kube_context_prompt)'  # …and put the k8s piece where you want
```

For just the raw `context` (no namespace/icon), call the underlying `kubectx_prompt_info` instead.

## Usage in devcontainer.json

**This repo (local path):**
```json
"features": {
  "./features/k8s": {}
}
```

**Other repos (OCI URI):**
```json
"features": {
  "ghcr.io/your-org/features/k8s:1": {}
}
```

## Firewall

Cluster endpoints and Helm chart repos are user-specific — add them to `.firewall/allowed-domains.conf` or via `allow-domain.sh` as needed.
