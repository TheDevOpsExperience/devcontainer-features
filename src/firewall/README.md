## Prerequisites

Requires the `core` feature. Installs `iptables`, `ipset`, `iproute2`, `dnsutils`, and `tcpdump` via `apt-get` — these are specialised system packages not provided by `core`.

## Capabilities

The feature declares `capAdd: [NET_ADMIN, NET_RAW]` in its `devcontainer-feature.json`, so the container gets the capabilities `iptables`/`ipset` (NET_ADMIN) and `tcpdump` (NET_RAW) need automatically. **You do not need `--cap-add` in `runArgs`** — adding the feature is enough. (Feature `capAdd` is merged into container creation and deduplicated, so a leftover `runArgs` entry is harmless but redundant.)

## Domain tiers

| Tier | Source | Lifetime |
|------|--------|----------|
| feature | `/usr/local/share/devcontainer/domains.d/*.conf` (registered at image build) | permanent |
| persistent | `<workspace>/.devcontainer/.firewall/allowed-domains.conf` | permanent (re-resolved on refresh) |
| session | `sudo allow-domain.sh <domain>` at runtime | temporary — cleared by the next periodic firewall refresh (every 30 min) or container restart, whichever comes first |

Session domains are temporary **by design**: the periodic refresh rebuilds the allowlist from the feature and persistent tiers only. To keep a domain, add it to `.firewall/allowed-domains.conf`.

For hosts-only names that DNS can't resolve (split-horizon names such as `metadata.google.internal`), pass the IP explicitly to bypass resolution and write the hosts entry directly: `sudo allow-domain.sh metadata.google.internal 169.254.169.254`.

Run `list-domains.sh` (no sudo) to see all allowed domains grouped by tier;
`list-domains.sh --json` emits machine-readable output (used by the Firewall
Monitor extension). Revoke a session grant early with
`sudo revoke-domain.sh <domain|ip|cidr>` — it drops the entry from the ipset and
`/etc/hosts` and logs `DOMAIN_REVOKED`/`IP_REVOKED` (session grants clear at the
next refresh regardless; revoke is for doing it immediately).

## Project firewall files

All project-specific firewall state lives in one bucket, `<workspace>/.devcontainer/.firewall/`:

| File | Purpose |
|------|---------|
| `allowed-domains.conf` | persistent allowlist (re-resolved on every refresh) |
| `ignored-domains.conf` | DNS-capture filter — domains/patterns (`*.example.com`) to omit from the capture log |

`.firewall/` holds **config only** (node-writable, host-persistent). The DNS
capture logs are **not** here — they live in `/var/log` (root-owned, so the
sandbox user can't tamper; reset on container rebuild):

| Log | Purpose |
|-----|---------|
| `/var/log/firewall-dns.log` | session log — every DNS attempt with a full timestamp; truncated on each start (drives the extension's count + last-seen) |
| `/var/log/firewall-dns-audit.log` | audit log — deduped, append-only first-seen per domain; survives stop/start within a build |
| `/var/log/firewall-changes.log` | allow/revoke events (`DOMAIN_ADDED` / `DOMAIN_REVOKED` / …) |

`list-attempts.sh` (no sudo; `--json` for machine output) aggregates the two DNS
logs into a deduplicated attempted/denied list. Since allowed domains resolve via
`/etc/hosts` (no DNS query), the captured set is effectively the denied/unknown
domains.

The setup scripts locate this dir via the workspace folder (lifecycle commands run with it as cwd), so any `workspaceFolder` works. `init-firewall.sh` records it in `/usr/local/share/devcontainer/firewall-dir`, and ad-hoc `list-domains.sh` / `capture-dns.sh` calls read it from there (overridable via `FIREWALL_DIR` env or argument).

## Firewall Monitor (VS Code extension)

Enabled by default (`install_extension`, set `false` to skip). Adds a **Firewall**
view to the activity bar:

- **Allowlist tree** grouped by tier (`session` / `persistent` / `feature`), from
  `list-domains.sh --json`. **Session** rows have an inline **revoke** button
  (`revoke-domain.sh`); **persistent** (project) rows have an inline **remove**
  button (drops the domain from `allowed-domains.conf` + refresh). Feature rows
  are build config — not editable here. The **Session** and **Persistent** group
  headers are always shown and carry an inline **+** button → enter a domain/IP to
  add it to that tier (session via `allow-domain.sh`, persistent via
  `allowed-domains.conf` + refresh).
- **Ignored list** — from `.firewall/ignored-domains.conf`. Per row: **stop
  ignoring** (remove the entry) and, for non-wildcard entries, **move to allowed**
  (un-ignore + add to the persistent allowlist + refresh).
- **Attempted / Denied list** — from `list-attempts.sh --json`: each captured
  domain with attempt count + last-seen, sorted by frequency. Inline actions per
  row: **ignore** (append `ignored-domains.conf`, exact or `*.parent`), **allow
  (persistent)** (append `allowed-domains.conf` + refresh), **allow (this
  session)** (`allow-domain.sh`).
- **Toasts** — watches `/var/log/firewall-changes.log`; when a domain is allowed
  at runtime it pops a warning with a one-click **Revoke**.
- **Open file** (title-bar button on every panel) — QuickPick to open the logs
  (`firewall-changes.log`, `firewall-dns.log`, `firewall-dns-audit.log`) or the
  project config (`allowed-domains.conf`, `ignored-domains.conf`).

The `.vsix` is built in CI and bundled inside the feature's OCI image;
`install.sh` copies it out at build time and `setup.sh` runs
`code --install-extension` on start. The extension is 1:1 coupled to the feature,
so it ships with it — no separate release or version to track. Every step is
non-fatal — if the copy or install fails, the firewall itself is unaffected. The extension needs no root; privileged actions go through the
sudoers-allowlisted scripts. This supersedes the manual "firewall log" task below
for most users.

## IPv6

The allowlist is IPv4-only. To prevent IPv6 from bypassing it, `init-firewall.sh` drops all IPv6 traffic (loopback excepted) via `ip6tables`. If the kernel has IPv6 disabled, the step is skipped.

## VS Code task — firewall log

Add to `.vscode/tasks.json` to tail the firewall change log in a dedicated panel on folder open:

```json
{
  "label": "Firewall log",
  "type": "shell",
  "command": "tail -f /var/log/firewall-changes.log",
  "isBackground": true,
  "presentation": {
    "reveal": "always",
    "panel": "dedicated",
    "label": "Firewall"
  },
  "runOptions": {
    "runOn": "folderOpen"
  }
}
```

## Credits

Adapted from [ilang/claude-code-dev-container](https://github.com/ilang/claude-code-dev-container) (MIT), which builds on Anthropic's [Claude Code devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer) — the original allowlist-firewall approach (Anthropic's work is proprietary; credited for attribution only). See the repo [NOTICE](../../NOTICE) for full third-party licenses.
