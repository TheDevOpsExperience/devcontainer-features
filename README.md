# devcontainer-features

Reusable [devcontainer Features](https://containers.dev/implementors/features/) for developer sandboxes — firewall, BuildKit, Claude/Gemini CLIs, gcloud, k8s, and more. Published to GHCR.

## Usage

Reference a feature by its published OCI URI in `devcontainer.json`:

```jsonc
"features": {
  "ghcr.io/TheDevOpsExperience/devcontainer-features/core": {},
  "ghcr.io/TheDevOpsExperience/devcontainer-features/firewall": {}
}
```

`core` is required by every other feature and must install first — every other feature declares `installsAfter: ["ghcr.io/TheDevOpsExperience/devcontainer-features/core"]` so this happens automatically.

A complete, copy-pasteable consumer setup (devcontainer.json, host.env, on-init hook) lives in [`examples/`](./examples).

## Features

| Feature | What it adds | Options |
|---------|-------------|---------|
| `core` | Baseline packages, helper scripts + sudoers, shell/Oh My Zsh setup, SSH config setup, volume ownership fixes — **required by all others** | — |
| `firewall` | iptables/ipset allowlist firewall, DNS capture, `allow-domain.sh`, `list-domains.sh` | — |
| `buildkit` | `buildctl` client + `docker-build` wrapper; connects to a shared `buildkitd` sidecar | `version`, `daemon_host`, `daemon_port` |
| `1password` | `op` CLI via the 1Password apt repository + SA-token host-init | — |
| `claude` | Claude Code CLI, pre-configured settings/CLAUDE.md/statusline | `skip_permissions` |
| `gemini` | Gemini CLI (`NO_BROWSER=true` always set) — API-key / Code Assist auth | `skip_permissions` |
| `antigravity` | Antigravity CLI (`agy`, native binary) — account-OAuth successor to gemini for non-API-key auth | `skip_permissions` |
| `codex` | OpenAI Codex CLI (`codex`, native binary, no Node) — ChatGPT-account / API-key auth | `skip_permissions` |
| `gcloud` | Google Cloud SDK (`gcloud`) via the official apt repository | — |
| `firebase` | Firebase CLI (via npm) — emulators need a `java` feature | — |
| `k8s` | kubectl, helm, kubectx, kubens — multi-arch | `kubectl_version`, `helm_version`, `kubectx_version` |
| `go` | Go toolchain + golangci-lint — multi-arch, GOPATH/build/lint cache persisted; gopls/dlv install on demand into the persisted GOPATH | `go_version`, `golangci_lint_version` |

See each feature's `src/<feature>/README.md` for full option details and notable behavior (e.g. the `claude` feature overwrites `~/.claude/CLAUDE.md` and `~/.claude/statusline.sh` on every container start).

## Base image

`image/Dockerfile` is an **optional build cache**. It pre-bakes the slow parts (apt packages, `gh`, `fzf`, `yq`) so `core`'s install-time checks become no-ops. All features work on any apt-based image (Debian/Ubuntu) without it.

It's published multi-arch (amd64 + arm64) to `ghcr.io/thedevopsexperience/tde-base` by `.github/workflows/build-image.yml` (on pushes to `main` touching `image/**`, on `v*` tags, or manually via *Run workflow*). Use it as your devcontainer base:

```jsonc
// devcontainer.json
"image": "ghcr.io/thedevopsexperience/tde-base:latest"
```

Or build it locally instead — `docker buildx build --platform linux/amd64,linux/arm64 -t my-base image/`.

### Tags

| Tag | Meaning |
|---|---|
| `latest` | Newest build from `main`. |
| `node<ver>`, `node<ver>-bookworm` | Rolling, newest build for that node major / distro (e.g. `node24`). Derived from the Dockerfile's `NODE_VERSION` arg. |
| `X.Y.Z`, `X.Y` | Image release (semver), published on a `vX.Y.Z` git tag. Bump it whenever node **or** a baked tool changes. |
| `sha-<short>` | Immutable — the exact commit, hence the exact tool set. Pin this (or the `@sha256:` digest) for reproducibility. |

### Versions

Only the node major is a knob — `ARG NODE_VERSION` in the Dockerfile drives both the base tag and the `node<ver>` tags. The baked tools (`gh`, `fzf`, `yq`) and apt packages track latest at build time; this is a convenience cache, not a reproducible-from-source image.

For a **frozen** base downstream, pin the published image by digest — that's immutable regardless of what floats in the Dockerfile:

```jsonc
"image": "ghcr.io/thedevopsexperience/tde-base@sha256:…"
```

Bump the image's git tag `vX.Y.Z` when you make a notable change (node bump, added tool) so the semver tags track meaningful snapshots.

## Development

```bash
# install the devcontainer CLI
npm install -g @devcontainers/cli

# run the smoke tests for every feature
devcontainer features test --project-folder .
```

## Credits

The `firewall` feature and `core`'s `install-package.sh` helper are adapted from
[**ilang/claude-code-dev-container**](https://github.com/ilang/claude-code-dev-container)
(MIT), which itself builds on Anthropic's
[**Claude Code devcontainer**](https://github.com/anthropics/claude-code/tree/main/.devcontainer)
— the original source of the allowlist-firewall and package-installer approach.
Anthropic's work is proprietary and is credited for attribution only. See
[NOTICE](./NOTICE) for full third-party licenses.

## License

[MIT](./LICENSE) — see also [NOTICE](./NOTICE) for third-party attributions.
