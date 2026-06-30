#!/bin/bash
# docker-push — docker-build --push, auto-wrapped in `op run` when the registry
# token is a 1Password secret reference.

set -euo pipefail

usage() {
  cat <<'EOF'
docker-push — build and push an image (docker-build --push), with optional
1Password integration.

Usage:
  docker-push <context> -t <name:tag> [docker-build options...]

Behaviour:
  Always adds --push and forwards every argument to docker-build. If `op` is on
  PATH and REGISTRY_TOKEN is an op:// reference, the command runs under `op run`
  so the secret is resolved just-in-time and never stored. With a literal token
  (or no op) it calls docker-build directly.

Options:
  -h, --help   Show this help.
  (all other flags are passed through to docker-build — see `docker-build --help`)

Environment:
  REGISTRY_USER    Registry username.
  REGISTRY_TOKEN   Registry token — a literal value, or an op:// reference
                   (e.g. op://vault/Registry PAT/credential) to resolve via op.

Examples:
  export REGISTRY_USER=me
  export REGISTRY_TOKEN="op://vault/Registry PAT/credential"
  docker-push . -t reg.example.com/me/img:1.2
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

if command -v op >/dev/null 2>&1 && [[ "${REGISTRY_TOKEN:-}" == op://* ]]; then
  exec op run -- docker-build "$@" --push
else
  exec docker-build "$@" --push
fi
