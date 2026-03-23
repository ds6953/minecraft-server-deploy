# Minecraft Server — Automated CI/CD Deployment to Solace

## Overview

This project wraps the [rocnick/minecraft-server](https://github.com/rocnick/minecraft-server) Minecraft server with a fully automated **GitHub Actions** CI/CD pipeline that builds and deploys to **solace.rit.edu** via SSH. On every push to `main`, the pipeline:

1. Downloads the latest Minecraft server jar
2. Verifies the jar is a valid Java archive
3. SSHs into solace.rit.edu, backs up the old jar, transfers the new one
4. Stops the old server process and starts the new one

## Architecture

```
Developer pushes to main
        |
        v
+------------------------------+
|  Job 1: BUILD                |
|  (GitHub Actions Runner)     |
|                              |
|  1. Checkout repo            |
|  2. Run latest_mc.sh to      |
|     download server jar      |
|  3. Verify jar is valid      |
|  4. Upload as build artifact |
+--------------+---------------+
               | on success
               v
+------------------------------+
|  Job 2: DEPLOY               |
|  (SSH to solace.rit.edu)     |
|                              |
|  1. Download build artifact  |
|  2. SSH: create directories  |
|  3. SSH: backup old jar      |
|  4. SCP: transfer new jar    |
|  5. SSH: stop old server     |
|  6. SSH: start new server    |
|  7. SSH: verify running      |
+--------------+---------------+
               |
               v
      solace.rit.edu
      ~/minecraft-server/
        server.jar (running)
```

## Deployment Concepts Used

This implementation applies several deployment best practices from the Week 7 lecture:

**Branch Deployment** — Pull requests trigger a separate workflow (branch-deploy.yml) that builds and tests the branch before it gets merged. If something breaks, the main branch can always be redeployed cleanly.

**Blue-Green / Rollback Support** — Every deploy backs up the previous server.jar with a timestamp. Rolling back is one command using rollback.sh, which restores the previous jar and restarts. This provides near-instant recovery.

**Audit Trail** — GitHub Actions logs provide a complete record of who pushed, what changed, when it built, and whether the deploy succeeded. Build artifacts are retained for 30 days.

**Deploy Locking** — GitHub Actions serializes workflow runs on the same branch, preventing concurrent deploys from conflicting with each other.

**Permissions** — GitHub repository settings control who can push to main (and trigger a production deploy). Branch protection rules can require PR reviews before merging. The SSH key is stored as a GitHub Secret, restricting deploy access.

## Repository Structure

```
.
+-- .github/
|   +-- workflows/
|       +-- build-and-deploy.yml   # Main CI/CD pipeline (push to main)
|       +-- branch-deploy.yml      # PR build and test (branch deploys)
+-- scripts/
|   +-- rollback.sh                # Quick rollback to a previous jar backup
|   +-- setup-server.sh            # First-time remote host setup
+-- Dockerfile                     # Standard Docker build (local use)
+-- Dockerfile.builder             # Multi-stage Docker build (local use)
+-- docker-compose.yml             # Docker Compose config (local use)
+-- build.sh                       # Original local build script
+-- latest_mc.sh                   # Downloads the latest Minecraft server jar
+-- DEPLOY_README.md               # This file
```

## Prerequisites

1. A GitHub repository with this code pushed to it
2. SSH key access from GitHub Actions to solace.rit.edu
3. Java installed on Solace (available by default on RIT servers)

## Setup Instructions

### Step 1: Generate an SSH Key Pair

On your local machine, generate a key specifically for GitHub Actions:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/gh_solace_deploy
```

This creates two files:
- ~/.ssh/gh_solace_deploy (private key — goes into GitHub)
- ~/.ssh/gh_solace_deploy.pub (public key — goes onto Solace)

### Step 2: Add the Public Key to Solace

```bash
ssh ds6953@solace.rit.edu 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
cat ~/.ssh/gh_solace_deploy.pub | ssh ds6953@solace.rit.edu 'cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Test that it works:
```bash
ssh -i ~/.ssh/gh_solace_deploy ds6953@solace.rit.edu 'echo "SSH key works"'
```

### Step 3: Add the Private Key to GitHub Secrets

1. Go to your GitHub repo: Settings -> Secrets and variables -> Actions
2. Click "New repository secret"
3. Name: SOLACE_SSH_KEY
4. Value: Paste the entire contents of ~/.ssh/gh_solace_deploy (the private key)
5. Click "Add secret"

### Step 4: Push and Deploy

Push to main to trigger the pipeline:

```bash
git add -A
git commit -m "Add CI/CD deployment pipeline"
git push origin main
```

Go to the Actions tab in your GitHub repo to watch the pipeline run. You will see the Build job download and verify the jar, then the Deploy job SSH into Solace and start the server.

### Step 5: Verify on Solace

SSH into Solace and check:

```bash
ssh ds6953@solace.rit.edu
cat ~/minecraft-server/server.pid        # Shows the running process ID
tail -20 ~/minecraft-server/server.log   # Shows server output
```

### Step 6: Rollback (if needed)

If a deploy causes issues, restore the previous version:

```bash
ssh ds6953@solace.rit.edu 'bash ~/minecraft-server/scripts/rollback.sh'
```

## Workflow Details

### build-and-deploy.yml (Production Pipeline)

**Trigger:** Push to main or manual dispatch from the Actions tab.

**Build Job:** Checks out the repo, runs latest_mc.sh to download the current Minecraft server jar, verifies it is a valid Java archive and is a reasonable file size, then uploads it as a GitHub Actions artifact.

**Deploy Job:** Downloads the build artifact, sets up an SSH key from GitHub Secrets, SSHs into solace.rit.edu to create the directory structure and config files, backs up the existing server.jar, transfers the new jar via SCP, stops any running server process, starts the new server, and verifies it is running after 10 seconds.

### branch-deploy.yml (Pull Request Testing)

**Trigger:** Pull requests targeting main.

Builds and tests the branch image in Docker to verify nothing is broken before merging. Does not deploy to Solace — only the main branch triggers a real deploy.

## Dependencies

### Build Dependencies (GitHub Actions runner)
- bash, curl, wget (pre-installed on GitHub runners)
- file command (for jar verification)

### Runtime Dependencies (on Solace)
- Java (available on RIT servers)
- Network access on port 25565

### CI/CD Dependencies
- GitHub Actions runners (free tier)
- GitHub Secrets (for SSH key storage)
