## Prerequisites

Any apt-based image (Debian/Ubuntu). The feature is self-contained: it installs its baseline packages (`curl`, `wget`, `ca-certificates`, `git`, `jq`, `unzip`, `gpg`, `less`, `procps`, `sudo`, `zsh`, `openssh-client`), helper scripts with sudoers entries, Oh My Zsh (robbyrussell theme, git + fzf plugins) with zsh as login shell, profile.d sourcing for zsh, and `/dc-volumes/commandhistory` history persistence. Every step is idempotent — packages, Oh My Zsh, and shell wiring already provided by the base image are skipped.

An optional **cache image** (see `image/Dockerfile` in this repo) pre-bakes the slow parts (apt packages, plus comfort tools like `gh`, `fzf`, `yq`) so the feature install becomes a near no-op. It is never required.

Core's start-time work (SSH config, ownership fixes), attach-time `.init` cleanup, and create-time setup run via its own `postCreateCommand` / `postStartCommand` / `postAttachCommand` contributions — no hooks needed in the consuming project. Other features run after core because they declare `installsAfter: [core]`.

## Host initialisation

This feature ships `host/on-init.sh`, which:

- creates the `.init` scratch directory and locks down `devcontainer.env` (600)
  before other features append secrets to it. Required by every feature that
  writes to `.init`.
- generates a container-safe SSH config from your host config (only safe
  directives forwarded; public key files copied in, auth via the forwarded
  `SSH_AUTH_SOCK` agent — private keys never copied). Skip this part by setting
  `CORE_FORWARD_SSH=false` in `host.env`.

The script expects `INIT_CONFIG_DIR` (path to `.init`) to be set, and reads
`CORE_FORWARD_SSH` (default `true`) before sourcing.

Add the following near the top of `.devcontainer/hooks/on-init.sh`, fetching the
script straight from this repo so you don't need to copy it. Pin
`FEATURES_REF` to a tag/commit for stability.

```bash
FEATURES_RAW_URL="https://raw.githubusercontent.com/TheDevOpsExperience/devcontainer-features"
FEATURES_REF="main"  # pin to a tag/commit for stability

# ── Core (core feature) ──────────────────────────────────────────────────────
source <(curl -fsSL "${FEATURES_RAW_URL}/${FEATURES_REF}/src/core/host/on-init.sh")
```

If you're working in this repo itself (local feature paths), `on-init.sh`
already sources this script directly — no curl needed.

## SSH agent forwarding

- **VS Code Dev Containers**: forwards a running host SSH agent automatically
  (built-in "Sharing Git credentials") — nothing to configure; `git` over SSH
  just works.
- **`devcontainer` CLI / other clients**: add the mount + env in the consuming
  `devcontainer.json`, using the socket path valid for your host:

  ```jsonc
  // Docker Desktop (macOS/Windows)
  "containerEnv": { "SSH_AUTH_SOCK": "/run/host-services/ssh-auth.sock" },
  "mounts": [
    "source=/run/host-services/ssh-auth.sock,target=/run/host-services/ssh-auth.sock,type=bind"
  ]
  // Native Linux Docker: bind your host's $SSH_AUTH_SOCK instead.
  ```

## Secret env file (`--env-file` runArg)

Core's `host/on-init.sh` creates `.devcontainer/.init/devcontainer.env` (chmod 600); features like `1password` append secrets (e.g. the SA token) to it. Docker reads that file **once at container creation**, then core's `postAttachCommand` deletes the whole `.init/` directory — so the secret never lingers on disk.

For Docker to read it, the consuming `.devcontainer/devcontainer.json` must point `--env-file` at it. A feature **cannot** inject `runArgs` (not a Feature-spec property) and a bind mount would force the secret to persist (defeating the cleanup), so this one line stays consumer-side. Copy it in:

```jsonc
// devcontainer.json
"runArgs": [
  "--env-file", ".devcontainer/.init/devcontainer.env"
]
```

The flow, end to end: host `on-init.sh` writes `.init/devcontainer.env` → Docker bakes it into the container env via `--env-file` at create → core `attach.sh` (`postAttachCommand`) removes `.init/`. Only needed when a feature actually writes secrets to the file; harmless if the file is empty.

**Why `postAttachCommand`, not `postStartCommand`.** `host/on-init.sh` (`initializeCommand`) regenerates `.init/` on **every** open — including a plain *reconnect* to an already-running container. But `postStartCommand` runs only on real create/start, **not** on reconnect, so a reconnect would leave the regenerated `.init/` (secrets) orphaned. `postAttachCommand` fires on every attach (create, start, *and* reconnect) and runs *after* `postStartCommand`, so it cleans up in all cases. The workspace path is passed explicitly (`${containerWorkspaceFolder}`) — feature lifecycle hooks aren't guaranteed to run with the workspace as cwd. SSH setup stays in `postStartCommand` (a reconnect hits an already-configured container).

