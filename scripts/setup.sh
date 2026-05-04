#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_DIR="$REPO_ROOT/terraform/0-bootstrap"

echo "=== Project1 Infrastructure Setup (One-time) ==="
echo ""
echo "This script automates the bootstrap process:"
echo "  1. Create S3 bucket + DynamoDB table with local backend"
echo "  2. Migrate state from local to S3 backend"
echo ""

echo "[1/3] Initializing terraform (local backend)..."
terraform -chdir="$BOOTSTRAP_DIR" init

echo ""
echo "[2/3] Applying bootstrap with local backend..."
terraform -chdir="$BOOTSTRAP_DIR" apply -auto-approve

echo ""
echo "[2/3] Uncommenting S3 backend in providers.tf..."
sed -i '' -e '8,14s/^  # /  /' "$BOOTSTRAP_DIR/providers.tf"

echo ""
echo "[3/3] Migrating state to S3..."
terraform -chdir="$BOOTSTRAP_DIR" init -migrate-state

echo ""
echo "=== Bootstrap complete ==="
echo "You can now run: ./scripts/start.sh"
