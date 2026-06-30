## What it does

Installs the 1Password CLI (`op`) from the official apt repository and registers
the 1Password API domains with the `firewall` allowlist. Also ships the SA-token
host-init script (`host/on-init.sh`).

## Prerequisites

Requires the `core` feature.

## 1Password account setup (one-time)

This feature authenticates inside the container as a **service account**. Your
personal 1Password account holds the SA token; `host/on-init.sh` reads it on the
host and injects it as `OP_SERVICE_ACCOUNT_TOKEN`.

```
Host (your personal op account)
  └─ reads SA token from: op://Personal/<DEV VAULT SA>/password
       └─ writes to: .devcontainer/.init/devcontainer.env
            └─ mounted into container as: OP_SERVICE_ACCOUNT_TOKEN
                 └─ op CLI inside container authenticates as the service account
```

> **Account flag:** every `op` command needs `--account <shorthand>` when more
> than one account is signed in. Commands below use `$OP_ACCOUNT` — set it once
> (e.g. `export OP_ACCOUNT="my.1password.com"` in your shell profile).

### Step 0 — Find your account shorthand

```bash
op account list
```

The shorthand is the subdomain of the account URL (`my` in `my.1password.com`);
the full URL works too.

### Step 1 — Sign in

```bash
op signin --account "$OP_ACCOUNT"
```

### Step 2 — Create a vault for project secrets

A dedicated vault the service account can read; your personal items (the SA
token itself) stay separate.

```bash
op vault create <DEV VAULT> --account "$OP_ACCOUNT"
```

Store project secrets (API keys, cloud credentials) here — readable in the container
via `op read "op://<DEV VAULT>/<item>/<field>"`.

### Step 3 — Create a service account

> **Plan note:** the `op` CLI works on any 1Password plan, but **service
> accounts require 1Password Business or Teams** — they aren't available on
> Individual/Family accounts (neither via the web UI nor the CLI). On those
> plans you'll need a different auth method, which this feature doesn't cover.

Via the web UI: **1password.com → Developer → Service Accounts → New Service
Account**, grant **Read** on `<DEV VAULT>`, save, and copy the token (shown once).

Or via CLI:

```bash
TOKEN=$(op service-account create <DEV VAULT SA> --account "$OP_ACCOUNT" --vault <DEV VAULT>:read_items --expires-in=90d --raw)
# Copy the token immediately — it won't be shown again.
```

### Step 4 — Store the SA token in your personal vault

```bash
op item create \
    --account "$OP_ACCOUNT" \
    --category "API Credential" \
    --title <DEV VAULT SA> \
    --vault Personal \
    --tags service-account,dev \
    "password=${TOKEN}" \
    "validFrom=$(date '+%Y-%m-%d')" \
    "expires=$(date -v +90d '+%Y-%m-%d')"
```

Verify it's readable (this path becomes `OP_SA_ITEM_PATH` below):

```bash
op read "op://Personal/<DEV VAULT SA>/password" --account "$OP_ACCOUNT"
```

## Host initialisation

This feature ships `host/on-init.sh`, which reads a service account
token from 1Password and appends it to `devcontainer.env` as
`OP_SERVICE_ACCOUNT_TOKEN`. It expects `INIT_CONFIG_DIR` (path to `.init`,
created by the `core` feature's `host/on-init.sh`), `OP_ACCOUNT`, and
`OP_SA_ITEM_PATH` to be set before sourcing.

Add the following to `.devcontainer/hooks/on-init.sh` when using this feature,
fetching the script straight from this repo so you don't need to copy it. Pin
`FEATURES_REF` to a tag/commit for stability.

```bash
FEATURES_RAW_URL="https://raw.githubusercontent.com/TheDevOpsExperience/devcontainer-features"
FEATURES_REF="main"  # pin to a tag/commit for stability

OP_ACCOUNT="${OP_ACCOUNT:-my.1password.com}"
OP_SA_ITEM_PATH="${OP_SA_ITEM_PATH:-op://Private/devcontainer-sa/credential}"

# ── 1Password (1password feature) ────────────────────────────────────────────
source <(curl -fsSL "${FEATURES_RAW_URL}/${FEATURES_REF}/src/1password/host/on-init.sh")
```

If you're working in this repo itself (local feature paths), `on-init.sh`
already sources this script directly — no curl needed.
