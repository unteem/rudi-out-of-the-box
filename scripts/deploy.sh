#!/bin/bash
# deploy.sh - Automated RUDI Platform Deployment
#
# This is the main deployment script that orchestrates the entire setup process

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo "========================================="
echo "   RUDI Platform Automated Deployment   "
echo "========================================="
echo ""

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
  log_warning "Running as root is not recommended"
  log_warning "Consider running as a regular user with Docker access"
fi

# Change to root directory
cd "$ROOT_DIR"

# Check prerequisites
log_info "Checking prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
  log_error "Docker is not installed"
  echo "Install Docker: https://docs.docker.com/engine/install/"
  exit 1
fi

# Check Docker Compose
if ! docker compose version &> /dev/null; then
  log_error "Docker Compose is not installed"
  echo "Install Docker Compose: https://docs.docker.com/compose/install/"
  exit 1
fi

# Check Git LFS
if ! command -v git-lfs &> /dev/null; then
  log_warning "Git LFS is not installed"
  log_warning "Some large files may not be available"
fi

# Check OpenSSL
if ! command -v openssl &> /dev/null; then
  log_error "OpenSSL is not installed"
  exit 1
fi

# Check keytool
if ! command -v keytool &> /dev/null; then
  log_error "keytool is not installed (part of Java JDK)"
  echo ""
  echo "Install Java JDK on Debian/Ubuntu:"
  echo "  sudo apt install openjdk-17-jdk"
  echo ""
  echo "Or use default JDK:"
  echo "  sudo apt install default-jdk"
  echo ""
  echo "After installation, verify:"
  echo "  keytool -version"
  echo ""
  echo "See DEBIAN-INSTALL-GUIDE.md for complete instructions."
  exit 1
fi

log_success "All prerequisites met"
echo ""
log_info "Using keytool: $(which keytool)"
log_info "Java version: $(java -version 2>&1 | head -1)"
echo ""

# Configuration
echo ""
log_info "Configuration..."

# Check if .env exists
if [ ! -f ".env" ]; then
  log_error ".env file not found"
  echo ""
  read -p "Enter your domain (e.g., example.com): " DOMAIN
  read -p "Enter RUDI version (default: v3.2.6): " RUDI_VERSION
  RUDI_VERSION=${RUDI_VERSION:-v3.2.6}
  
  cat > .env << EOF
base_dn=$DOMAIN
rudi_version=$RUDI_VERSION
EOF
  
  log_success "Created .env file"
fi

source .env
log_info "Domain: $base_dn"
log_info "RUDI Version: $rudi_version"

# Add .passwords.env to .gitignore if not already there
if [ -f ".gitignore" ]; then
  if ! grep -q ".passwords.env" .gitignore; then
    echo ".passwords.env" >> .gitignore
    echo ".env.local" >> .gitignore
    echo "config-backup-*" >> .gitignore
    log_info "Added sensitive files to .gitignore"
  fi
fi

# Step-by-step deployment
echo ""
echo "========================================="
echo "Starting Deployment Process"
echo "========================================="
echo ""

# Step 1: Set permissions
log_info "[1/10] Setting permissions..."
chmod -R 755 config 2>/dev/null || true
chmod -R 777 data 2>/dev/null || true
mkdir -p data/{rudi,dataverse,magnolia,solr}
mkdir -p database-data/{rudi,dataverse,magnolia}
mkdir -p certs logs
log_success "Permissions set"

# Step 2: Generate RSA keys
log_info "[2/10] Generating RSA keys..."
if [ -f "config/key/id_rsa" ]; then
  log_warning "RSA keys already exist"
  read -p "Regenerate? This will overwrite existing keys (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash scripts/generate-keys.sh
  else
    log_info "Skipping key generation"
  fi
else
  bash scripts/generate-keys.sh
fi
log_success "RSA keys ready"

# Step 3: Generate passwords
log_info "[3/10] Generating secure passwords..."
if [ -f ".passwords.env" ]; then
  log_warning "Passwords file already exists"
  read -p "Regenerate? This will create NEW passwords (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash scripts/generate-passwords.sh
  else
    log_info "Using existing passwords"
  fi
else
  bash scripts/generate-passwords.sh
fi
source .passwords.env
log_success "Passwords ready"

