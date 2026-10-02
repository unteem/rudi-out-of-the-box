#!/bin/bash
# prepare-database-init.sh - Process SQL init files with environment variables
#
# This script uses envsubst to replace variables in SQL files before database initialization

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

cd "$ROOT_DIR"

echo "========================================="
echo "Preparing Database Initialization Files"
echo "========================================="
echo ""

# Check if passwords file exists
if [ ! -f ".env" ]; then
  echo "ERROR: .env not found!"
  echo "Copy the template first: cp .env.example .env"
  exit 1
fi

# Source and export passwords
set -a; source .env; set +a

# Explicit variable list — prevents envsubst from touching unrelated ${...} patterns
DB_VARS='$DB_RUDI $DB_ACL $DB_APIGATEWAY $DB_KALIM $DB_KONSENT $DB_KOS $DB_PROJEKT $DB_SELFDATA $DB_STRUKTURE $DB_TEMPLATE $DB_DATAVERSE $DB_MAGNOLIA'
MS_VARS='$MS_ACL $MS_APIGATEWAY $MS_KALIM $MS_KONSENT $MS_KONSULT $MS_KOS $MS_PROJEKT $MS_SELFDATA $MS_STRUKTURE'
ALL_VARS="$DB_VARS $MS_VARS"

log_info "Processing RUDI database init files..."

for sql_template in config/rudi-init/*.sql.template; do
  sql_file="${sql_template%.template}"
  echo "Processing $sql_template..."
  envsubst "$ALL_VARS" < "$sql_template" > "$sql_file"
done

log_info "Processing ACL OAuth2 secrets script..."
envsubst "$MS_VARS" < config/acl/03-oauth-secrets.sql.template > config/acl/03-oauth-secrets.sql

echo ""
echo "========================================="
echo "✓ Database init files prepared!"
echo "========================================="
echo ""

