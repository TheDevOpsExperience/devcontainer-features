# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Public collection of reusable devcontainer **Features** for developer sandboxes. Features are published as OCI images to **GHCR** (`ghcr.io/TheDevOpsExperience/devcontainer-features/<feature>`) and consumed by project-specific `devcontainer.json` files in other repos.

Layout follows the official `devcontainers/feature-starter` convention: one feature per directory under `src/`, matching tests under `test/`.

```
src/<feature>/devcontainer-feature.json   # metadata, options, lifecycle hooks
src/<feature>/install.sh                   # build-time install
test/<feature>/                            # smoke tests (devcontainer features test)
```

## How features are referenced

Consumers reference features by their **published GHCR URI**:

```json
"features": {
  "ghcr.io/TheDevOpsExperience/devcontainer-features/core": {},
  "ghcr.io/TheDevOpsExperience/devcontainer-features/firewall": {}
}
```

Within this repo, `installsAfter` and inter-feature references also use the GHCR URI (not local paths), so consumers get correct install ordering automatically.

## Feature Architecture

### `core` feature vs. base image

The **`core` feature is self-sufficient** and works on any apt-based image (Debian/Ubuntu). It provides everything the other features depend on:

- Baseline packages via an idempotent `check_packages` helper (no-op when already present): `curl`, `wget`, `ca-certificates`, `git`, `jq`, `unzip`, `gpg`, `less`, `procps`, `sudo`, `zsh`, `openssh-client`
- Lifecycle hooks (SSH config, ownership fixes, `.zsh_profile` seeding) wired via core's own `postCreateCommand` / `postStartCommand` contributions; `.init` cleanup runs via `postAttachCommand` (fires on reconnect too, where `postStart` does not)
- Helper scripts + sudoers: `fix-ownership.sh`, `install-package.sh`, `fix-volume-ownership.sh` (sudoers written for `_REMOTE_USER`, not a hardcoded user)
- A `/usr/local/share/devcontainer/.core-installed` marker so dependent features can verify core ran first
- `/etc/profile.d/` sourcing loop in `.zshrc` (so feature env vars are available in VS Code terminals) — appended only if not already present
- History persistence wired to `/dc-volumes/commandhistory` (zsh + bash) — appended only if not already present
- Oh My Zsh (robbyrussell theme, git + fzf plugins) — skipped when `~/.oh-my-zsh` already exists; `fzf` ensured via binary check (apt fallback)
- Sets the user's login shell to zsh

**Other features depend only on `core`.** All non-core `install.sh` scripts guard against core being absent:

```bash
if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi
```

Features installing via `npm` (`firebase`, `gemini`) require Node.js in the base image and bail out recommending `ghcr.io/devcontainers/features/node` when `npm` is missing. `firebase` additionally requires a Java runtime for the emulators and bails out recommending `ghcr.io/devcontainers/features/java`.

### Feature install order

Every non-core feature declares:

```json
"installsAfter": ["ghcr.io/TheDevOpsExperience/devcontainer-features/core"]
```

