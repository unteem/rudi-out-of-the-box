#!/bin/bash
# update-configs.sh - Update RUDI configuration files with generated passwords
#
# This script updates all configuration files with passwords from .env
# WARNING: This will modify configuration files in place

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Updating Configuration Files"
echo "========================================="
echo ""

# Check if passwords file exists
if [ ! -f "$ROOT_DIR/.env" ]; then
  echo "ERROR: .env not found!"
  echo "Please run deploy.sh first"
  exit 1
fi

# Source and export all variables
set -a; source "$ROOT_DIR/.env"; set +a

echo "WARNING: This will modify configuration files in place!"
echo "A backup will be created first."
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Create backup
BACKUP_DIR="$ROOT_DIR/config-backup-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup: $BACKUP_DIR"
cp -r "$ROOT_DIR/config" "$BACKUP_DIR"

echo ""
echo "[1/5] Preparing database initialization..."
echo "  ℹ  Database init files will be processed by prepare-database-init.sh"
echo "  ℹ  Using envsubst to replace password variables"

echo ""
echo "[2/5] Docker Compose files use environment variables..."
echo "  ℹ  Variables will be read from .env.local at runtime"
echo "  ℹ  No modification of docker-compose files needed"

echo ""
echo "[3/5] Properties files use envsubst templates..."
echo "  ℹ  Properties will be processed by prepare-properties.sh"
echo "  ℹ  Using envsubst with explicit variable list"
echo "  ℹ  Spring Boot property references will be preserved"

echo ""
echo "[5/5] Creating environment override file..."

# Create .env.local for Docker Compose to use
cat > "$ROOT_DIR/.env.local" << EOF
# Auto-generated environment overrides
# Source: update-configs.sh on $(date)

# Database passwords for Docker Compose
DB_RUDI=${DB_RUDI}
DB_DATAVERSE=${DB_DATAVERSE}
DB_MAGNOLIA=${DB_MAGNOLIA}

# Dataverse
DATAVERSE_API_TOKEN=${DATAVERSE_API_TOKEN}

# Application
EUREKA_PASSWORD=${EUREKA_PASSWORD}
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD}
EOF

chmod 600 "$ROOT_DIR/.env.local"
echo "  ✓ Created .env.local"

echo ""
echo "========================================="
echo "✓ Configuration update complete!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Backup created: $BACKUP_DIR"
echo "  - Prepared database init scripts (envsubst will process)"
echo "  - Docker Compose files use environment variables"
echo "  - Properties files use envsubst templates"
echo "  - Created .env.local for Docker Compose variable resolution"
echo ""
echo "What will be configured:"
echo "  ✓ Database passwords (via envsubst)"
echo "  ✓ OAuth2 client secrets (via envsubst)"
echo "  ✓ Keystore passwords (via envsubst)"
echo "  ✓ Eureka credentials (via envsubst)"
echo "  ✓ Dataverse API token (via envsubst)"
echo "  ✓ Special keystore passwords (via envsubst)"
echo ""
echo "To restore from backup if needed:"
echo "  rm -rf config && mv $BACKUP_DIR config"
echo ""
echo "Next: run prepare-properties.sh and prepare-database-init.sh"
echo "See: documentation/cookbook/roob-to-prod.md"
echo ""
