# Firewall Monitor

VS Code extension bundled with the `firewall` devcontainer feature. Adds a
**Firewall** container to the activity bar with three panels for inspecting and
managing the allowlist firewall — all without leaving the editor. The extension
never needs root: privileged actions go through the sudoers-allowlisted firewall
scripts, and config edits are written directly to the node-writable
`.devcontainer/.firewall/` dir.

## Panels

### Allowlist
Allowed domains from `list-domains.sh --json`, grouped by tier:

- **Session** — runtime grants (`allow-domain.sh`). Inline **revoke** per row.
- **Persistent** — the project allowlist (`.firewall/allowed-domains.conf`).
  Inline **remove** per row (drops it from the conf + refresh).
- **Feature** — domains registered by features at build time; nested by feature
  name (e.g. `claude`, `core`). Read-only (build config).

The **Session** and **Persistent** group headers are always shown and carry an
inline **+** button → enter a domain/IP/CIDR to add it to that tier.

### Attempted / Denied
Undecided-denied **inbox**: deduplicated DNS lookups the sandboxed user
attempted, from `list-attempts.sh --json` — each with attempt count + last-seen,
sorted by frequency. (Allowed domains resolve via `/etc/hosts` without a DNS
query, so the captured set is effectively the denied/unknown domains.) A domain
**drops out of this list once resolved** either way — allowed (now in the live
allowlist → **Allowlist** view) or ignored (→ **Ignored** view). Inline actions
per row:

- **ignore** — append to `ignored-domains.conf` (choose exact or `*.parent`).
- **allow (persistent)** — append to `allowed-domains.conf` + refresh.
- **allow (this session)** — `allow-domain.sh`.

### Ignored
Entries from `.firewall/ignored-domains.conf`. Inline actions per row:

- **stop ignoring** — remove the entry (works for exact and `*.wildcard`).
- **move to allowed** — un-ignore + add to the persistent allowlist + refresh
  (offered for non-wildcard entries only; a `*.x` can't resolve into the
  allowlist).

## Other actions

- **Toasts** — watches `/var/log/firewall-changes.log`; when a domain is allowed
  at runtime, pops a warning with a one-click **Revoke**.
- **Open file** (title-bar button on every panel) — QuickPick to open the logs
  (`firewall-changes.log`, `firewall-dns.log`, `firewall-dns-audit.log`) or the
  project config (`allowed-domains.conf`, `ignored-domains.conf`).
- **Refresh** (title-bar button per panel). Panels also auto-refresh when the
  relevant log / config file changes.

## Backing scripts (provided by the `firewall` feature)

| Action | Script |
|--------|--------|
| List allowlist | `list-domains.sh --json` (no sudo) |
| List attempts | `list-attempts.sh --json` (no sudo) |
| Allow (session) | `sudo allow-domain.sh <domain>` |
| Revoke (session) | `sudo revoke-domain.sh <domain>` |
| Allow / remove (persistent) | edit `allowed-domains.conf` + `sudo refresh-firewall.sh` |
| Ignore / un-ignore | edit `ignored-domains.conf` (no sudo) |

## Build

```bash
npm i -g @vscode/vsce
vsce package --allow-missing-repository --skip-license   # → firewall-monitor-<version>.vsix
```

Built automatically by the feature release workflow when the `firewall` feature
publishes: the "Bundle firewall extension" step runs `vsce package` and drops the
`.vsix` into the staged feature dir, so it ships INSIDE the feature's OCI image.
The feature's `install.sh` copies it out at build time and `setup.sh` runs
`code --install-extension` on container start when `install_extension` is enabled.
Every step is non-fatal. (Locally `*.vsix` is gitignored and not built, so the
extension is simply skipped during `devcontainer features test`.)

### Versioning

The extension is **1:1 coupled to the feature** — it ships inside the feature
artifact and has no standalone distribution, so there is no version to track or
sync. `package.json` `version` exists only because `vsce package` requires a
value; it isn't a pin and doesn't need bumping in lockstep with the feature.

- To ship a new extension build: change the extension **and** bump
  `firewall/devcontainer-feature.json` (which is what triggers a feature publish,
  which rebuilds and re-bundles the `.vsix`).
- A container picks up a new build on **rebuild** (install re-copies the bundled
  `.vsix`; `setup.sh` reinstalls with `--force`).
