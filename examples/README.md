# Example consumer setup

A working starter for a project that consumes this feature collection. Copy these
files into your project's `.devcontainer/` and trim to what you need.

```
.devcontainer/
├── devcontainer.json     # features (GHCR URIs), base image, runArgs, ports
├── host.env              # host-side config (1Password account, BuildKit)
├── hooks/on-init.sh      # initializeCommand — runs on the host before build
├── .firewall/            # project firewall files (committed; log is gitignored)
│   ├── allowed-domains.conf   # extra firewall allowlist entries
│   └── ignored-domains.conf   # DNS-capture-log suppression
└── .gitignore            # excludes generated .init/ + .firewall/dns-domains.log
```

The example uses `"image": "ghcr.io/thedevopsexperience/tde-base:node24"` (an optional
build-cache base with Node pre-installed). Any apt-based image works — swap in
`mcr.microsoft.com/devcontainers/javascript-node:1-bookworm`, or replace `image`
with a `build.dockerfile` if you need project-specific layers.

## Steps

1. Copy this directory to `.devcontainer/` in your project.
2. In `devcontainer.json`, keep `core` (always required) plus the features you
   want; drop the rest. `gemini` and `antigravity` are mutually exclusive.
3. Edit `host.env` — set your `OP_ACCOUNT` / `OP_SA_ITEM_PATH` (or remove the
   1Password block from `hooks/on-init.sh` if you don't use it) and the BuildKit
   values (or remove that block).
4. Pin `FEATURES_REF` in `hooks/on-init.sh` to a tag/commit for reproducibility.
5. Keep the included `.gitignore` when you copy (it lands at
   `.devcontainer/.gitignore`). It excludes the generated `.init/` directory —
   which holds the secret `devcontainer.env` — and the
   `.firewall/dns-domains.log` capture file. Never commit those.

## Notes

- Features are referenced by published GHCR URIs; `core` installs first
  automatically (every feature declares `installsAfter: core`).
- The `image` base is an optional cache — any apt-based image works, but the
  npm-based features (`firebase`, `gemini`) need Node in the base.
- `firebase` emulators require a Java runtime — this example adds the official
  `ghcr.io/devcontainers/features/java` feature for that.
- See each feature's `src/<feature>/README.md` for options and host-init details.
