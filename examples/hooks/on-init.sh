#!/bin/bash
# on-init.sh — runs on the HOST before the container is built (initializeCommand).
# Prepares secrets and sidecar services. Never runs inside the container.
#
# It sources each feature's host-side script straight from the collection repo,
# so there is nothing to copy. Pin FEATURES_REF to a tag/commit for stability.
set -e

SCRIPT_DIR="$(dirname "$0")"
# Core's host script creates this directory and locks down devcontainer.env;
# we only need to tell it where .init lives. No export needed — the feature
# scripts are sourced into this same shell.
INIT_CONFIG_DIR="${SCRIPT_DIR}/../.init"

# Host-side configuration (OP_ACCOUNT, BUILDKIT_*). Shell exports take precedence
# (host.env uses ${VAR:-default}).
# shellcheck source=../host.env
source "${SCRIPT_DIR}/../host.env"

FEATURES_RAW_URL="https://raw.githubusercontent.com/TheDevOpsExperience/devcontainer-features"

# Pin each feature's host script to that feature's release tag. devcontainers/action
# tags every published feature as feature_<id>_<version>, so a ref pins the host
# hooks to the same revision as the OCI feature you consume in devcontainer.json.
# Keep these in sync with the versions you pin there. Use "main" for a floating
# latest (not reproducible).
#
# Leave a ref empty (or comment it out) to skip that feature's host script
# entirely — `load` is a no-op when the ref is unset/empty.
CORE_REF="feature_core_1.0.0"
ONEPASSWORD_REF="feature_1password_1.0.0"
BUILDKIT_REF="feature_buildkit_1.0.0"

# Fetch a feature's host script at the given ref and source it. curl runs in a
# command substitution (not a <(...) process substitution) so a failed fetch —
# 404 from a wrong ref/path, no network — propagates and aborts
# initializeCommand with a clear error. With process substitution the curl
# failure is masked and .init/devcontainer.env is silently never created,
# surfacing later as a cryptic "docker run --env-file ... no such file or
# directory".
load() {
  local feature="$1" ref="$2" url body
  # Empty/unset ref → feature disabled; skip without fetching.
  [ -n "$ref" ] || return 0
  url="${FEATURES_RAW_URL}/${ref}/src/${feature}/host/on-init.sh"
  body="$(curl -fsSL "$url")" || {
    echo "ERROR: on-init failed to fetch ${url}" >&2
    echo "       Check the ref (${ref}) exists on the remote and has src/." >&2
    exit 1
  }
  source /dev/stdin <<<"$body"
}

# ── Core (creates .init, locks devcontainer.env, generates SSH config) ───────
load core "$CORE_REF"

# ── 1Password (inject the SA token) ──────────────────────────────────────────
# Reads OP_ACCOUNT / OP_SA_ITEM_PATH from host.env. Remove if not using 1password.
load 1password "$ONEPASSWORD_REF"

# ── BuildKit (shared network + buildkitd sidecar) ────────────────────────────
# Remove if not using the buildkit feature. BUILDKIT_* come from host.env, which
# is already sourced into this shell, so sourcing the script picks them up.
load buildkit "$BUILDKIT_REF"
