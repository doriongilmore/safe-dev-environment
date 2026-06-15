#!/bin/bash
set -euo pipefail

echo "[post-create] Checking Composer dependencies..."
if [ -f composer.json ]; then
    composer install --no-interaction
    echo "[post-create] Composer install done."
else
    echo "[post-create] No composer.json found — skipping."
fi
