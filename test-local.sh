#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

GODOT_BIN="/Users/mandalay/Documents/Godot/Godot.app/Contents/MacOS/Godot"
PORT="${1:-8080}"

echo "==> Exporting Godot Web build..."
rm -rf build/web
mkdir -p build/web
"$GODOT_BIN" --headless --export-release "Web" build/web/index.html

echo "==> Serving at http://localhost:${PORT} (Ctrl+C to stop)"
cd build/web
python3 -m http.server "$PORT"
