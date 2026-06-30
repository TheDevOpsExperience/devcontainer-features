## What it does

Installs the official **Google Antigravity CLI** (`agy`) — Google's native
terminal coding agent — using the upstream bootstrapper
(`https://antigravity.google/cli/install.sh`). The SHA512-verified native binary
lands in `~/.local/bin/agy` (added to `PATH` via `/etc/profile.d`). No Node.js
required.

It also registers the CLI's background self-update hosts with the `firewall`
allowlist.

## Prerequisites

Requires the `core` feature. Works on any apt-based image (no Node needed).

`antigravity` and `gemini` are **mutually exclusive** — enabling both fails the
build (each guards on the other's install marker). Pick one.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `skip_permissions` | boolean | `false` | Aliases `agy` with `--dangerously-skip-permissions` (skips confirmation prompts). Appropriate for sandboxed devcontainers where the firewall replaces the permission system. |

## Why this exists (Gemini CLI → Antigravity)

Google is moving free / AI Pro / Ultra (account-OAuth) users of the Gemini CLI
to the Antigravity CLI (announced for **2026-06-18**). Use this feature for
**account-based** (paid Google account, no API key) authentication. The
`gemini` feature stays for API-key / Code Assist Standard/Enterprise users.

> Verify the current state of this transition against Google's official
> announcement before relying on it — early reporting was mixed.

## Authentication (headless / container)

The CLI is SSH/remote-aware: it detects a headless session and prints an auth
URL to open in your **host** browser, then completes the flow back to the
container. Sign in with your paid Google account — no API key.

## Firewall domains

Registered at install (runtime self-update):

- `antigravity-cli-auto-updater-974169037036.us-central1.run.app` — update manifest
- `storage.googleapis.com` — update binary downloads (public GCS bucket)

**Not yet captured:** the inference + account-auth endpoints are baked into the
binary. On first `agy` run, watch the firewall reject log for blocked hosts
(expect `oauth2.googleapis.com` plus a Gemini/Code Assist backend) and allow
them — persistently in your `.firewall/allowed-domains.conf` / a `domains.d` file, or
per-session with `allow-domain.sh`. Please open an issue with what you observe
so this list can be made exact.

## Devcontainer rules merge into `AGENTS.md` (your file is preserved)

The feature's `postStartCommand` (`lifecycle/setup.sh`) runs on **every container start** and seeds Antigravity's global instructions with the sandbox rules **without clobbering your own `AGENTS.md`**. Antigravity reads `~/.gemini/antigravity/AGENTS.md` and supports import directives, so:

- Feature rules live in `~/.gemini/antigravity/devcontainer-rules.md`, **overwritten on every start** (so image rebuilds propagate updates) — don't edit it directly.
- `~/.gemini/antigravity/AGENTS.md` is **never clobbered**. The script just ensures it imports the rules via `@./devcontainer-rules.md`: created with the import line if missing, the line appended once if absent, no-op if already present. Bring your own `AGENTS.md` freely.
- Content adapts to installed features: package-install guidance (`install-package.sh`, from `core`) is always included; firewall guidance (`list-domains.sh`/`allow-domain.sh`) is appended **only when the `firewall` feature is present**.

(Both `~/.gemini/antigravity/AGENTS.md` and the config dir `~/.gemini/antigravity-cli` sit under the shared `~/.gemini` volume, so they persist.)

## Config persistence

The CLI stores its config/credentials under `~/.gemini/antigravity-cli` — i.e.
inside `~/.gemini`, the Gemini CLI's directory. This feature symlinks the whole
`~/.gemini` to a Docker volume (`gemini-<project>` → `/dc-volumes/gemini`) so
login survives rebuilds. The volume is **shared with the `gemini` feature** —
the two are mutually exclusive, so only one writes it, and migrating
`gemini`→`antigravity` keeps your existing login (same `~/.gemini`).

## Known gaps (v0.1.0)

- The CLI **self-updates in the background**; builds are therefore not fully
  pinned.
