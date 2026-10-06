#!/bin/bash
# deploy.sh - Automated RUDI Platform Deployment
#
# Deploys the RUDI platform with empty databases (no dummy data).
# To load dummy data afterwards, run: scripts/import-data.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================="
echo "   RUDI Platform Deployment             "
echo "========================================="
echo ""

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
  log_warning "Running as root is not recommended"
  log_warning "Consider running as a regular user with Docker access"
fi

cd "$ROOT_DIR"

# ─── Prerequisites ────────────────────────────────────────────────────────────

log_info "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
  log_error "Docker is not installed"
  echo "Install Docker: https://docs.docker.com/engine/install/"
  exit 1
fi

if ! docker compose version &> /dev/null; then
  log_error "Docker Compose plugin is not installed"
  echo "Install: sudo apt install docker-compose-plugin"
  exit 1
fi

if ! command -v openssl &> /dev/null; then
  log_error "OpenSSL is not installed"
  echo "Install: sudo apt install openssl"
  exit 1
fi

if ! command -v keytool &> /dev/null; then
  log_error "keytool is not installed (requires Java JDK)"
  echo "Install: sudo apt install openjdk-17-jdk"
  exit 1
fi


log_success "Prerequisites met"
echo ""

# ─── Configuration ────────────────────────────────────────────────────────────

log_info "Loading configuration..."

if [ ! -f ".env" ]; then
  log_error ".env not found"
  echo "Copy the template and fill in your settings:"
  echo "  cp .env.example .env"
  exit 1
fi

set -a; source .env; set +a
DATAVERSE_HOST="${DATAVERSE_DOMAIN:-dataverse.$base_dn}"
MAGNOLIA_HOST="${MAGNOLIA_DOMAIN:-magnolia.$base_dn}"
log_info "Domain:        $base_dn"
log_info "RUDI version:  $rudi_version"
log_info "LE email:      ${LETSENCRYPT_EMAIL:-<not set>}"

if [ -z "$LETSENCRYPT_EMAIL" ]; then
  log_warning "LETSENCRYPT_EMAIL is not set in .env — Traefik will not be able to request TLS certificates"
fi

echo ""
echo "========================================="
echo "Starting Deployment"
echo "========================================="
echo ""

# ─── Step 1: Directories and permissions ──────────────────────────────────────

log_info "[1/7] Setting up directories and permissions..."
# Directories only: keystores must stay in mode 600
find config -type d -exec chmod 755 {} + 2>/dev/null || true
mkdir -p data/{rudi,dataverse,magnolia,producer}
mkdir -p data/solr/solr-data
mkdir -p database-data/{rudi,dataverse,magnolia}
mkdir -p logs
# Solr runs as UID 8983 inside the container
chown -R 8983:8983 data/solr 2>/dev/null || \
  log_warning "Could not chown data/solr — run: sudo chown -R 8983:8983 data/solr"
# rudinode (producer node) runs as UID 5001
chown -R 5001:5001 data/producer 2>/dev/null || \
  log_warning "Could not chown data/producer — run: sudo chown -R 5001:5001 data/producer"
log_success "Directories ready"

# ─── Step 2: Passwords ────────────────────────────────────────────────────────

log_info "[2/7] Generating passwords..."
if grep -q "^DB_RUDI=" .env 2>/dev/null; then
  log_warning "Passwords already present in .env"
  read -p "Regenerate? This will create NEW passwords and invalidate existing data (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash scripts/generate-passwords.sh
  else
    log_info "Keeping existing passwords"
  fi
else
  bash scripts/generate-passwords.sh
fi
set -a; source .env; set +a
log_success "Passwords ready"

# ─── Step 3: Keystores ────────────────────────────────────────────────────

log_info "[3/7] Generating keystores (SSL, consent, selfdata, apigateway, JWT)..."
bash scripts/generate-ssl-keystores.sh
log_success "Keystores ready"

# ─── Step 4: Configuration files ──────────────────────────────────────────────

log_info "[4/7] Preparing configuration files..."
bash scripts/prepare-database-init.sh
bash scripts/prepare-properties.sh
log_success "Configuration files ready"

# ─── Step 5: Traefik ACME file ────────────────────────────────────────────────

log_info "[5/7] Preparing Traefik..."
mkdir -p traefik
if [ ! -f "traefik/acme.json" ]; then
  touch traefik/acme.json
  chmod 600 traefik/acme.json
  log_success "Created traefik/acme.json"
else
  # Ensure permissions are correct even if file already existed
  chmod 600 traefik/acme.json
  log_info "traefik/acme.json already exists"
fi

# ─── Step 6: Docker network ───────────────────────────────────────────────────

log_info "[6/7] Creating Docker network..."
docker network create traefik 2>/dev/null && log_success "Network 'traefik' created" || log_info "Network 'traefik' already exists"

# ─── Step 7: Deploy services ──────────────────────────────────────────────────

log_info "[7/7] Deploying services..."

log_info "Pulling Docker images (this may take several minutes)..."
docker compose \
               -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               --profile "*" pull || log_warning "Some images failed to pull"

