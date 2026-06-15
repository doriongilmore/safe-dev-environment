#!/bin/bash
set -euo pipefail

echo "[post-create] Running safe-npm install..."
# npm is safe-npm via the symlink set in the Dockerfile
npm install

echo "[post-create] Done."
