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
if [ ! -f ".passwords.env" ]; then
  echo "ERROR: .passwords.env not found!"
  echo "Please run generate-passwords.sh first"
  exit 1
fi

# Source passwords
source .passwords.env

# Export all database passwords for envsubst
export DB_RUDI
export DB_DATAVERSE
export DB_MAGNOLIA
export DB_ACL
export DB_APIGATEWAY
export DB_KALIM
export DB_KONSENT
export DB_KOS
export DB_PROJEKT
export DB_SELFDATA
export DB_STRUKTURE
export DB_TEMPLATE

log_info "Processing RUDI database init files..."

# Create backup of original file if not already backed up
if [ ! -f "config/rudi-init/01-usr.sql.template" ]; then
  cp config/rudi-init/01-usr.sql config/rudi-init/01-usr.sql.template
  log_info "Created template backup: 01-usr.sql.template"
fi

# Process SQL file with envsubst
envsubst < config/rudi-init/01-usr.sql.template > config/rudi-init/01-usr.sql

log_success "Processed: config/rudi-init/01-usr.sql"

# Verify variables were replaced
if grep -q '\${DB_' config/rudi-init/01-usr.sql; then
  log_warning "Some variables may not have been replaced!"
  grep '\${DB_' config/rudi-init/01-usr.sql
else
  log_success "All database password variables replaced"
fi

# Process other SQL files if they have variables
for sql_file in config/rudi-init/*.sql; do
  if [ "$sql_file" = "config/rudi-init/01-usr.sql" ]; then
    continue  # Already processed
  fi
  
  if grep -q '\${' "$sql_file"; then
    log_info "Processing $(basename $sql_file)..."
    
    # Create template backup
    if [ ! -f "${sql_file}.template" ]; then
      cp "$sql_file" "${sql_file}.template"
    fi
    
    # Process with envsubst
    envsubst < "${sql_file}.template" > "$sql_file"
    log_success "Processed: $sql_file"
  fi
done

# Process Dataverse and Magnolia init files if needed
log_info "Checking Dataverse init files..."
for sql_file in config/dataverse-init/*.sql 2>/dev/null; do
  if [ -f "$sql_file" ] && grep -q '\${' "$sql_file"; then
    log_info "Processing $(basename $sql_file)..."
    
    # Create template backup
    if [ ! -f "${sql_file}.template" ]; then
      cp "$sql_file" "${sql_file}.template"
    fi
    
    # Process with envsubst
    envsubst < "${sql_file}.template" > "$sql_file"
    log_success "Processed: $sql_file"
  fi
done

log_info "Checking Magnolia init files..."
for sql_file in config/magnolia-init/*.sql 2>/dev/null; do
  if [ -f "$sql_file" ] && grep -q '\${' "$sql_file"; then
    log_info "Processing $(basename $sql_file)..."
    
    # Create template backup
    if [ ! -f "${sql_file}.template" ]; then
      cp "$sql_file" "${sql_file}.template"
    fi
    
    # Process with envsubst
    envsubst < "${sql_file}.template" > "$sql_file"
    log_success "Processed: $sql_file"
  fi
done

echo ""
echo "========================================="
echo "✓ Database init files prepared!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Replaced password variables in SQL files"
echo "  - Created .template backups of original files"
echo "  - Ready for database initialization"
echo ""
echo "Variables used:"
echo "  DB_ACL, DB_APIGATEWAY, DB_KALIM, DB_KONSENT,"
echo "  DB_KOS, DB_PROJEKT, DB_SELFDATA, DB_STRUKTURE, DB_TEMPLATE"
echo ""
