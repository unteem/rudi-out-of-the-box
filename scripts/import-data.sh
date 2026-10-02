#!/bin/bash
# import-data.sh - Import dummy/test data into a running RUDI platform
#
# Run this AFTER deploy.sh, once all services are up.
# It loads the sample datasets from dummy-data/ into the running databases
# and mounts the demo file stores.
#
# Usage:
#   ./scripts/import-data.sh              # interactive — asks which to import
#   ./scripts/import-data.sh --all        # import all without prompting
#   ./scripts/import-data.sh --rudi       # import only RUDI database
#   ./scripts/import-data.sh --dataverse  # import only Dataverse database
#   ./scripts/import-data.sh --magnolia   # import only Magnolia database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

cd "$ROOT_DIR"

echo "========================================="
echo "   RUDI Dummy Data Import               "
echo "========================================="
echo ""
echo "This imports sample data into the running RUDI databases:"
echo "  - RUDI:      test users, organizations, sample metadata (~318 MB)"
echo "  - Dataverse: sample collections and datasets (~67 MB)"
echo "  - Magnolia:  sample CMS content (~2 MB)"
echo ""
log_warning "This will overwrite any existing data in the selected databases."
log_warning "Only run this on a fresh deployment or a dedicated test environment."
echo ""

# ─── Parse arguments ──────────────────────────────────────────────────────────

IMPORT_RUDI=false
IMPORT_DATAVERSE=false
IMPORT_MAGNOLIA=false

if [ $# -eq 0 ]; then
  read -p "Import RUDI database (users, organizations, metadata)? (y/N): " -n 1 -r; echo
  [[ $REPLY =~ ^[Yy]$ ]] && IMPORT_RUDI=true

  read -p "Import Dataverse database (sample collections)? (y/N): " -n 1 -r; echo
  [[ $REPLY =~ ^[Yy]$ ]] && IMPORT_DATAVERSE=true

  read -p "Import Magnolia database (sample CMS content)? (y/N): " -n 1 -r; echo
  [[ $REPLY =~ ^[Yy]$ ]] && IMPORT_MAGNOLIA=true
else
  for arg in "$@"; do
    case "$arg" in
      --all)       IMPORT_RUDI=true; IMPORT_DATAVERSE=true; IMPORT_MAGNOLIA=true ;;
      --rudi)      IMPORT_RUDI=true ;;
      --dataverse) IMPORT_DATAVERSE=true ;;
      --magnolia)  IMPORT_MAGNOLIA=true ;;
      *)
        log_error "Unknown argument: $arg"
        echo "Usage: $0 [--all | --rudi | --dataverse | --magnolia]"
        exit 1
        ;;
    esac
  done
fi

if ! $IMPORT_RUDI && ! $IMPORT_DATAVERSE && ! $IMPORT_MAGNOLIA; then
  log_info "Nothing selected — exiting"
  exit 0
fi

# ─── Check services are running ───────────────────────────────────────────────

log_info "Checking that database containers are running..."

check_container() {
  local container=$1
  if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
    log_error "Container '$container' is not running"
    log_error "Start the platform first: ./scripts/deploy.sh"
    exit 1
  fi
}

$IMPORT_RUDI      && check_container "rudiplatform-database-1"
$IMPORT_DATAVERSE && check_container "rudiplatform-dataverse-database-1"
$IMPORT_MAGNOLIA  && check_container "rudiplatform-magnolia-database-1"

# ─── Check backup files exist ─────────────────────────────────────────────────

check_backup() {
  local path=$1
  if [ ! -f "$path" ]; then
    log_error "Backup file not found: $path"
    log_error "The dummy-data/ directory is stored externally (S3 or similar)."
    log_error "Download it and place it at: $ROOT_DIR/dummy-data/"
    exit 1
  fi
}

$IMPORT_RUDI      && check_backup "dummy-data/rudi/rudi.backup"
$IMPORT_DATAVERSE && check_backup "dummy-data/dataverse/dataverse.backup"
$IMPORT_MAGNOLIA  && check_backup "dummy-data/magnolia/magnolia.backup"

# ─── Load passwords ───────────────────────────────────────────────────────────

if [ ! -f ".env" ]; then
  log_error ".env not found — run ./scripts/deploy.sh first"
  exit 1
fi
set -a; source .env; set +a

