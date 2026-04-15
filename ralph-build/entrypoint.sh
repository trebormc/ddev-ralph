#!/bin/bash
#ddev-generated

# =============================================================================
# Ralph DDEV Entrypoint
# =============================================================================

# --- Fix Docker socket access if needed ---
# On Linux, the socket GID may not match the container's docker group.
# On macOS/Windows Docker Desktop, the socket is already accessible — this is skipped.
if [ -z "$_DOCKER_GROUP_FIXED" ] && [ -S /var/run/docker.sock ] && ! docker info > /dev/null 2>&1; then
  SOCK_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "")
  if [ -n "$SOCK_GID" ] && [ "$SOCK_GID" != "0" ]; then
    sudo groupadd -g "$SOCK_GID" docker-host 2>/dev/null || true
    sudo usermod -aG docker-host "$(whoami)" 2>/dev/null || true
    export _DOCKER_GROUP_FIXED=1
    # Use newgrp via sg to pick up the new group. If sg fails, continue without it.
    sg docker-host -c "export _DOCKER_GROUP_FIXED=1; $0 $*" && exit 0 || true
  fi
fi

exec "$@"