so OCI consumers get correct ordering automatically. If feature X must run after feature Y at runtime, X declares `installsAfter: [..., Y]`. Two features with no dependency relation are ordered alphabetically by ID (deterministic, but don't rely on it for real ordering).

### Self-install, not `dependsOn` wrappers

Every feature **installs its own tool directly**. A `dependsOn` wrapper approach
(declare an upstream community/official feature as a hard dependency and only
write the firewall `domains.d` locally) was tried and reverted — upstream
features proved too fragile: no maintained `op` feature exists, and the dhoeric
`google-cloud-cli` feature uses the removed `apt-key` and breaks on modern
Ubuntu. So prefer a self-contained `install.sh` (apt/npm/binary) over
`dependsOn` unless the upstream is known-robust and you've verified its build.
`firebase` and `gemini` install via npm; the rest via apt or a native binary.

### Mutually exclusive features

The devcontainer spec has no `conflictsWith` primitive, so mutual exclusion is
enforced at install time with marker files. Each feature drops
`/usr/local/share/devcontainer/.<id>-installed` early in its `install.sh` and, before
that, errors if the conflicting feature's marker already exists. Whichever
installs second sees the other's marker and fails the build with a clear message.
Current pair: `gemini` ⇄ `antigravity` (`.gemini-installed` / `.antigravity-installed`).

## Key Conventions

### Volume naming

Feature mounts use `${localWorkspaceFolderBasename}` suffix so volumes are automatically scoped per project:

```json
"source": "commandhistory-${localWorkspaceFolderBasename}"
```

| Volume source | Mount target | Symlinked from | Feature |
|---|---|---|---|
| `commandhistory-<project>` | `/dc-volumes/commandhistory` | — | `core` |
| `config-<project>` | `/dc-volumes/config` | `~/.config` | `core` |
| `claude-<project>` | `/dc-volumes/claude` | `~/.claude` | `claude` |
| `gemini-<project>` | `/dc-volumes/gemini` | `~/.gemini` | `gemini`, `antigravity` (shared — both use `~/.gemini`; mutually exclusive) |
| `codex-<project>` | `/dc-volumes/codex` | `~/.codex`; `~/.agents` → `/dc-volumes/codex/agents` subdir | `codex` |
| `kube-<project>` | `/dc-volumes/kube` | `~/.kube` | `k8s` |
| `go-<project>` | `/dc-volumes/go` | `~/go` → `gopath/` subdir (also `GOPATH`/`GOCACHE`/`GOLANGCI_LINT_CACHE` env; `cache/` subdir untouched by the symlink) | `go` |

Mount targets are user-neutral `/dc-volumes/<name>` paths because feature mounts can't reference the remote user. Each feature's `install.sh` symlinks the corresponding home-dir path (for the user from `_REMOTE_USER`) to the volume, so the features work with any `remoteUser`.

**Never install a feature-owned binary under a volume mount target.** `install.sh` runs at build time, when `/dc-volumes/<name>` is still an ordinary image directory. The named volume mounts over it at container create and seeds itself from the image *only while it's empty* — so on every later rebuild the image content at that path is shadowed by whatever the volume already holds. A tool installed there can never be updated by a rebuild (bumping a `*_version` option would silently keep the old binary), and its build artifacts get baked into every image layer for nothing. Install tools into the image (`/usr/local/bin`, `/usr/local/go`, …) and keep the volume for state the *user* generates at runtime — config, credentials, caches. `go` is the worked example: the toolchain and `golangci-lint` go to `/usr/local/go` and `/usr/local/bin`, while the runtime `GOPATH` (where the user's own `go install` writes) stays on the volume.

**Corollary — a tool the volume already persists doesn't need installing at build time at all.** If an editor extension or the tool's own ecosystem already installs it into a persisted path, let it. `go` is again the example: `gopls`/`dlv` are *not* installed by the feature. The `golang.go` VS Code extension installs them on demand into `GOPATH/bin`, which is on the volume, so they survive rebuilds; the fetch needs only `proxy.golang.org`, already allowlisted. That drops two version options the editor manages better, and with them the pinned-`go_version`-vs-current-`gopls` conflict. Apply this only when all three hold: something else owns the install, the target path is persisted, and the runtime domains are already allowlisted. `golangci-lint` fails the third (GitHub hosts are build-time only) and wants CI-matching pins, so it stays baked in.

### Environment variables

Do NOT set env vars via `containerEnv` in `devcontainer-feature.json` when the value contains a `.` (Docker rejects `.` in Dockerfile ENV variable names). Instead write them to `/etc/profile.d/` from `install.sh`:

```bash
echo "export BUILDKIT_HOST=tcp://${HOST}:${PORT}" > /etc/profile.d/buildkit-env.sh
```

VS Code opens a non-login zsh, so `/etc/profile.d/` is not sourced automatically. The `core` feature appends a sourcing loop to `.zshrc` to handle this.

### Lifecycle hooks

Each feature that needs create-time or start-time work contributes its own `postCreateCommand` / `postStartCommand` in `devcontainer-feature.json`, pointing at a script the feature's `install.sh` persists under `/usr/local/share/devcontainer/<feature>/`:

```jsonc
// devcontainer-feature.json
"postCreateCommand": "/usr/local/share/devcontainer/<feature>/create.sh",
"postStartCommand":  "/usr/local/share/devcontainer/<feature>/setup.sh"
```

```bash
# install.sh — persist outside the feature dir (install scripts aren't
# guaranteed to survive the build) and outside /tmp
mkdir -p /usr/local/share/devcontainer/<feature>
cp "$FEATURE_DIR/lifecycle/setup.sh" /usr/local/share/devcontainer/<feature>/setup.sh
chmod +x /usr/local/share/devcontainer/<feature>/setup.sh
```