# Step 4: SSL Certificates
log_info "[4/10] Checking SSL certificates..."
if [ ! -f "certs/fullchain.pem" ] || [ ! -f "certs/privkey.pem" ]; then
  log_warning "SSL certificates not found in certs/ directory"
  echo ""
  echo "For PRODUCTION deployment, you need valid SSL certificates."
  echo "Options:"
  echo "  1. Copy your certificates to certs/fullchain.pem and certs/privkey.pem"
  echo "  2. Generate self-signed certificates (TESTING ONLY)"
  echo ""
  read -p "Generate self-signed certificates for testing? (y/N): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Generating self-signed certificates..."
    mkdir -p certs
    openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
      -keyout certs/privkey.pem \
      -out certs/fullchain.pem \
      -subj "/CN=rudi.$base_dn/O=RUDI Platform/C=FR"
    log_warning "Self-signed certificates generated - NOT for production!"
  else
    log_error "SSL certificates required. Exiting."
    exit 1
  fi
fi
log_success "SSL certificates available"

# Step 5: Generate SSL keystores
log_info "[5/10] Generating SSL keystores..."
bash scripts/generate-ssl-keystores.sh
log_success "SSL keystores generated"

# Step 6: Update configurations
log_info "[6/10] Updating configuration files..."
bash scripts/update-configs.sh
log_success "Configurations updated"

# Step 6.5: Prepare database init files with envsubst
log_info "[6.5/10] Preparing database initialization files..."
bash scripts/prepare-database-init.sh
log_success "Database init files prepared"

# Step 6.6: Prepare properties files with envsubst
log_info "[6.6/10] Preparing properties files..."
bash scripts/prepare-properties.sh
log_success "Properties files prepared"

# Step 7: Create Docker network
log_info "[7/10] Creating Docker network..."
docker network create traefik 2>/dev/null && log_success "Network created" || log_info "Network already exists"

# Step 8: Pull Docker images
log_info "[8/10] Pulling Docker images..."
log_info "This may take several minutes..."
docker compose -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               --profile "*" pull || log_warning "Some images failed to pull"
log_success "Images pulled"

# Step 9: Deploy services
log_info "[9/10] Deploying services..."

log_info "Starting databases..."
docker compose -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               up -d database dataverse-database magnolia-database

log_info "Waiting for databases to initialize (60 seconds)..."
sleep 60

log_info "Starting all services..."
docker compose -f docker-compose-magnolia.yml \
               -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-network.yml \
               --profile "*" up -d

log_success "All services started"

# Step 10: Verify deployment
log_info "[10/10] Verifying deployment..."
log_info "Waiting for services to be ready (30 seconds)..."
sleep 30

echo ""
echo "========================================="
echo "Service Health Check"
echo "========================================="

SERVICES_TO_CHECK=(
  "https://rudi.$base_dn:Portal"
  "https://dataverse.$base_dn:Dataverse"
  "https://magnolia.$base_dn:Magnolia"
)

ALL_HEALTHY=true
for service_info in "${SERVICES_TO_CHECK[@]}"; do
  IFS=':' read -r url name <<< "$service_info"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "$url" --connect-timeout 5 || echo "000")
  
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ]; then
    log_success "$name is accessible (HTTP $HTTP_CODE)"
  else
    log_warning "$name returned HTTP $HTTP_CODE (may still be starting)"
    ALL_HEALTHY=false
  fi
done

# Display running containers
echo ""
echo "========================================="
echo "Running Containers"
echo "========================================="
docker compose -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               -f docker-compose-network.yml \
               --profile "*" ps

echo ""
echo "========================================="
echo "Deployment Summary"
echo "========================================="
echo ""

if $ALL_HEALTHY; then
  log_success "Deployment completed successfully!"
else
  log_warning "Deployment completed with warnings"
  log_info "Some services may still be starting up"
  log_info "Check logs: docker compose logs -f"
fi

echo ""
echo "Access URLs:"
echo "  Portal:    https://rudi.$base_dn"
echo "  Dataverse: https://dataverse.$base_dn"
echo "  Magnolia:  https://magnolia.$base_dn"
echo ""
echo "Default credentials are in: documentation/identifiants.md"
echo "Generated passwords are in: .passwords.env (KEEP SECURE!)"
echo ""
echo "IMPORTANT NEXT STEPS:"
echo "  1. Change all default user passwords"
echo "  2. Review and test all services"
echo "  3. Configure producer nodes (see PRODUCTION-DEPLOYMENT.md)"
echo "  4. Set up backups and monitoring"
echo "  5. Configure email settings"
echo ""
echo "For production deployment, see: PRODUCTION-DEPLOYMENT.md"
echo ""
echo "To view logs:"
echo "  docker compose -f docker-compose-*.yml --profile '*' logs -f"
echo ""
echo "To stop services:"
echo "  docker compose -f docker-compose-*.yml --profile '*' stop"
echo ""