# ─── Import RUDI database ─────────────────────────────────────────────────────

if $IMPORT_RUDI; then
  echo ""
  log_info "Importing RUDI database..."

  docker cp dummy-data/rudi/rudi.backup rudiplatform-database-1:/tmp/rudi.backup

  docker exec -e PGPASSWORD="$DB_RUDI" rudiplatform-database-1 \
    pg_restore -U rudi -d rudi --clean --if-exists /tmp/rudi.backup

  docker exec rudiplatform-database-1 rm /tmp/rudi.backup
  log_success "RUDI database imported"

  # Apply schema grants — schemas are created by pg_restore from the backup
  # and need explicit GRANT for service users to access them.
  log_info "Applying schema grants..."
  docker cp dummy-data/rudi/04-grant.sql rudiplatform-database-1:/tmp/04-grant.sql
  docker exec -e PGPASSWORD="$DB_RUDI" rudiplatform-database-1 \
    psql -U rudi -d rudi -f /tmp/04-grant.sql
  docker exec rudiplatform-database-1 rm /tmp/04-grant.sql
  log_success "Schema grants applied"
fi

# ─── Import Dataverse database ────────────────────────────────────────────────

if $IMPORT_DATAVERSE; then
  echo ""
  log_info "Importing Dataverse database..."

  docker cp dummy-data/dataverse/dataverse.backup rudiplatform-dataverse-database-1:/tmp/dataverse.backup

  docker exec -e PGPASSWORD="$DB_DATAVERSE" rudiplatform-dataverse-database-1 \
    pg_restore -U dataverse -d dataverse --clean --if-exists /tmp/dataverse.backup

  docker exec rudiplatform-dataverse-database-1 rm /tmp/dataverse.backup
  log_success "Dataverse database imported"

  # Also make the demo dataset files available by updating the compose mount.
  # The dataverse-files directory must match what's in the database.
  if [ -d "dummy-data/dataverse/dataverse-files" ]; then
    log_info "Copying demo dataset files to data/dataverse/dataverse-files/..."
    mkdir -p data/dataverse/dataverse-files
    cp -rn dummy-data/dataverse/dataverse-files/. data/dataverse/dataverse-files/
    log_success "Demo dataset files copied"
  fi
fi

# ─── Import Magnolia database ─────────────────────────────────────────────────

if $IMPORT_MAGNOLIA; then
  echo ""
  log_info "Importing Magnolia database..."

  docker cp dummy-data/magnolia/magnolia.backup rudiplatform-magnolia-database-1:/tmp/magnolia.backup

  docker exec -e PGPASSWORD="$DB_MAGNOLIA" rudiplatform-magnolia-database-1 \
    pg_restore -U magnolia -d magnolia --clean --if-exists /tmp/magnolia.backup

  docker exec rudiplatform-magnolia-database-1 rm /tmp/magnolia.backup
  log_success "Magnolia database imported"

  # Restore the JCR datastore (binary files referenced by the Magnolia database).
  # Without this, Magnolia will start but content references will be broken.
  if [ -d "dummy-data/magnolia/repository" ]; then
    log_info "Restoring Magnolia JCR datastore..."
    mkdir -p data/magnolia/repository
    cp -rn dummy-data/magnolia/repository/. data/magnolia/repository/
    log_success "Magnolia JCR datastore restored"
    log_warning "Restart Magnolia to apply: docker compose -f docker-compose-magnolia.yml --profile magnolia restart magnolia"
  fi
fi

# ─── Restart affected services ────────────────────────────────────────────────

echo ""
log_info "Restarting services to pick up imported data..."

if $IMPORT_RUDI; then
  docker compose -f docker-compose-rudi.yml --profile portail restart \
    acl strukture kalim konsult kos projekt selfdata konsent apigateway gateway
fi

if $IMPORT_DATAVERSE; then
  docker compose -f docker-compose-dataverse.yml restart dataverse
fi

if $IMPORT_MAGNOLIA; then
  docker compose -f docker-compose-magnolia.yml --profile magnolia restart magnolia
fi

echo ""
echo "========================================="
echo "Import Complete"
echo "========================================="
echo ""
log_success "Dummy data imported successfully"
echo ""
echo "Default credentials are in: documentation/identifiants.md"
echo ""
log_warning "Change all default passwords before exposing this installation publicly"
echo ""
