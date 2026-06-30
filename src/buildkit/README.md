## Prerequisites

Requires the `core` feature.

## Options

| Option | Default | Description |
|---|---|---|
| `version` | `latest` | BuildKit version of the `buildctl` client (without `v` prefix). Pin for reproducible builds; keep in sync with `BUILDKIT_VERSION` in `host.env` so client and daemon match. `latest` is resolved without `api.github.com` (no rate-limit issues). |
| `daemon_host` | `buildkitd` | Hostname of the BuildKit daemon container. Must match the container name in `on-init.sh`. |
| `daemon_port` | `1234` | Port the BuildKit daemon listens on. |

Example with non-default values:
```json
"registry.example.com/devcontainer-features/buildkit:1": {
  "daemon_host": "my-buildkitd",
  "daemon_port": "1234"
}
```

## Building images

The feature installs two PATH commands wrapping `buildctl`:

### `docker-build`

```
docker-build <context> [-f <dockerfile>] [-t <name:tag>] [--push] [buildctl options...]
```

| Flag | Meaning |
|---|---|
| `-f`, `--file` | Dockerfile path (default `Dockerfile`). |
| `-t`, `--tag` | Image name:tag → `--output type=image,name=<tag>`. |
| `--push` | Add `push=true`. Requires `-t` and credentials — either `REGISTRY_TOKEN` or an existing `~/.docker/config.json` (errors otherwise). |
| anything else | Passed straight through to `buildctl` (`--opt`, `--build-arg`, …). |

```bash
docker-build .                                   # build only, no image output
docker-build . -t myimage:latest                 # local image
docker-build . -f docker/Dockerfile.prod -t reg.example.com/me/img:1.2 --push
```

Credentials on `--push`, in order:

- **`REGISTRY_TOKEN`** set → login uses an **isolated** docker config (`mktemp`,
  never touches `~/.docker/config.json`). Host is derived from the `-t` tag
  (Docker rules: a leading segment with a `.` or `:port` is the host, else Docker
  Hub). If a `~/.docker/config.json` already exists it is **merged in** (so
  `credHelpers` / other registries — e.g. from `gcloud auth configure-docker` —
  survive), then the token entry is added.
  ```bash
  export REGISTRY_USER=me
  export REGISTRY_TOKEN=<token>   # literal, or an op:// reference with docker-push
  ```
- **No token but an existing `~/.docker/config.json`** (e.g. `gcloud auth
  configure-docker`, a prior `docker login`) → used as-is, untouched.
- **Neither** → `--push` errors.

### `docker-push`

`docker-build --push`, auto-wrapped in **`op run`** when `op` is on PATH and
`REGISTRY_TOKEN` is a 1Password secret reference — the secret is resolved
just-in-time and never stored. With a literal token (or no `op`) it calls
`docker-build` directly.

```bash
export REGISTRY_USER=ingradi
export REGISTRY_TOKEN="op://vault/Registry PAT/credential"
docker-push . -t reg.example.com/me/img:1.2
```

(Single tag only — `buildctl`'s `name=` field takes one tag. For multi-tag
aliases, retag afterwards with `oras tag`.)

## Registry access (firewall + login)

The feature allowlists the buildkitd daemon host (`daemon_host`) plus **Docker
Hub's auth + registry API** (`auth.docker.io`, `registry-1.docker.io`) as a sane
default — Docker Hub is the implicit registry for unqualified `FROM` images. Any
**other** registry depends on your project, so you allowlist it yourself.

### Which side reaches the registry — and what the firewall sees

A registry interaction splits across the two containers, and only one of them is
behind the firewall:

| Step | Runs in | Behind the firewall? | Hosts |
|---|---|---|---|
| Auth handshake / token | **this devcontainer** (`buildctl`) | **yes — must allowlist** | `auth.docker.io`, etc. |
| Manifest / image-config resolution | **this devcontainer** | **yes — must allowlist** | `registry-1.docker.io`, `ghcr.io`, … |
| Layer **blob** pull/push | **buildkitd sidecar** | **no** (sidecar isn't firewalled) | `production.cloudflare.docker.com`, `storage.googleapis.com`, … |

So allowlist the **auth + registry API** hosts in *this* container; the **blob
CDN** hosts are pulled by the sidecar and don't need a firewall entry here. (This
is why a `FROM node` pull fails with a blocked `auth.docker.io` even though the
sidecar fetches the actual layers.)

### Using another registry

1. **Allowlist its auth + registry hosts** — add them to
   `.devcontainer/.firewall/allowed-domains.conf` (persistent) or your own `domains.d/*.conf`.
   Blob-CDN hosts are *italicised* below — sidecar-side, usually no entry needed:

   | Registry | Auth + registry API (allowlist here) | Blob CDN (sidecar) |
   |---|---|---|
   | Docker Hub | `registry-1.docker.io`, `auth.docker.io` *(default)* | _`production.cloudflare.docker.com`_ |
   | GHCR | `ghcr.io` | _`pkg-containers.githubusercontent.com`_ |
   | GitLab | `registry.gitlab.com` | _`storage.googleapis.com`_ |

2. **Authenticate** — easiest is `docker-push` (or `docker-build --push`) with
   `REGISTRY_USER` / `REGISTRY_TOKEN` set (see [Building images](#building-images)).
   Otherwise run `docker login` (or seed `~/.docker/config.json`) inside the
   container. Without credentials the daemon authenticates anonymously and push
   fails with a 401.

## Host initialisation

This feature ships a host-side script (`host/on-init.sh`) that ensures the
shared Docker network and buildkitd sidecar are running. Add the following to
`.devcontainer/hooks/on-init.sh` when using this feature, fetching the script straight
from this repo so you don't need to copy it. Pin `FEATURES_REF` to a tag/commit
for stability.

```bash
# ── BuildKit (buildkit feature) ──────────────────────────────────────────────
FEATURES_RAW_URL="https://raw.githubusercontent.com/TheDevOpsExperience/devcontainer-features"
FEATURES_REF="main"             # pin to a tag/commit for stability

BUILDKIT_NETWORK="devcontainer-shared"  # must also match runArgs --network in devcontainer.json
BUILDKIT_CONTAINER="buildkitd"          # must match daemon_host option
BUILDKIT_PORT="1234"                    # must match daemon_port option
BUILDKIT_VERSION="latest"               # must match version option (daemon/client parity)

curl -fsSL "${FEATURES_RAW_URL}/${FEATURES_REF}/src/buildkit/host/on-init.sh" \
  | BUILDKIT_NETWORK="${BUILDKIT_NETWORK}" BUILDKIT_CONTAINER="${BUILDKIT_CONTAINER}" BUILDKIT_PORT="${BUILDKIT_PORT}" BUILDKIT_VERSION="${BUILDKIT_VERSION}" bash
```

If you're working in this repo itself (local feature paths), `on-init.sh` already
sources `host/on-init.sh` directly — no curl needed.
