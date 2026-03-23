#!/bin/bash
# ============================================================
# setup-server.sh — First-time setup on the deploy target host
# ============================================================
# Run this ONCE on the remote server before the first deploy.
# It creates the required directory structure and config files.
# ============================================================

set -euo pipefail

DATA_DIR="/opt/minecraft"

echo "=== Setting up Minecraft server directories ==="

sudo mkdir -p "$DATA_DIR/world"

# Create default config files if they don't exist
if [ ! -f "$DATA_DIR/server.properties" ]; then
  echo "Creating default server.properties..."
  cat > /tmp/server.properties <<'PROPS'
server-port=25565
gamemode=survival
difficulty=normal
max-players=20
view-distance=10
motd=A Minecraft Server deployed via GitHub Actions
enable-command-block=true
PROPS
  sudo mv /tmp/server.properties "$DATA_DIR/server.properties"
fi

if [ ! -f "$DATA_DIR/ops.json" ]; then
  echo '[]' | sudo tee "$DATA_DIR/ops.json" > /dev/null
fi

if [ ! -f "$DATA_DIR/whitelist.json" ]; then
  echo '[]' | sudo tee "$DATA_DIR/whitelist.json" > /dev/null
fi

sudo chown -R 1000:1000 "$DATA_DIR"

echo "=== Setup complete. Directory listing: ==="
ls -la "$DATA_DIR"
