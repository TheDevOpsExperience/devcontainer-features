#!/bin/bash
# init-workspace.sh — creates the .init scratch directory, locks down the
# secrets file before anything appends to it, and (optionally) generates a
# container-safe SSH config from the host config. Runs on the HOST (called
# from on-init.sh).
#
# SSH config: only safe directives are forwarded; public key files are copied
# in. Auth is handled by the forwarded SSH agent (SSH_AUTH_SOCK) — private
# keys stay on the host. IdentityFile can point to either the private key
# (id_ed25519) or the public key (id_ed25519.pub); in both cases the adjacent
# .pub file is copied in.
#
# Required env vars:
#   INIT_CONFIG_DIR  - path to the .init directory
# Optional env vars:
#   CORE_FORWARD_SSH - "true" (default) to generate the SSH config, "false" to skip
set -e

# Start from a clean slate. .init is regenerated scratch (secrets + SSH config);
# the container deletes it at postStart once the start succeeds. If a previous
# start *failed* before that cleanup ran, an orphaned .init — including the
# chmod-600 devcontainer.env secrets — is left on the host. initializeCommand
# (this script) runs on every start attempt, so wiping here removes any such
# orphan on the next start before recreating. Safe: nothing else owns this dir.
rm -rf "${INIT_CONFIG_DIR}"

mkdir -p "${INIT_CONFIG_DIR}"

# Secrets land in devcontainer.env — lock it down before anything appends.
touch "${INIT_CONFIG_DIR}/devcontainer.env"
chmod 600 "${INIT_CONFIG_DIR}/devcontainer.env"

if [ "${CORE_FORWARD_SSH:-true}" = "true" ] && [ -f "$HOME/.ssh/config" ]; then
  mkdir -p "${INIT_CONFIG_DIR}/ssh-keys"
  while IFS= read -r line; do
    if [[ "$line" =~ ^([[:space:]]*IdentityFile[[:space:]]+)(.+)$ ]]; then
      key_path="${BASH_REMATCH[2]}"
      key_path="${key_path/#\~/$HOME}"
      if [[ "$key_path" == *.pub ]]; then
        pub_key_path="$key_path"
      else
        pub_key_path="${key_path}.pub"
      fi
      if [ ! -f "$pub_key_path" ]; then
        echo "  Warning: public key not found: $pub_key_path (skipping IdentityFile)" >&2
      elif ! grep -qE '^(ssh|ecdsa|sk-ssh|sk-ecdsa)-' "$pub_key_path" 2>/dev/null; then
        echo "  Warning: $pub_key_path does not look like a valid public key (skipping IdentityFile)" >&2
      else
        key_filename=$(basename "$pub_key_path")
        cp "$pub_key_path" "${INIT_CONFIG_DIR}/ssh-keys/"
        echo "${BASH_REMATCH[1]}~/.ssh/${key_filename}"
      fi
    else
      echo "$line"
    fi
  done < <(grep -E '^\s*(Host\b|HostName\b|User\b|Port\b|ProxyJump\b|ProxyCommand\b|ForwardAgent\b|ServerAliveInterval\b|ServerAliveCountMax\b|ConnectTimeout\b|StrictHostKeyChecking\b|IdentityFile\b|#|[[:space:]]*$)' \
    "$HOME/.ssh/config") > "${INIT_CONFIG_DIR}/generated-ssh-config"
fi
