## What it does

Installs the gcloud CLI from Google's official apt repository (modern signed-by
keyring) and registers the Google Cloud control-plane domains with the
`firewall` allowlist.

## Prerequisites

Requires the `core` feature.

## Firestore emulator

This feature no longer bundles the standalone Cloud SDK Firestore emulator
(`google-cloud-cli-firestore-emulator`). For Firebase development, use the
`firebase` feature's Emulator Suite instead.

If you specifically need the Cloud SDK emulator (non-Firebase GCP apps), add it
yourself — e.g. in a custom Dockerfile or a `postCreateCommand`:

```bash
gcloud components install cloud-firestore-emulator
```
