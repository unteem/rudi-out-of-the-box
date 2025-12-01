#!/bin/bash
# deploy-clean.sh - Clean production deployment WITHOUT dummy data
#
# This script deploys RUDI with empty databases (schema only, no test data)
# No Git LFS required!

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cd "$ROOT_DIR"

echo "========================================="
echo "   RUDI Clean Production Deployment     "
echo "========================================="
echo ""
log_info "This deployment will create EMPTY databases"
log_info "No dummy data, no test users, no sample content"
echo ""
echo "What will be created:"
echo "  ✓ Database schemas and tables (via Flyway migrations)"
echo "  ✓ Database users with secure passwords"
echo "  ✓ Empty RUDI portal (you create the first admin)"
echo "  ✓ Empty Dataverse (default admin user only)"
echo "  ✓ Empty Magnolia CMS (default admin user only)"
echo ""
echo "What will NOT be imported:"
echo "  ✗ rudi.backup (318MB) - Test users and organizations"
echo "  ✗ dataverse.backup (67MB) - Sample collections"
echo "  ✗ magnolia.backup (1.9MB) - Sample CMS content"
echo ""
read -p "Continue with clean deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_error "Aborted"
  exit 1
fi

# Disable dummy data imports
echo ""
log_info "Disabling dummy data imports..."

# RUDI database - disable backup import
if [ -f "config/rudi-init/03-import.sh" ]; then
  mv config/rudi-init/03-import.sh config/rudi-init/03-import.sh.disabled
  log_success "Disabled RUDI dummy data import (rudi.backup)"
else
  log_info "RUDI import already disabled"
fi

# Dataverse database - disable backup import
if [ -f "config/dataverse-init/import.sh" ]; then
  mv config/dataverse-init/import.sh config/dataverse-init/import.sh.disabled
  log_success "Disabled Dataverse dummy data import (dataverse.backup)"
else
  log_info "Dataverse import already disabled"
fi

# Magnolia database - disable backup import
if [ -f "config/magnolia-init/import.sh" ]; then
  mv config/magnolia-init/import.sh config/magnolia-init/import.sh.disabled
  log_success "Disabled Magnolia dummy data import (magnolia.backup)"
else
  log_info "Magnolia import already disabled"
fi

# Optional: Remove backup files to save space
echo ""
read -p "Remove backup files to save disk space (386MB)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -f config/rudi-init/rudi.backup
  rm -f config/dataverse-init/dataverse.backup
  rm -f config/magnolia-init/magnolia.backup
  log_success "Removed backup files (saved 386MB)"
fi

# Prepare database init files before deployment
echo ""
log_info "Preparing database initialization files..."
if [ -f "$ROOT_DIR/.passwords.env" ]; then
  bash "$SCRIPT_DIR/prepare-database-init.sh"
  log_success "Database init files prepared"
else
  log_warning "No .passwords.env found, will be generated during deployment"
fi

# Run standard deployment
echo ""
log_info "Starting clean deployment..."
echo ""

bash "$SCRIPT_DIR/deploy.sh"

DEPLOY_EXIT=$?

if [ $DEPLOY_EXIT -eq 0 ]; then
  echo ""
  echo "========================================="
  echo "Clean Deployment Complete!"
  echo "========================================="
  echo ""
  log_success "RUDI platform deployed with EMPTY databases"
  echo ""
  echo "📋 IMPORTANT NEXT STEPS:"
  echo ""
  echo "1️⃣  CREATE FIRST ADMIN USER (RUDI Portal)"
  echo "   docker exec -it database psql -U rudi -d rudi"
  echo ""
  echo "   Then run this SQL:"
  echo "   INSERT INTO acl_data.user_account "
  echo "     (uuid, login, password, type, created_date, updated_date)"
  echo "   VALUES "
  echo "     (gen_random_uuid(), 'admin@yourdomain.com', "
  echo "      crypt('YourPassword123!', gen_salt('bf', 12)), "
  echo "      'PERSON', NOW(), NOW());"
  echo ""
  echo "2️⃣  CHANGE DATAVERSE ADMIN PASSWORD"
  echo "   Access: https://dataverse.\${base_dn}"
  echo "   Login: dataverseAdmin / Rud1R00B-dvadmin"
  echo "   Then change password immediately!"
  echo ""
  echo "3️⃣  CHANGE MAGNOLIA ADMIN PASSWORD"
  echo "   Access: https://magnolia.\${base_dn}"
  echo "   Login: superuser / Rud1R00B-mgl-admin"
  echo "   Then change password immediately!"
  echo ""
  echo "4️⃣  CREATE YOUR ORGANIZATION"
  echo "   Via RUDI Portal admin interface"
  echo ""
  echo "📖 Detailed instructions: PRODUCTION-CLEAN-INSTALL.md"
  echo ""
  echo "⚠️  Remember: No test users exist!"
  echo "   You must create all users and organizations from scratch."
  echo ""
else
  log_error "Deployment failed with exit code $DEPLOY_EXIT"
  echo ""
  echo "To restore dummy data imports:"
  echo "  mv config/rudi-init/03-import.sh.disabled config/rudi-init/03-import.sh"
  echo "  mv config/dataverse-init/import.sh.disabled config/dataverse-init/import.sh"
  echo "  mv config/magnolia-init/import.sh.disabled config/magnolia-init/import.sh"
  exit $DEPLOY_EXIT
fi
