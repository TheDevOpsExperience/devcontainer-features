#!/bin/bash
# start-buildkitd.sh — ensures the shared Docker network and buildkitd sidecar
# container are running. Runs on the HOST (called from on-init.sh).
#
# Required env vars:
#   BUILDKIT_NETWORK   - Docker network name (must match runArgs --network)
#   BUILDKIT_CONTAINER - container name (must match daemon_host option)
#   BUILDKIT_PORT      - port buildkitd listens on (must match daemon_port option)
# Optional:
#   BUILDKIT_VERSION   - buildkitd version to run, without v prefix (default:
#                        latest). Keep in sync with the feature's "version"
#                        option so client and daemon match.
set -e

BUILDKIT_VERSION="${BUILDKIT_VERSION:-latest}"
# Rootless image: buildkitd runs as a non-root user inside the container, so a
# breakout from a build step lands in a locked-down container, not on the host.
# This is the difference that makes the sidecar safer than mounting docker.sock.
# Tag form differs by version: latest is just "rootless" (no "latest-" prefix),
# pinned versions are "vX.Y.Z-rootless".
if [ "${BUILDKIT_VERSION}" = "latest" ]; then
  BUILDKIT_IMAGE="moby/buildkit:rootless"
else
  BUILDKIT_IMAGE="moby/buildkit:v${BUILDKIT_VERSION#v}-rootless"
fi

if ! docker network ls --format '{{.Name}}' | grep -q "^${BUILDKIT_NETWORK}$"; then
  echo "Creating ${BUILDKIT_NETWORK} network..."
  docker network create "${BUILDKIT_NETWORK}"
else
  echo "Network ${BUILDKIT_NETWORK} already exists"
fi

if docker ps --format '{{.Names}}' | grep -q "^${BUILDKIT_CONTAINER}$"; then
  RUNNING_IMAGE=$(docker inspect -f '{{.Config.Image}}' "${BUILDKIT_CONTAINER}")
  echo "buildkitd already running (${RUNNING_IMAGE})"
  if [ "${RUNNING_IMAGE}" != "${BUILDKIT_IMAGE}" ]; then
    echo "WARNING: running buildkitd image ${RUNNING_IMAGE} differs from requested ${BUILDKIT_IMAGE}." >&2
    echo "         To switch: docker rm -f ${BUILDKIT_CONTAINER} and re-run this script." >&2
  fi
elif docker ps -a --format '{{.Names}}' | grep -q "^${BUILDKIT_CONTAINER}$"; then
  echo "Starting existing buildkitd container..."
  docker start "${BUILDKIT_CONTAINER}"
else
  echo "Starting buildkitd (${BUILDKIT_IMAGE})..."
  # Rootless buildkitd — no --privileged. Per moby/buildkit's rootless docs
  # (docs/rootless.md), the Docker recipe is three security-opt relaxations:
  #   - seccomp/apparmor unconfined: the default Docker profiles block the
  #     unshare/user-namespace syscalls RootlessKit needs inside the container.
  #   - systempaths=unconfined: unmasks /proc so buildkitd keeps its own process
  #     sandbox. Preferred over --oci-worker-no-process-sandbox (the k8s-only
  #     fallback), which can't reap ExecOp processes and lets a build step
  #     kill/ptrace processes in the daemon container.
  # All three are far weaker than --privileged (no extra caps, no host devices).
  # Do NOT add --allow-insecure-entitlement here: it would re-enable privileged
  # build steps (RUN --security=insecure) and reopen a direct host-escape path.
  docker run -d \
    --name "${BUILDKIT_CONTAINER}" \
    --restart unless-stopped \
    --network "${BUILDKIT_NETWORK}" \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    --security-opt systempaths=unconfined \
    "${BUILDKIT_IMAGE}" \
    --addr "tcp://0.0.0.0:${BUILDKIT_PORT}"
fi
