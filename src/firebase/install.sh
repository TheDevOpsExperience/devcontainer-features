#!/bin/bash
set -e

if [ ! -f /usr/local/share/devcontainer/.core-installed ]; then
    echo "ERROR: The 'core' feature must be installed before this feature." >&2; exit 1
fi

if ! command -v npm > /dev/null 2>&1; then
    echo "ERROR: 'npm' not found. This feature requires Node.js in the base image." >&2
    echo "       Add 'ghcr.io/devcontainers/features/node' to your devcontainer.json features." >&2
    exit 1
fi

# The Firebase emulators (Firestore, Database, Pub/Sub) run on the JVM.
if ! command -v java > /dev/null 2>&1; then
    echo "ERROR: 'java' not found. The Firebase emulators require a Java runtime." >&2
    echo "       Add 'ghcr.io/devcontainers/features/java' to your devcontainer.json features." >&2
    exit 1
fi

npm install -g firebase-tools

# Domains — runtime only. The CLI install (npm) and the OAuth consent page (host
# browser) are not in this list; the emulator binaries download from
# storage.googleapis.com on first start.
mkdir -p /usr/local/share/devcontainer/domains.d
cat > /usr/local/share/devcontainer/domains.d/firebase.conf << 'EOF'
firebase.googleapis.com
firestore.googleapis.com
firebaseio.com
firebaseapp.com
cloudfunctions.googleapis.com
run.googleapis.com
identitytoolkit.googleapis.com
securetoken.googleapis.com
fcm.googleapis.com
firebaseinstallations.googleapis.com
storage.googleapis.com
oauth2.googleapis.com
www.googleapis.com
EOF
