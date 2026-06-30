# Codex CLI

Installs the [OpenAI Codex CLI](https://github.com/openai/codex) (`codex`) via the official bootstrapper (`https://chatgpt.com/codex/install.sh`) — a native binary, **no Node required** — and registers its runtime domains with the `firewall` feature.

Auth is either a ChatGPT account (browser OAuth, opened on the host) or an `OPENAI_API_KEY`. Config and the installed binary both live under `~/.codex`, persisted on a per-project volume, so login and the install survive rebuilds.

## Prerequisites

Requires the `core` feature. Works on any apt-based image (Debian/Ubuntu) — no Node needed.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `skip_permissions` | boolean | `false` | Aliases `codex` with `--yolo` (skips approval prompts and the built-in sandbox). Appropriate for sandboxed devcontainers where the firewall replaces the permission system. |

## Skills & plugins persist across rebuilds

The feature doesn't pre-install any skills or plugins — you install them yourself ([Agent Skills](https://developers.openai.com/codex/skills) via `$skill-installer`, [plugins](https://developers.openai.com/codex/plugins) via `/plugins` or `codex plugin marketplace add`). Everything you install survives container rebuilds and restarts, because both of Codex's state locations are kept on the per-project volume:

- `~/.codex` — auth, `config.toml`, the CLI binary, and installed plugin bundles (`~/.codex/plugins/`) — mounted directly.
- `~/.agents` — your USER-scope skills (`~/.agents/skills/`) and personal plugin marketplaces (`~/.agents/plugins/marketplace.json`) — symlinked to the same volume (`install.sh` points `~/.agents` at `/dc-volumes/codex/agents`; Codex follows the symlink when scanning).

Installing skills/plugins at runtime clones from GitHub, so allow it per-session: `sudo allow-domain.sh github.com codeload.github.com`.

## Devcontainer rules merge into `AGENTS.md` (your file is preserved)

The feature's `postStartCommand` (`lifecycle/setup.sh`) runs on **every container start** and adds the sandbox rules to the global `~/.codex/AGENTS.md` **without clobbering your own instructions**. Codex has no file-import syntax (it concatenates instruction files), so the rules live in a marker-delimited managed block:

```
<!-- BEGIN devcontainer-rules (managed — do not edit) -->
...feature rules...
<!-- END devcontainer-rules (managed) -->
```

- The managed block is **rewritten on every start** (so image rebuilds propagate updates); everything outside the markers — your own content — is preserved. If `AGENTS.md` doesn't exist it's created with just the block; if it exists without the block, the block is appended.
- Content adapts to installed features: package-install guidance (`install-package.sh`, from `core`) is always included; firewall guidance (`list-domains.sh`/`allow-domain.sh`) is appended **only when the `firewall` feature is present**.
- **Caveat:** a user-provided `~/.codex/AGENTS.override.md` takes precedence over `AGENTS.md` at the global scope (Codex reads the override *instead of* `AGENTS.md`), so the rules won't apply if you use a global override file.

## Remote user

Works with any remote user. The config volume mounts at the user-neutral path `/dc-volumes/codex` (feature mounts can't reference the remote user); `install.sh` symlinks `~/.codex` to it (and `~/.agents` to `/dc-volumes/codex/agents`) for the user detected via `_REMOTE_USER`.

## Firewall domains

Registered in `/usr/local/share/devcontainer/domains.d/codex.conf` (allowlisted at container start by the `firewall` feature):

- `api.openai.com` — Responses API (API-key auth)
- `chatgpt.com` — backend-api (ChatGPT-account auth)
- `auth.openai.com` — in-container token refresh

The OAuth consent page opens in the host browser, so it isn't allowlisted here. Add more per-session with `allow-domain.sh` if a workflow needs them.
