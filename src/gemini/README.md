> **Transition note (2026-06-18):** Google is moving free / AI Pro / Ultra
> account-OAuth users of the Gemini CLI to the **Antigravity CLI**. This feature
> remains appropriate for **API-key** and **Code Assist Standard/Enterprise**
> auth. For account-based (paid Google account, no API key) auth, use the
> [`antigravity`](../antigravity) feature. Verify the transition against Google's
> official announcement.
>
> `gemini` and `antigravity` are **mutually exclusive** — enabling both fails the
> build (each guards on the other's install marker). Pick one.

## Prerequisites

Requires the `core` feature and Node.js in the base image (or add `ghcr.io/devcontainers/features/node` to your features).

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `skip_permissions` | boolean | `false` | Sets `GEMINI_CLI_YOLO=true` in the `gemini` zsh alias (skips confirmation prompts). Appropriate for sandboxed devcontainers. |

`NO_BROWSER=true` is always set in the `gemini` alias (no browser available in the container).

## Devcontainer rules merge into `GEMINI.md` (your file is preserved)

The feature's `postStartCommand` (`lifecycle/setup.sh`) runs on **every container start** and seeds the global Gemini memory with the sandbox rules **without clobbering your own `GEMINI.md`**:

- Feature rules live in `~/.gemini/devcontainer-rules.md`, **overwritten on every start** (so image rebuilds propagate updates) — don't edit it directly.
- `~/.gemini/GEMINI.md` is **never clobbered**. The script just ensures it imports the rules via Gemini's `@file.md` syntax (`@./devcontainer-rules.md`): created with the import line if missing, the line appended once if absent, no-op if already present. Bring your own `GEMINI.md` freely.
- Content adapts to installed features: package-install guidance (`install-package.sh`, from `core`) is always included; firewall guidance (`list-domains.sh`/`allow-domain.sh`) is appended **only when the `firewall` feature is present**.

## Remote user

Works with any remote user. The config volume mounts at the user-neutral path `/dc-volumes/gemini` (feature mounts can't reference the remote user); `install.sh` symlinks `~/.gemini` to it for the user detected via `_REMOTE_USER`.
