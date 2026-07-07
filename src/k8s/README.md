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

## Shell integration

Enables the `kubectl`, `helm`, and `kubectx` oh-my-zsh plugins via core's plugin registry — no config needed. `kubectl`/`helm` give aliases + completion; `kubectx` provides `kubectx_prompt_info` for the prompt (the ahmetb `kubectx`/`kubens` binaries carry their own completion). See core's `zsh_plugins` option to add your own on top.

Also shows the **active kube-context and namespace on the right prompt** (`RPROMPT`, as `⎈ context:namespace`), via core's `zshrc.d` drop-in — context from `kubectx_prompt_info`, namespace from `kubectl config view --minify`. The left prompt stays yours. Set short context names with `kubectx_mapping[long-context-name]=short`. Silence it with `export K8S_HIDE_CONTEXT=1` (e.g. in `.devcontainer/zshrc.d/.overrides.zsh`), or set your own prompt there to override — e.g. drop your host `PROMPT`/`RPROMPT` in verbatim, since `.overrides.zsh` is sourced last.

**Reusing the segment in a custom prompt.** The segment is a public shell function, `kube_context_prompt`, that echoes ` ⎈ <context>:<namespace>` (or nothing when there's no context / no `kubectl` / `K8S_HIDE_CONTEXT` is set). Call it from your own `PROMPT`/`RPROMPT` in `.overrides.zsh` to keep this piece while building the rest yourself:

```zsh
# .devcontainer/zshrc.d/.overrides.zsh
RPROMPT=''                              # drop the feature's default placement
PROMPT='%~ $(kube_context_prompt) %# '  # …and put the k8s piece where you want
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