**Ordering is per the devcontainer spec: feature lifecycle hooks run in Feature installation order, grouped by phase (all `postCreate` across features, then all `postStart`), before any `devcontainer.json` hook.** Use string/array command form, never the object form (object entries run in parallel). A feature with multiple ordered steps chains them inside its single script.

### Baking feature options into flag files

Feature options are only available during `install.sh` — not at `postCreateCommand` / `postStartCommand` time. To pass boolean options to create/setup scripts, bake them into flag files during install:

```bash
# install.sh
if [ "${SKIP_PERMISSIONS:-false}" = "true" ]; then
    touch /usr/local/share/devcontainer/.feature-flag
fi
```

Then check the flag file in the lifecycle script.

### Firewall domain allowlist

Features that need network access at runtime register their domains in `/usr/local/share/devcontainer/domains.d/<feature>.conf`. The `firewall` setup scripts read these files to allowlist domains on container start.

**Allowlist hygiene — register only what the container needs at runtime.** The always-on allowlist is a standing capability, so keep it tight. Before adding a domain to a `.conf`, classify it:

- **Build-time only** (apt repos, CLI download/install hosts, anything hit during `install.sh`) → **omit**. Feature install runs *before* the firewall (and `dependsOn` pulls happen pre-firewall too), so these don't need allowlisting.
- **Host-browser only** (OAuth *consent* pages like `accounts.google.com`, emulator/UI assets) → **omit**. The browser runs on the host with full network; only what the in-container CLI dials counts. Note the token *exchange/refresh* (e.g. `oauth2.googleapis.com`) is in-container and does need allowlisting — only the consent page is host-side.
- **Broad or occasional** (hosts serving every repo/bucket — `raw.githubusercontent.com`, `storage.googleapis.com`; or rarely-used endpoints) → **omit from always-on**; document them as a per-session `allow-domain.sh` in a `# NOTE:` comment next to the `.conf`.
- **Consumer-specific** (e.g. the container registry for `buildkit`) → **omit**; the feature can't know it. Register only the universal piece and document the rest in the feature README.
- **Runtime-essential and feature-universal** → **register**. This is the only category that belongs in the `.conf`.

Prefer the authoritative vendor "network requirements / restricted network" doc over guessing; cite it in a comment above the heredoc (see `claude/install.sh`). Add a short comment explaining why each non-obvious domain is needed and why notable ones were left out.

### oh-my-zsh plugin registry

Same drop-in pattern as `domains.d/`, for oh-my-zsh plugins. A feature that wants its matching plugin enabled writes one plugin name per line to `/usr/local/share/devcontainer/zsh-plugins.d/<feature>.conf` in its `install.sh` (e.g. `k8s` writes `kubectl`/`helm` for aliases+completion, plus `kubectx` for its `kubectx_prompt_info` used by the prompt segment). Core's `zsh_plugins` option writes the user's own list to `user-plugins.conf`. Core's `create.sh` merges every `.conf` (plus the always-on `git`/`fzf` baseline) into the `.zshrc` `plugins=()` array at container-create — deduped, and regenerated from the registry each create so it's idempotent across rebuilds.

This decouples features from core: enabling a feature never requires touching `core.zsh_plugins`. Only enable a plugin whose tool the feature actually installs, and only one that ships bundled with oh-my-zsh (no separate plugin install — sourcing the bundled file is what enables it). Timing works because `create.sh` runs after every feature's `install.sh`, so all `.conf` files exist when the merge runs.

### Interactive-zsh drop-ins (`zshrc.d/`)

The interactive-zsh sibling of `profile.d` (env, `sh`) and `zsh-plugins.d` (plugins): for prompt segments, keybinds, functions — anything needing a live zsh. Core appends two lines to `.zshrc` (after oh-my-zsh/theme, so `RPROMPT` edits stick without a `precmd`) that source, in three tiers, last-wins:

