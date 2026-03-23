# ============================================================
# Minecraft Server - Branch Deploy (Staging / PR Preview)
# ============================================================
# Builds the image for any feature branch or pull request
# and tags it with the branch name. Does NOT deploy to
# production — used for testing before merge.
#
# This follows the "Branch Deployment" best practice:
# deploy each branch before merging so the destination branch
# can always be re-deployed if something goes wrong.
# ============================================================

name: Minecraft Server - Branch Build (PR)

on:
  pull_request:
    branches: [main]

env:
  IMAGE_NAME: minecraft-server
  REGISTRY: ghcr.io

jobs:
  branch-build:
    name: Build & Test Branch
    runs-on: ubuntu-latest

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Determine branch tag
        id: meta
        run: |
          BRANCH="${{ github.head_ref }}"
          SAFE_BRANCH=$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9._-]/-/g')
          TAG="${{ env.REGISTRY }}/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${SAFE_BRANCH}"
          echo "tag=${TAG}" >> "$GITHUB_OUTPUT"
          echo "branch=${SAFE_BRANCH}" >> "$GITHUB_OUTPUT"

      - name: Build Docker image for branch
        run: |
          docker build \
            -t ${{ steps.meta.outputs.tag }} \
            -f Dockerfile.builder .

      - name: Smoke-test — container starts without crash
        run: |
          echo "Starting container for smoke test..."
          CONTAINER_ID=$(docker run -d ${{ steps.meta.outputs.tag }})
          sleep 15
          STATUS=$(docker inspect --format='{{.State.Running}}' "$CONTAINER_ID" 2>/dev/null || echo "false")
          docker logs "$CONTAINER_ID" 2>&1 | tail -20
          docker stop "$CONTAINER_ID" > /dev/null
          if [ "$STATUS" != "true" ]; then
            echo "::error::Container exited within 15 seconds — branch build is broken."
            exit 1
          fi
          echo "Branch smoke test passed."

      - name: Push branch image to GHCR
        run: docker push ${{ steps.meta.outputs.tag }}

      - name: Post summary
        run: |
          echo "### Branch Build Summary" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Branch:** ${{ steps.meta.outputs.branch }}" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Image:** \`${{ steps.meta.outputs.tag }}\`" >> "$GITHUB_STEP_SUMMARY"
          echo "- **Smoke Test:** Passed" >> "$GITHUB_STEP_SUMMARY"
