#!/bin/bash
# docker-build — wrapper around buildctl for Dockerfile-based builds.

set -euo pipefail

usage() {
  cat <<'EOF'
docker-build — build a Dockerfile with buildctl (BuildKit), optionally pushing.

Usage:
  docker-build <context> [-f <dockerfile>] [-t <name:tag>] [--push] [buildctl options...]

Options:
  -f, --file <path>    Dockerfile to build (default: Dockerfile).
  -t, --tag <name:tag> Image name:tag to produce.
  --push               Push the image. Requires -t and credentials.
  -h, --help           Show this help.
  <other>              Anything else is passed straight to buildctl
                       (e.g. --opt build-arg:FOO=bar).

Environment (used only with --push):
  REGISTRY_TOKEN   Registry token/password. If a token is set, login uses an
                   isolated docker config and never touches ~/.docker.
  REGISTRY_USER    Registry username paired with REGISTRY_TOKEN.

Credentials for --push (in order):
  1. REGISTRY_TOKEN set      → isolated login; host derived from the -t tag.
                               An existing ~/.docker/config.json is merged in
                               (credHelpers / other registries survive).
  2. ~/.docker/config.json   → used as-is (e.g. gcloud auth configure-docker).
  3. neither                 → --push errors.

Examples:
  docker-build .                                   # build only, no image output
  docker-build . -t myimage:latest                 # build a local image
  docker-build . -t reg.example.com/me/img:1.2 --push
  docker-build . -f docker/Dockerfile.prod -t img:prod --push --opt build-arg:FOO=bar
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

context="${1:-.}"
shift || true
dockerfile="Dockerfile"
tag=""
push=false
remaining=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      dockerfile="$2"
      shift 2
      ;;
    -t|--tag)
      tag="$2"
      shift 2
      ;;
    --push)
      push=true
      shift
      ;;
    *)
      remaining+=("$1")
      shift
      ;;
  esac
done

# ── Validate push/tag combination ─────────────────────────────────────────────
# Existing docker config (e.g. from `gcloud auth configure-docker`) is a valid
# credential source on its own. Capture it before we override DOCKER_CONFIG.
src_config="${DOCKER_CONFIG:-$HOME/.docker}/config.json"

if [ "$push" = true ] && [ -z "$tag" ]; then
  echo "ERROR: --push requires -t <name:tag> (nothing to push to)." >&2
  echo >&2
  usage >&2
  exit 1
fi

if [ "$push" = true ] && [ -z "${REGISTRY_TOKEN:-}" ] && [ ! -f "$src_config" ]; then
  echo "ERROR: --push needs credentials — either REGISTRY_TOKEN (+ REGISTRY_USER) in" >&2
  echo "       the environment, or an existing docker config at $src_config" >&2
  echo "       (e.g. from 'gcloud auth configure-docker')." >&2
  echo "       Tip: wrap the command in 'op run -- docker-build ...' to inject a token." >&2
  echo >&2
  usage >&2
  exit 1
fi

# ── Optional registry login (isolated docker config) ──────────────────────────
# Only needed when injecting a token. Without a token, buildctl uses the ambient
# config ($src_config) directly. With a token, seed an isolated config from the
# ambient one (so credHelpers / other registries survive) then merge our entry —
# never mutating ~/.docker/config.json.
if [ "$push" = true ] && [ -n "${REGISTRY_TOKEN:-}" ]; then
  host="${tag%%/*}"
  case "$host" in
    *.*|*:*) : ;;            # has a dot or :port → real registry host
    *) host="docker.io" ;;   # no host segment in tag → Docker Hub
  esac

  _DOCKER_CONFIG="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$_DOCKER_CONFIG'" EXIT

  if [ -f "$src_config" ]; then
    cp "$src_config" "$_DOCKER_CONFIG/config.json"
  else
    echo '{}' > "$_DOCKER_CONFIG/config.json"
  fi

  auth="$(printf '%s:%s' "${REGISTRY_USER:-}" "$REGISTRY_TOKEN" | base64 -w0)"
  jq --arg h "$host" --arg a "$auth" '.auths[$h].auth = $a' \
    "$_DOCKER_CONFIG/config.json" > "$_DOCKER_CONFIG/config.json.tmp"
  mv "$_DOCKER_CONFIG/config.json.tmp" "$_DOCKER_CONFIG/config.json"

  export DOCKER_CONFIG="$_DOCKER_CONFIG"
  if [ -f "$src_config" ]; then
    echo "Logged in to $host as ${REGISTRY_USER:-<no-user>} (merged with $src_config)"
  else
    echo "Logged in to $host as ${REGISTRY_USER:-<no-user>}"
  fi
fi

# ── Assemble output option ────────────────────────────────────────────────────
output=()
if [ -n "$tag" ]; then
  if [ "$push" = true ]; then
    output=(--output "type=image,name=${tag},push=true")
  else
    output=(--output "type=image,name=${tag}")
  fi
fi

buildctl \
  --addr "${BUILDKIT_HOST:-tcp://buildkitd:1234}" \
  build \
  --frontend dockerfile.v0 \
  --local context="$context" \
  --local dockerfile="$(dirname "$dockerfile")" \
  --opt filename="$(basename "$dockerfile")" \
  "${output[@]}" \
  "${remaining[@]}"
