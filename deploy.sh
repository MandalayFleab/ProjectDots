#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Running as a script (not an interactive login shell) skips ~/.zprofile,
# which is where Docker Desktop adds `docker` to PATH -- add it explicitly.
export PATH="$HOME/.docker/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

GODOT_BIN="/Users/mandalay/Documents/Godot/Godot.app/Contents/MacOS/Godot"
IMAGE="mandalayfleab/project-dots"
TAG="$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"

echo "==> Exporting Godot Web build..."
rm -rf build/web
mkdir -p build/web
"$GODOT_BIN" --headless --export-release "Web" build/web/index.html

echo "==> Building and pushing Docker image ${IMAGE}:${TAG} (linux/amd64, for the server)..."
# The server is linux/amd64; building on Apple Silicon without --platform would
# produce an arm64-only image the server can't pull. buildx --push builds and
# pushes directly since multi/cross-platform images can't be `docker load`ed locally.
docker buildx build --platform linux/amd64 \
	-f Dockerfile -t "${IMAGE}:${TAG}" -t "${IMAGE}:latest" --push .

echo
echo "Done. Paste this into the panel (adjust the left-hand port if 3000 is taken):"
echo
cat <<EOF
services:
  web:
    image: ${IMAGE}:${TAG}
    ports:
      - "3005:80"
    restart: unless-stopped
EOF
