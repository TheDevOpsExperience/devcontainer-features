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