COMPOSE_ALL="-f docker-compose-magnolia.yml -f docker-compose-rudi.yml -f docker-compose-dataverse.yml -f docker-compose-network.yml"

log_info "Starting databases..."
docker compose $COMPOSE_ALL up -d database dataverse-database magnolia-database

log_info "Waiting for databases to initialize (60 seconds)..."
sleep 60

# Dataverse and Magnolia first: RUDI microservices need the Dataverse API token
log_info "Starting Dataverse, Solr and Magnolia..."
docker compose $COMPOSE_ALL --profile dataverse --profile magnolia up -d

log_info "Initializing Dataverse for RUDI (bootstrap, rudi metadata block, collections)..."
bash scripts/init-dataverse.sh
set -a; source .env; set +a
bash scripts/prepare-properties.sh
log_success "Dataverse initialized"

log_info "Starting RUDI services..."
docker compose $COMPOSE_ALL --profile "*" up -d

log_success "All services started"

# ─── Apply OAuth2 microservice secrets ────────────────────────────────────────
#
# The ACL Flyway migrations seed microservice users (kalim, strukture, etc.)
# with an unknown hardcoded BCrypt hash. We overwrite those hashes with the
# deployment-specific MS_* secrets after Flyway has run.
# We wait for ACL to finish starting and Flyway to complete before applying.

log_info "Waiting for ACL to start and Flyway to complete (60 seconds)..."
sleep 60

ACL_READY=false
for i in $(seq 1 12); do
  if docker compose -f docker-compose-rudi.yml exec -T database \
       psql -U rudi -d rudi -c "SELECT 1 FROM acl_data.user_ WHERE login='kalim';" \
       > /dev/null 2>&1; then
    ACL_READY=true
    break
  fi
  log_info "Waiting for ACL Flyway migrations... (${i}/12)"
  sleep 10
done

if $ACL_READY; then
  log_info "Applying OAuth2 microservice secrets..."
  docker exec -i rudiplatform-database-1 \
    psql -U rudi -d rudi < config/acl/03-oauth-secrets.sql
  log_success "OAuth2 microservice secrets applied"
  log_info "Restarting microservices to pick up new secrets..."
  docker compose -f docker-compose-rudi.yml restart \
    acl kalim strukture konsult kos projekt selfdata konsent apigateway
  log_success "Microservices restarted"
else
  log_warning "ACL Flyway migrations did not complete in time — OAuth2 secrets not applied"
  log_info "Apply manually: docker exec rudiplatform-database-1 psql -U rudi -d rudi < config/acl/03-oauth-secrets.sql"
fi

# ─── Health check ─────────────────────────────────────────────────────────────

log_info "Waiting for services to be ready (30 seconds)..."
sleep 30

echo ""
echo "========================================="
echo "Service Health Check"
echo "========================================="

ALL_HEALTHY=true
for entry in "https://rudi.$base_dn|Portal" "https://$DATAVERSE_HOST|Dataverse" "https://$MAGNOLIA_HOST|Magnolia"; do
  IFS='|' read -r url name <<< "$entry"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "$url" --connect-timeout 5 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ]; then
    log_success "$name is reachable (HTTP $HTTP_CODE)"
  else
    log_warning "$name returned HTTP $HTTP_CODE (may still be starting)"
    ALL_HEALTHY=false
  fi
done

echo ""
echo "========================================="
echo "Running Containers"
echo "========================================="
docker compose \
               -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               -f docker-compose-network.yml \
               --profile "*" ps

echo ""
echo "========================================="
echo "Deployment Complete"
echo "========================================="
echo ""

if $ALL_HEALTHY; then
  log_success "All services are reachable"
else
  log_warning "Some services may still be starting — check logs if issues persist"
  echo "  docker compose -f docker-compose-rudi.yml logs -f"
fi

echo ""
echo "Access URLs:"
echo "  Portal:    https://rudi.$base_dn"
echo "  Dataverse: https://$DATAVERSE_HOST"
echo "  Magnolia:  https://$MAGNOLIA_HOST"
echo ""
echo "Generated passwords: .env  (keep secure!)"
echo ""
echo "Next steps (see documentation/cookbook/roob-to-prod.md):"
echo "  1. Configure Magnolia (change superuser password)"
echo "  2. Create the first RUDI administrator"
echo "  3. Initialize KOS vocabularies: ./scripts/init-kos.sh"
echo "  4. Define reuse reference lists: ./scripts/init-projekt.sh (config/projekt/referentiels.json)"
echo "  5. Deploy the producer node: ./scripts/deploy-producer.sh"
echo "  6. Back up .env and config/*/*.jks"
echo ""
echo "To load dummy/test data into the databases:"
echo "  ./scripts/import-data.sh"
echo ""
echo "To view logs:"
echo "  docker compose -f docker-compose-rudi.yml -f docker-compose-dataverse.yml -f docker-compose-magnolia.yml --profile '*' logs -f"
echo ""
echo "To stop services:"
echo "  docker compose -f docker-compose-rudi.yml -f docker-compose-dataverse.yml -f docker-compose-magnolia.yml -f docker-compose-network.yml --profile '*' stop"
echo ""
