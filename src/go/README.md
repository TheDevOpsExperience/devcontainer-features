## Prerequisites

Requires the `core` feature.

## Tools installed

| Tool | Version option | Default | Install method |
|------|-----------------|---------|-----------------|
| `go` / `gofmt` | `go_version` | latest stable | official tarball |
| `golangci-lint` | `golangci_lint_version` | latest | official install script |

`golangci-lint` intentionally isn't installed via `go install` — upstream recommends against it (doesn't stamp version info / plugin replacements correctly); the official install script is used instead, pinned to a version resolved up front so it never has to call `api.github.com` itself.

Both tools are installed into the **image** (`/usr/local/go`, `/usr/local/bin`), never into the volume — see [GOPATH / cache persistence](#gopath--cache-persistence) for why that matters.

Pin for reproducible builds:

```json
"features": {
  "./features/go": {
    "go_version": "1.26.5",
    "golangci_lint_version": "2.12.2"
  }
}
```

Go's first release of a minor carries no patch component — pin `1.27`, not `1.27.0` (`go1.27.0` isn't a real download). `go_version: latest` is resolved via the official `https://go.dev/VERSION?m=text` endpoint; `golangci_lint_version: latest` via the GitHub `/releases/latest` redirect (no `api.github.com`, no unauthenticated rate-limit issues). Both `amd64` and `arm64` are supported.

**golangci-lint `latest` is now 2.x.** v2 changed the config format; a repo still on a v1 `.golangci.yml` should either migrate (`golangci-lint migrate`) or pin `golangci_lint_version` to its v1 release. The install script is always fetched from the repo's `HEAD`, so a v1 pin runs through the current script — it works, but it's not a combination upstream tests.

## Tools deliberately *not* installed: `gopls`, `dlv`

The language server and debugger install **on demand**, not at image build. The feature recommends the `golang.go` VS Code extension, which prompts to install any tool it's missing and does so with `go install` — landing them in `GOPATH/bin`, which is on the volume, so they persist across rebuilds. Outside VS Code, run the same commands yourself:

```bash
go install golang.org/x/tools/gopls@latest
go install github.com/go-delve/delve/cmd/dlv@latest
```

That needs only `proxy.golang.org`, which this feature already allowlists — the on-demand install works behind the firewall.

The tradeoff: the first Go file opened in a fresh project waits for the install. That's once per volume, not once per rebuild. In exchange, the editor owns the versions of the tools it already knows how to manage, and the feature stops carrying pins that can silently conflict with a pinned `go_version` (an old `go_version` plus a current `gopls` either fails the build or quietly triggers a `GOTOOLCHAIN` switch to compile it).

`golangci-lint` deliberately isn't treated this way: `go install` is the wrong install path for it, its install script needs GitHub hosts kept off the runtime allowlist on purpose, and its version wants to match CI — lint drift between container and CI produces false greens.

## GOPATH / cache persistence

`~/go` is symlinked to `gopath/` inside the `go-${localWorkspaceFolderBasename}` volume (mounted at `/dc-volumes/go`), same pattern as the `claude`/`gemini`/`codex`/`k8s` features. The volume holds two subdirs so caches don't clutter the GOPATH tree:

- `gopath/` — `GOPATH`: module cache (`pkg/mod`) and *your* `go install`ed binaries (`bin/`)
- `cache/build/` — `GOCACHE`: the Go build cache
- `cache/golangci-lint/` — `GOLANGCI_LINT_CACHE`: golangci-lint's own lint-result cache

All three (`GOPATH`, `GOCACHE`, `GOLANGCI_LINT_CACHE`) are `containerEnv`, pointing at the volume directly, so a cold `go mod download` / full rebuild / re-lint never happens just because the container was rebuilt. An existing `~/go` from the base image is copied into `gopath/` on first install, then replaced with the symlink. `/dc-volumes/go/gopath/bin` is added to `PATH` (spelled out rather than `$HOME/go/bin`, so root/`sudo` shells see it too).

**The feature's own tools are deliberately *not* on the volume.** `install.sh` runs at build time, when `/dc-volumes/go` is still an ordinary image directory; the named volume mounts over it at container create and seeds itself from the image only while it's empty. So a binary the feature installed under that path would be shadowed by any pre-existing volume — bumping `golangci_lint_version` and rebuilding would silently keep the old binary. The Go toolchain and `golangci-lint` therefore go to `/usr/local/go` and `/usr/local/bin`. Nothing changes for tools *you* install at runtime (including `gopls`/`dlv`): `GOPATH` is the volume then, so `go install` lands in `gopath/bin` and persists across rebuilds.

`gopath/bin` comes *before* `/usr/local/bin` on `PATH`, so a `go install`ed copy of a tool wins over the feature's — deliberate, but worth knowing if `golangci-lint --version` ever disagrees with `golangci_lint_version`.

## Shell / editor integration

Registers oh-my-zsh's bundled `golang` plugin (`go` completion + aliases) in `zsh-plugins.d/go.conf`; core merges it into the `.zshrc` `plugins=()` array at container-create.

Recommends the `golang.go` VS Code extension via `customizations.vscode.extensions` — it's what installs `gopls`/`dlv` on demand (see above).

## Usage in devcontainer.json

**This repo (local path):**
```json
"features": {
  "./features/go": {}
}
```

**Other repos (OCI URI):**
```json
"features": {
  "ghcr.io/your-org/features/go:1": {}
}
```

## Firewall

Registers `proxy.golang.org` and `sum.golang.org` — hit at runtime by `go get`/`go mod download`/`go build`/`go install` for any module not already cached, and by Go 1.21+'s `GOTOOLCHAIN` auto-download. `storage.googleapis.com` backs some proxy requests but is too broad for the always-on allowlist; allow it per-session with `allow-domain.sh` if a module download fails against it specifically.