1. **Features** — a feature drops `/usr/local/share/devcontainer/zshrc.d/<name>.zsh` in its `install.sh` (baked at build). `k8s` adds a kube-context `PROMPT` segment.
2. **Project** — every `*.zsh` in the workspace's `.devcontainer/zshrc.d/` (committed, team-shared). `create.sh` writes the loader to `$HOME/.devcontainer-project-zshrc.zsh` with the resolved `${containerWorkspaceFolder}` — passed as the first arg to `create.sh` via core's `postCreateCommand`. Sourced **live** from the bind-mounted workspace, so edits land in any new terminal, no rebuild. The loader lives in the user's home (not root-owned `/usr/local/share`) because `create.sh` runs as the non-root remote user; the `.zshrc` source line keeps `$HOME` literal so it resolves per-user.
3. **Personal** — `.devcontainer/zshrc.d/.overrides.zsh` (gitignored). The leading dot keeps it out of the project `*.zsh(N)` glob; the loader sources it **explicitly last**, so it wins.

**Prompt lanes, so features and the user don't collide:** the theme sets the initial `PROMPT`/`RPROMPT` (robbyrussell leaves `RPROMPT` empty). No enforced default lane for features — each picks whichever side fits its segment and extends (pre- or append) rather than replacing. `k8s` prepends to `PROMPT`, first in the chain ahead of the theme's own segments, since kube-context is high-consequence (which cluster you're pointed at) and easy to miss on the right edge of a narrow terminal. Project/personal tiers are sourced after features, so a user's own prompt/theme wins. Each feature segment must honor a documented opt-out env (e.g. `k8s` → `K8S_HIDE_CONTEXT=1`) so a user can silence one segment while keeping the default prompt. See `examples/zshrc.d/` for the consumer layout.

**The `commandhistory` volume holds history only** (`.bash_history`, `.zsh_history`) — no shell config. Interactive-zsh config lives in `zshrc.d` (feature/project/personal), never on that volume.

### Package installation inside containers

Do NOT use `apt-get` directly from inside the container. Use the wrapper:

```bash
sudo install-package.sh <package1> [package2] ...
```

The `install-package.sh` script validates package names and rejects flags.

## Feature Summary

| Feature | What it adds | Options |
|---------|-------------|---------|
| `core` | Baseline packages, helper scripts + sudoers, shell/Oh My Zsh setup, SSH config setup, volume ownership fixes, idle-stop watchdog, oh-my-zsh plugin registry — **required by all others** | `idle_stop`, `idle_grace`, `zsh_plugins`, `git_prompt` |
| `firewall` | iptables/ipset allowlist firewall, DNS capture, `allow-domain.sh`, `revoke-domain.sh`, `list-domains.sh` (+`--json`), `list-attempts.sh` (+`--json`), Firewall Monitor VS Code extension | `install_extension`, `enabled` |
| `buildkit` | `buildctl` client + `docker-build` wrapper; connects to shared `buildkitd` sidecar | `version`, `daemon_host`, `daemon_port` |
| `1password` | `op` CLI via apt repository + SA-token host-init | — |
| `claude` | Claude Code CLI, pre-configured settings/CLAUDE.md/statusline | `skip_permissions` |
| `gemini` | Gemini CLI (`NO_BROWSER=true` always set) — API-key / Code Assist auth | `skip_permissions` |
| `antigravity` | Antigravity CLI (`agy`, native binary, no Node) — account-OAuth successor to gemini for non-API-key auth | `skip_permissions` |
| `gcloud` | Google Cloud SDK (`gcloud`) via apt repository | — |
| `codex` | OpenAI Codex CLI (`codex`, native binary, no Node) — ChatGPT-account / API-key auth | `skip_permissions` |
| `firebase` | Firebase CLI (via npm) — emulators need a `java` feature | — |
| `k8s` | kubectl, helm, kubectx, kubens — multi-arch | `kubectl_version`, `helm_version`, `kubectx_version` |
| `go` | Go toolchain + golangci-lint — multi-arch, GOPATH/build/lint cache persisted; gopls/dlv install on demand into the persisted GOPATH | `go_version`, `golangci_lint_version` |

### Notable option behavior

- **`core.idle_stop`** (bool, default `false`) — runs a root watchdog
  (`idle-stop.sh`) that stops the container once VS Code has been disconnected for
  `idle_grace` seconds, so nothing runs unattended. Covers both window-close and
  CLI-launched (`devcontainer up`) containers, unlike devcontainer.json
  `shutdownAction`. **Default off** because core is mandatory — enable per
  project (the devcontainer template sets `core: { idle_stop: true }`). Liveness
  is a VS Code IPC-socket *connect/listen* probe (not file presence), so it
  needs `ss`/`socat`/`pgrep`; logs to `/var/log/idle-stop.log`.
- **`core.idle_grace`** (string, default `"120"`) — seconds before idle-stop
  halts the container. Aggressive values can trip on laptop-sleep / reconnect.
- **`core.git_prompt`** (bool, default `true`) — robbyrussell's theme bakes
  `$(git_prompt_info)` into its own `PROMPT` unconditionally. The
  `zshrc.d/git-prompt.zsh` drop-in strips that (so core, not the theme, owns
  whether it shows — no theme-file patch, survives oh-my-zsh updates and the
  "already installed, skip" branch) and re-adds it with
  `PROMPT+=' $(git_prompt_info)'` only when enabled — same pattern as k8s's
  own prompt segment. Regenerated every install.
- **`firewall.enabled`** (bool, default `true`) — set `false` to skip
  `init-firewall.sh`'s lockdown and the periodic IP-refresh daemon; all egress
  flows normally. DNS capture (`capture-dns.sh`) still runs regardless — with
  enforcement off, nothing pre-populates `/etc/hosts`, so every lookup is a real
  DNS query and the capture log ends up recording every requested domain, not
  just the denied/unknown ones. The `firewall-dir` marker file (normally written
  by `init-firewall.sh`, read as a fallback by `list-domains.sh` /
  `list-attempts.sh`) is now written by `capture-dns.sh` itself so it's still
  correct when the lockdown step is skipped. The extension is mode-aware: it
  checks the same install-time flag file
  (`/usr/local/share/devcontainer/firewall/enabled`) at activation and hides the
  **Allowlist**/**Ignored** panels when it's absent, retitling
  **Attempted/Denied** to **Requested** and dropping its inline ignore/allow
  buttons + circle-slash icon (plain globe instead) — with nothing enforced
  there's nothing to decide, it's just a log.
- **`firewall.install_extension`** (bool, default `true`) — installs the Firewall
  Monitor VS Code extension (allowlist TreeView, session-domain revoke, runtime
  allow-event toasts). The `.vsix` is built in CI (`release.yml` "Bundle
  firewall extension" step) and shipped INSIDE the feature OCI artifact;
  `install.sh` copies it out at build time and `setup.sh` runs
  `code --install-extension`. The extension is 1:1 coupled to the feature — no
  standalone release/tag and no version sync (`extension/package.json` `version`
  is only what `vsce` needs, not a pin). All failures are non-fatal (graceful
  degrade; locally `devcontainer features test` ships no `.vsix` → skipped). `revoke-domain.sh` (sudoers-allowlisted) and
  `list-domains.sh --json` back the extension; node never needs root for it.
  The extension also has an **Attempted/Denied** panel (`list-attempts.sh --json`)
  with per-row ignore / allow-persistent / allow-session actions. **DNS capture
  logs moved to `/var/log`** (root-owned, tamper-resistant, reset on rebuild):
  `firewall-dns.log` (session, every attempt, truncated each start) +
  `firewall-dns-audit.log` (deduped first-seen, append-only, `SEEN` seeded from it
  across restarts). `.firewall/` now holds **config only** (allow/ignore lists).
- **`claude.skip_permissions`** (bool, default `false`) — adds `--dangerously-skip-permissions` to the `claude` alias. Appropriate for sandboxed containers where the firewall replaces Claude's permission system.
- The `claude` feature does **not** provision plugins — users install them at runtime; they persist because the whole `~/.claude` config dir is on the volume.
- The `claude` setup script (wired as the feature's `postStartCommand`) runs on every container start. It **does not clobber `~/.claude/CLAUDE.md`** — the user's own global instructions are preserved. Instead it writes feature rules to `~/.claude/devcontainer-rules.md` (overwritten each start so rebuilds propagate) and ensures `CLAUDE.md` carries a one-time `@devcontainer-rules.md` import line (create-if-missing, append-once, idempotent). The rules file is assembled from `config/rules-base.md` (package install, always) plus `config/rules-firewall.md` (appended only when the `firewall` feature is detected via `list-domains.sh` on `PATH`). It still **overwrites `~/.claude/statusline.sh`** from the image default, and merges `settings.json` preserving user customizations.
- **`gemini.skip_permissions`** (bool, default `false`) — sets `GEMINI_CLI_YOLO=true` in the `gemini` alias.
- **`antigravity.skip_permissions`** (bool, default `false`) — aliases `agy` with `--dangerously-skip-permissions`.
- **`codex.skip_permissions`** (bool, default `false`) — aliases `codex` with `--yolo`.
- The `codex` feature does **not** provision skills/plugins — users install them at runtime and they persist via two volume paths: `~/.codex` (auth, `config.toml`, plugin bundles) is mounted directly; `~/.agents` (USER-scope skills at `~/.agents/skills`, personal marketplaces at `~/.agents/plugins/marketplace.json`) is symlinked to `/dc-volumes/codex/agents`. Codex follows the symlink when scanning.
- **`buildkit`** — only the `buildctl` client is installed; `buildkitd` runs as a host sidecar. Keep client/daemon versions in sync.
- **`k8s` / `buildkit` / `go` versions** — `latest` is resolved without `api.github.com` (avoids unauthenticated rate limits): kubectl via `dl.k8s.io/release/stable.txt`, helm via `get.helm.sh/helm-latest-version`, kubectx and golangci-lint via the GitHub `/releases/latest` redirect, go via `go.dev/VERSION?m=text`. Go pins have no patch component on a minor's first release (`1.27`, not `1.27.0`).
- **`go`** — both installed tools go into the **image** (`/usr/local/go` + `/usr/local/bin`), never under `/dc-volumes/go`; see the volume-shadowing rule above. The volume carries `GOPATH` (module cache + the user's own `go install`s), `GOCACHE` and `GOLANGCI_LINT_CACHE` only. `gopls`/`dlv` aren't installed by the feature — the recommended `golang.go` extension installs them on demand into `gopath/bin` on the volume. `golangci-lint` uses upstream's install script (fetched from `HEAD`) rather than `go install`, which upstream advises against; `latest` is 2.x, and a repo on a v1 config must migrate or pin.

## Publishing

Features publish to GHCR via the official `devcontainers/action` in `.github/workflows/release.yml`. Tests run via `devcontainer features test` in `.github/workflows/test.yml`. Image path: `ghcr.io/TheDevOpsExperience/devcontainer-features/<feature>`.

The optional base image (`image/Dockerfile`) publishes separately via `.github/workflows/build-image.yml` — multi-arch (amd64 + arm64) buildx push to `ghcr.io/thedevopsexperience/tde-base` (GHCR paths are lowercase; the workflow lowercases the owner). Triggers on `main` pushes touching `image/**` and `workflow_dispatch`.

### Git release tags

Both workflows push a **git tag per release** (in addition to the OCI tags), so host-side scripts can pin to an exact revision — OCI tags only cover the artifact, but the host `hooks/` and the `devcontainer.json` template live in the repo, not the image. Both need `contents: write`.

| Source | Git tag | Version source | Driven by |
|---|---|---|---|
| Feature | `feature_<id>_<version>` | `.version` in `devcontainer-feature.json` | `devcontainers/action` auto-tags each published feature (`addRepoTagForPublishedTag`) |
| Base image | `tde-base-v<version>` | `ARG IMAGE_VERSION` in `image/Dockerfile` | `build-image.yml` after a successful push |

**Don't add a custom feature-tag step** — `devcontainers/action@v1` already tags every published feature `feature_<id>_<version>` (underscore-delimited, unconditional, no opt-out). It tags via the GitHub API, which is the real reason `release.yml` needs `contents: write` — under `contents: read` it fails with a silent warning and no tag. A hand-rolled step just produces a second, differently-named tag for the same release.

The base image has no equivalent auto-tag (`build-image.yml` uses buildx, not the action), so its `tde-base-v<version>` tag step is custom and **idempotent** — skips a tag already on the commit (rerun-safe). It additionally **fails the build** in an early "Validate version tag" step if `IMAGE_VERSION` is already tagged on a *different* commit (image changed but version wasn't bumped); a tag on the same commit is treated as a rerun and allowed. So **bump `IMAGE_VERSION` on every `image/**` change.**

Underscore tags resolve unambiguously on `raw.githubusercontent.com` (no slash in the ref). Consumers pin via these tags: a feature's host `on-init.sh` fetches each feature's host script at `feature_<id>_<version>` (see `examples/hooks/on-init.sh`), and the base image is pinned downstream by OCI tag (`tde-base:1.0.0`) or digest.
