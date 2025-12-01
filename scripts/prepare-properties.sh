#!/bin/bash
# prepare-properties.sh - Process properties files with environment variables
#
# This script uses envsubst to replace ONLY deployment-specific variables,
# while preserving Spring Boot property references like ${server.ssl.key-store-password}

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cd "$ROOT_DIR"

echo "========================================="
echo "Preparing Properties Files"
echo "========================================="
echo ""

# Check if passwords file exists
if [ ! -f ".passwords.env" ]; then
  log_error ".passwords.env not found!"
  echo "Please run generate-passwords.sh first"
  exit 1
fi

# Source passwords
source .passwords.env

# Source SMTP configuration if exists
if [ -f ".env.smtp" ]; then
  log_info "Loading SMTP configuration from .env.smtp"
  source .env.smtp
else
  log_warning "No .env.smtp found - using default mailhog configuration"
  log_info "For production, copy .env.smtp.example to .env.smtp and configure"
  # Set defaults for testing (mailhog)
  export SMTP_HOST=${SMTP_HOST:-mailhog}
  export SMTP_PORT=${SMTP_PORT:-1025}
  export SMTP_AUTH=${SMTP_AUTH:-false}
  export SMTP_STARTTLS=${SMTP_STARTTLS:-false}
  export SMTP_USERNAME=${SMTP_USERNAME:-}
  export SMTP_PASSWORD=${SMTP_PASSWORD:-}
  export SMTP_FROM=${SMTP_FROM:-noreply@rudi.localhost}
fi

# Export variables that we want envsubst to replace
# IMPORTANT: Only list variables we want to replace, not Spring Boot placeholders!
export DB_ACL DB_APIGATEWAY DB_KALIM DB_KONSENT DB_KOS \
       DB_PROJEKT DB_SELFDATA DB_STRUKTURE

export MS_ACL MS_APIGATEWAY MS_KALIM MS_KONSENT MS_KOS \
       MS_PROJEKT MS_SELFDATA MS_STRUKTURE

export KEYSTORE_PASSWORD CONSENT_KEYSTORE_PASSWORD \
       SELFDATA_KEYSTORE_PASSWORD APIGATEWAY_KEYSTORE_PASSWORD

export EUREKA_USER EUREKA_PASSWORD DATAVERSE_API_TOKEN

export CONSENT_VALIDATE_SALT CONSENT_REVOKE_SALT \
       TREATMENTVERSION_PUBLISH_SALT

export SMTP_HOST SMTP_PORT SMTP_AUTH SMTP_STARTTLS \
       SMTP_USERNAME SMTP_PASSWORD SMTP_FROM

export base_dn

# List of variables to replace (CRITICAL: only these will be replaced)
# This prevents envsubst from replacing Spring Boot variables like ${server.ssl.key-store-password}
ENVSUBST_VARS='$DB_ACL $DB_APIGATEWAY $DB_KALIM $DB_KONSENT $DB_KOS $DB_PROJEKT $DB_SELFDATA $DB_STRUKTURE'
ENVSUBST_VARS="$ENVSUBST_VARS "'$MS_ACL $MS_APIGATEWAY $MS_KALIM $MS_KONSENT $MS_KOS $MS_PROJEKT $MS_SELFDATA $MS_STRUKTURE'
ENVSUBST_VARS="$ENVSUBST_VARS "'$KEYSTORE_PASSWORD $CONSENT_KEYSTORE_PASSWORD $SELFDATA_KEYSTORE_PASSWORD $APIGATEWAY_KEYSTORE_PASSWORD'
ENVSUBST_VARS="$ENVSUBST_VARS "'$EUREKA_USER $EUREKA_PASSWORD $DATAVERSE_API_TOKEN'
ENVSUBST_VARS="$ENVSUBST_VARS "'$CONSENT_VALIDATE_SALT $CONSENT_REVOKE_SALT $TREATMENTVERSION_PUBLISH_SALT'
ENVSUBST_VARS="$ENVSUBST_VARS "'$SMTP_HOST $SMTP_PORT $SMTP_AUTH $SMTP_STARTTLS $SMTP_USERNAME $SMTP_PASSWORD $SMTP_FROM'
ENVSUBST_VARS="$ENVSUBST_VARS "'$base_dn'

log_info "Processing microservice properties files..."
echo ""

# List of microservices
SERVICES=(acl apigateway gateway kalim konsent kos konsult projekt selfdata strukture registry)

TOTAL=${#SERVICES[@]}
CURRENT=0

for service in "${SERVICES[@]}"; do
  CURRENT=$((CURRENT + 1))
  PROP_FILE="$ROOT_DIR/config/$service/${service}.properties"
  
  if [ ! -f "$PROP_FILE" ]; then
    log_warning "[$CURRENT/$TOTAL] Skipping $service (file not found)"
    continue
  fi
  
  echo "[$CURRENT/$TOTAL] Processing $service..."
  
  # Create .template backup if not already exists
  if [ ! -f "${PROP_FILE}.template" ]; then
    cp "$PROP_FILE" "${PROP_FILE}.template"
    log_info "  Created template backup"
  fi
  
  # Process with envsubst - ONLY replacing our specific variables
  envsubst "$ENVSUBST_VARS" < "${PROP_FILE}.template" > "$PROP_FILE"
  
  # Verify Spring Boot variables are preserved
  if grep -q '\${server\.' "$PROP_FILE"; then
    log_success "  ✓ Processed (Spring Boot variables preserved)"
  else
    log_success "  ✓ Processed"
  fi
  
  # Check if any of our variables remain unreplaced
  if grep -qE '\${(DB_|MS_|KEYSTORE_|EUREKA_|DATAVERSE_)' "$PROP_FILE"; then
    log_warning "  ⚠ Some deployment variables may not have been replaced"
  fi
done

echo ""
log_info "Verifying preserved Spring Boot variables..."

# Count Spring Boot variables that should be preserved
SPRING_VARS=$(grep -h '\${server\.' config/*/*.properties 2>/dev/null | wc -l)
if [ "$SPRING_VARS" -gt 0 ]; then
  log_success "Preserved $SPRING_VARS Spring Boot property references"
else
  log_warning "No Spring Boot variables found (this might be unexpected)"
fi

echo ""
echo "========================================="
echo "✓ Properties files prepared!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Processed $TOTAL microservice properties files"
echo "  - Created .template backups (if not existing)"
echo "  - Replaced deployment-specific variables only"
echo "  - Preserved Spring Boot property references"
echo ""
echo "Variables replaced:"
echo "  - Database passwords: DB_ACL, DB_KALIM, etc."
echo "  - OAuth2 secrets: MS_ACL, MS_KALIM, etc."
echo "  - Keystore passwords: KEYSTORE_PASSWORD, etc."
echo "  - Application: EUREKA_PASSWORD, DATAVERSE_API_TOKEN"
echo "  - SMTP: SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, etc."
echo ""
echo "Variables preserved (examples):"
echo "  - \${server.ssl.key-store-password}"
echo "  - \${spring.application.name}"
echo "  - \${random.uuid}"
echo "  - \${base_dn} (Spring property reference)"
echo ""
