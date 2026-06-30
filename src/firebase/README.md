## What it does

Installs `firebase-tools` via npm and registers the Firebase domains with the
`firewall` allowlist.

## Prerequisites

Requires the `core` feature and **Node.js** in the base image (or add
`ghcr.io/devcontainers/features/node`) — installs via npm.

The emulators (Firestore, Database, Pub/Sub) run on the **JVM**, so a Java
runtime is also required — add `ghcr.io/devcontainers/features/java` to your
features. The install fails fast if `npm` or `java` is missing.

## Ports

Firebase emulators use the following ports. Add to your `devcontainer.json`:

```json
"forwardPorts": [9099, 4000, 4400, 8080, 9199, 9150, 8085]
```

| Port | Emulator |
|------|----------|
| 4000 | Emulator Suite UI |
| 4400 | Emulator Hub |
| 8080 | Firestore |
| 8085 | Cloud Tasks |
| 9099 | Authentication |
| 9150 | Cloud Storage |
| 9199 | Storage |
