# ============================================================
# Minecraft Server - CI/CD Build & Deploy Pipeline
# ============================================================
# This GitHub Actions workflow automates the full lifecycle of
# the Minecraft server:
#   1. BUILD    — Download the latest Minecraft server jar
#   2. TEST     — Verify the jar was downloaded successfully
#   3. PUBLISH  — Upload the build artifact to GitHub
#   4. DEPLOY   — SSH into solace.rit.edu, transfer the jar,
#                 and set up the server to run
#
# Trigger: Push to 'main' branch or manual dispatch.
#
# Required GitHub Secrets:
#   SOLACE_SSH_KEY — Private SSH key for solace.rit.edu
# ============================================================

name: Minecraft Server - Build & Deploy

on:
  push:
    branches: [main]
  workflow_dispatch:              # Allow manual runs from the Actions tab

env:
  DEPLOY_HOST: solace.rit.edu
  DEPLOY_USER: ds6953
  DEPLOY_DIR: ~/minecraft-server
  SERVER_PORT: 25565

jobs:
  # -------------------------------------------------------
  # Job 1: BUILD — Download the latest Minecraft server jar,
  #         verify it, and upload as a build artifact.
  # -------------------------------------------------------
  build:
    name: Build (Download Server Jar)
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Download latest Minecraft server jar
        run: |
          echo "=== Downloading latest Minecraft server jar ==="
          chmod +x latest_mc.sh
          ./latest_mc.sh server.jar
          ls -lh server.jar

      - name: Verify jar file is valid
        run: |
          echo "=== Verifying server.jar ==="
          FILE_TYPE=$(file server.jar)
          echo "$FILE_TYPE"
          if echo "$FILE_TYPE" | grep -q "Java archive"; then
            echo "Verification PASSED — valid Java archive."
          else
            echo "::error::server.jar is not a valid Java archive."
            exit 1
          fi
          JAR_SIZE=$(stat --format=%s server.jar)
          echo "File size: $JAR_SIZE bytes"
          if [ "$JAR_SIZE" -lt 1000000 ]; then
            echo "::error::server.jar is suspiciously small (< 1MB). Download may have failed."
            exit 1
          fi
          echo "Size check PASSED."

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: minecraft-server-jar
          path: server.jar
          retention-days: 30

      - name: Build summary
        run: |
          echo "### Build Summary" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Artifact:** server.jar" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Size:** $(du -h server.jar | cut -f1)" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Verification:** Passed (valid Java archive)" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Commit:** $(git rev-parse --short HEAD)" >> "$GITHUB_STEP_SUMMARY"

  # -------------------------------------------------------
  # Job 2: DEPLOY — SSH into solace.rit.edu, transfer the
  #         server jar, configure the server, and start it.
  # -------------------------------------------------------
  deploy:
    name: Deploy to Solace (solace.rit.edu)
    needs: build
    runs-on: ubuntu-latest

    if: github.ref == 'refs/heads/main'

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Download build artifact
        uses: actions/download-artifact@v4
        with:
          name: minecraft-server-jar

      - name: Set up SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SOLACE_SSH_KEY }}" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          ssh-keyscan -H ${{ env.DEPLOY_HOST }} >> ~/.ssh/known_hosts 2>/dev/null

      - name: Create server directory on Solace
        run: |
          echo "=== Setting up directory structure on Solace ==="
          ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=no \
            ${{ env.DEPLOY_USER }}@${{ env.DEPLOY_HOST }} << 'REMOTE_SETUP'
          mkdir -p ~/minecraft-server/backups
          mkdir -p ~/minecraft-server/world

          # Create eula.txt (required by Minecraft)
          echo "eula=true" > ~/minecraft-server/eula.txt

          # Create server.properties if it doesn't exist
          if [ ! -f ~/minecraft-server/server.properties ]; then
            cat > ~/minecraft-server/server.properties << 'PROPS'
          server-port=25565
          gamemode=survival
          difficulty=normal
          max-players=20
          view-distance=10
          motd=Minecraft Server - Deployed via CI/CD
          enable-command-block=true
          PROPS
          fi

          # Create empty ops/whitelist if they don't exist
          [ -f ~/minecraft-server/ops.json ] || echo '[]' > ~/minecraft-server/ops.json
          [ -f ~/minecraft-server/whitelist.json ] || echo '[]' > ~/minecraft-server/whitelist.json

          echo "Directory setup complete."
          ls -la ~/minecraft-server/
          REMOTE_SETUP

      - name: Backup existing server jar (if any)
        run: |
          echo "=== Backing up previous server.jar ==="
          ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=no \
            ${{ env.DEPLOY_USER }}@${{ env.DEPLOY_HOST }} << 'REMOTE_BACKUP'
          if [ -f ~/minecraft-server/server.jar ]; then
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            cp ~/minecraft-server/server.jar ~/minecraft-server/backups/server_${TIMESTAMP}.jar
            echo "Backed up to backups/server_${TIMESTAMP}.jar"
            # Keep only the 5 most recent backups
            ls -t ~/minecraft-server/backups/server_*.jar | tail -n +6 | xargs rm -f 2>/dev/null
            echo "Backup rotation complete."
          else
            echo "No existing server.jar to back up."
          fi
          REMOTE_BACKUP

      - name: Transfer server jar to Solace
        run: |
          echo "=== Uploading server.jar to Solace ==="
          scp -i ~/.ssh/deploy_key -o StrictHostKeyChecking=no \
            server.jar ${{ env.DEPLOY_USER }}@${{ env.DEPLOY_HOST }}:~/minecraft-server/server.jar
          echo "Transfer complete."

      - name: Deploy — Stop old server and start new one
        run: |
          echo "=== Deploying on Solace ==="
          ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=no \
            ${{ env.DEPLOY_USER }}@${{ env.DEPLOY_HOST }} << 'REMOTE_DEPLOY'
          cd ~/minecraft-server

          # Stop existing server if running
          if [ -f server.pid ]; then
            OLD_PID=$(cat server.pid)
            if kill -0 "$OLD_PID" 2>/dev/null; then
              echo "Stopping existing server (PID $OLD_PID)..."
              kill "$OLD_PID"
              sleep 5
              # Force kill if still running
              kill -0 "$OLD_PID" 2>/dev/null && kill -9 "$OLD_PID"
              echo "Old server stopped."
            fi
            rm -f server.pid
          fi

          # Start the new server in the background
          echo "Starting Minecraft server..."
          nohup java -Xms512M -Xmx1024M -jar server.jar nogui \
            > server.log 2>&1 &
          echo $! > server.pid
          NEW_PID=$(cat server.pid)
          echo "Server started with PID $NEW_PID"

          # Wait and verify the process is still running
          sleep 10
          if kill -0 "$NEW_PID" 2>/dev/null; then
            echo "========================================="
            echo "  DEPLOY SUCCESSFUL"
            echo "  Host: solace.rit.edu"
            echo "  PID:  $NEW_PID"
            echo "  Dir:  ~/minecraft-server"
            echo "  Log:  ~/minecraft-server/server.log"
            echo "========================================="
            echo ""
            echo "=== Last 15 lines of server log ==="
            tail -15 server.log
          else
            echo "::error::Server process died within 10 seconds."
            echo "=== Server log ==="
            cat server.log
            exit 1
          fi
          REMOTE_DEPLOY

      - name: Deploy summary
        run: |
          echo "### Deploy Summary" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Target:** ${{ env.DEPLOY_USER }}@${{ env.DEPLOY_HOST }}" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Directory:** ~/minecraft-server" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Status:** Deployed and verified running" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Commit:** $(git rev-parse --short HEAD)" >> "$GITHUB_STEP_SUMMARY"

      - name: Clean up SSH key
        if: always()
        run: rm -f ~/.ssh/deploy_key
