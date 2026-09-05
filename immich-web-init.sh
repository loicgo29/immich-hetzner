#!/bin/bash
set -e

# Fix immich-web configuration to point to correct server
# This runs BEFORE the original entrypoint

echo "Patching immich-web for correct server URL..."

# Find and replace the hardcoded server address in the app bundles
# The issue: immich-web tries to connect to 172.19.0.4:3001 (old docker network address)
# We need it to use immich-server:2283 instead

# Search for any JavaScript files in the web assets
find /app -name "*.js" -type f | while read jsfile; do
  # Replace localhost:3001 → immich-server:2283
  sed -i 's|localhost:3001|immich-server:2283|g' "$jsfile" 2>/dev/null || true
  # Replace any hardcoded docker IP:3001 pattern → immich-server:2283
  sed -i 's|172\.[0-9]\+\.[0-9]\+\.[0-9]\+:3001|immich-server:2283|g' "$jsfile" 2>/dev/null || true
done

echo "Patching complete. Starting nginx..."

# Continue with original entrypoint
exec "$@"
