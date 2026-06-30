## Prerequisites

Requires the `core` feature.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `skip_permissions` | boolean | `false` | Launch Claude Code with `--dangerously-skip-permissions` (baked into the `claude` zsh alias). Appropriate for sandboxed devcontainers where the `firewall` feature replaces Claude's permission system. |

## Plugins persist across rebuilds

The feature doesn't pre-install plugins — install them yourself with `claude plugin marketplace add <repo>` + `claude plugin install <plugin>@<marketplace>`. They land under `~/.claude` (the config dir, on the per-project volume), so they survive container rebuilds and restarts. Installing from a GitHub marketplace at runtime needs the host allowed per-session: `sudo allow-domain.sh github.com codeload.github.com`.

## Remote user

Works with any remote user. The config volume mounts at the user-neutral path `/dc-volumes/claude` (feature mounts can't reference the remote user); `CLAUDE_CONFIG_DIR` points there and `install.sh` symlinks `~/.claude` to it for the user detected via `_REMOTE_USER`.

## Your `CLAUDE.md` is preserved — feature rules merge via `@import`

This feature's `postStartCommand` (`lifecycle/setup.sh`) runs on **every container start**, not just create. It keeps your own global instructions and layers the devcontainer rules on top:

- **Feature rules live in `~/.claude/devcontainer-rules.md`**. This file is **overwritten** every start so image rebuilds propagate updates — don't edit it directly. Content adapts to which features are present:
  - Package-install guidance (`install-package.sh`, from `core`) is **always** included.
  - Firewall guidance (`list-domains.sh` / `allow-domain.sh`) is appended **only when the `firewall` feature is installed** (detected by its CLI on `PATH`). Without `firewall` the rules stay accurate — no references to tooling that isn't there.
- **`~/.claude/CLAUDE.md` is never clobbered.** The setup script just ensures it contains an `@devcontainer-rules.md` import line so the feature rules apply alongside your content:
  - No `CLAUDE.md` → one is created containing the import line.
  - `CLAUDE.md` exists without the import → the line is appended once (your content untouched).
  - Import already present → no-op.
  Bring your own `CLAUDE.md` freely; your instructions and the feature rules coexist.
- **Overwrites `~/.claude/statusline.sh`** with the image default every start (edits lost on next start, by design).
- **Merges** `settings.json`, preserving your customizations.