**Failed-start cleanup.** The `postAttachCommand` delete only runs when the container reaches the attach phase. If a build or start *fails earlier*, `.init/` (secrets included) is orphaned on the host — the devcontainer spec has no on-failure hook. Core handles this by wiping `.init/` at the **top of `host/on-init.sh`** (`initializeCommand`), which reruns on every start attempt: any orphan from a prior failed start is removed on the next one before the dir is recreated. A start that fails and is never retried leaves the orphan until the next initialize; the file stays `chmod 600` in the meantime.

## Idle-stop watchdog

`idle_stop` (bool, default `false`) starts a root watchdog (`idle-stop.sh`) that
**stops the container once VS Code has been disconnected for `idle_grace`
seconds** (default `120`), so nothing keeps running unattended. Unlike
devcontainer.json `shutdownAction` — which only fires on window *close* — this
also covers CLI-launched (`devcontainer up`) containers, because it signals
PID 1 itself.

Default is **off**: core is mandatory, so auto-stopping every consumer's
container would be surprising. Enable it per project:

```jsonc
// devcontainer.json
"features": {
  "ghcr.io/TheDevOpsExperience/devcontainer-features/core": { "idle_stop": true }
}
```

Liveness is a probe for an active VS Code IPC socket (listener via `ss`, else a
`socat` connect-probe, else a `pgrep` fallback) — **not** mere socket-file
presence, since stale socket files linger after disconnect. Activity is logged to
`/var/log/idle-stop.log`. Pair with `"shutdownAction": "stopContainer"` for the
clean window-close path. Note: a tight `idle_grace` can trip on laptop sleep or a
brief network blip — bump it if that bites.

## oh-my-zsh plugin registry

Core assembles the `.zshrc` `plugins=()` array from a drop-in registry at
container-create, so plugins can come from two sources without coupling:

- **Features** — a feature drops `/usr/local/share/devcontainer/zsh-plugins.d/<feature>.conf`
  (one bundled oh-my-zsh plugin name per line) in its `install.sh`. Installing the
  feature enables its plugin; no core config needed. (`k8s`, e.g., enables
  `kubectl`/`kubectx`/`helm`.)
- **You** — the `zsh_plugins` option (space-separated) adds your own:

```jsonc
// devcontainer.json
"features": {
  "ghcr.io/TheDevOpsExperience/devcontainer-features/core": { "zsh_plugins": "z you-should-use" }
}
```

Both are merged with the always-on `git`/`fzf` baseline, deduped, and written to
the array by `create.sh` — regenerated from the registry each create, so it's
idempotent across rebuilds. Only bundled oh-my-zsh plugins work (no separate
install; sourcing the shipped plugin file is what enables it).

## Prompt & interactive-zsh drop-ins

For live-zsh customization (prompt segments, keybinds, functions) core sources,
at the **end** of `.zshrc` (after oh-my-zsh and the theme), in three tiers:

1. **Features** — every `*.zsh` in `/usr/local/share/devcontainer/zshrc.d/`
   (baked at build). e.g. `k8s` adds an active-kube-context `PROMPT` segment.
2. **Project** — every `*.zsh` in your workspace's `.devcontainer/zshrc.d/`
   (committed, shared). Sourced live from the bind-mounted workspace, so edits
   show up in any new terminal — no rebuild.
3. **Personal** — `.devcontainer/zshrc.d/.overrides.zsh` (gitignored). Sourced
   **last**, so it wins.

Prompt ownership stays mostly clean:

- **Theme owns the left prompt** (`PROMPT`) — robbyrussell by default.
- **Features default to the right prompt** (`RPROMPT`), appending rather than
  replacing — `k8s` is the one documented exception, appending to the left
  `PROMPT` instead because the kube-context it shows is high-consequence
  (which cluster you're pointed at) and easy to miss on the right edge of a
  narrow terminal.
- **You win last** via project `*.zsh` (team) or `.overrides.zsh` (personal):
  set your own `PROMPT`/`RPROMPT`/theme there and it overrides everything, or
  silence one feature's segment with its opt-out env (e.g. `export K8S_HIDE_CONTEXT=1`).

See [`examples/zshrc.d/`](../../examples/zshrc.d/) for a starter layout. Note the
`commandhistory` volume holds **only** shell history (`.bash_history`,
`.zsh_history`) — shell config lives here, not on that volume.

## Credits

`install-package.sh` is adapted from [ilang/claude-code-dev-container](https://github.com/ilang/claude-code-dev-container) (MIT), which builds on Anthropic's [Claude Code devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer) (proprietary; credited for attribution only). See the repo [NOTICE](../../NOTICE) for full third-party licenses.
