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
if [ ! -f ".env" ]; then
  log_error ".env not found!"
  echo "Copy the template first: cp .env.example .env"
  exit 1
fi

# Source and export all variables so envsubst child process can see them
set -a; source .env; set +a

# Source SMTP configuration if exists
if [ -f ".env.smtp" ]; then
  log_info "Loading SMTP configuration from .env.smtp"
  set -a; source .env.smtp; set +a
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

export MS_ACL MS_APIGATEWAY MS_KALIM MS_KONSENT MS_KONSULT MS_KOS \
       MS_PROJEKT MS_SELFDATA MS_STRUKTURE

export KEYSTORE_PASSWORD CONSENT_KEYSTORE_PASSWORD \
       SELFDATA_KEYSTORE_PASSWORD APIGATEWAY_KEYSTORE_PASSWORD

export EUREKA_USER EUREKA_PASSWORD DATAVERSE_API_TOKEN

export ADMIN_REGISTRY ADMIN_GATEWAY ADMIN_APIGATEWAY

export CONSENT_VALIDATE_SALT CONSENT_REVOKE_SALT \
       TREATMENTVERSION_PUBLISH_SALT

export SMTP_HOST SMTP_PORT SMTP_AUTH SMTP_STARTTLS \
       SMTP_USERNAME SMTP_PASSWORD SMTP_FROM

export base_dn

# Spring Boot lit les .properties en ISO-8859-1 : les caractères non ASCII
# (accents) sont écrits sous forme d'échappements \uXXXX
properties_escape() {
  printf '%s' "$1" | python3 -c 'import sys; print("".join(c if ord(c) < 128 else "\\u%04x" % ord(c) for c in sys.stdin.read()), end="")'
}

# Personnalisation du portail (valeurs par défaut si absentes de .env)
export RUDI_TEAM_NAME="$(properties_escape "${RUDI_TEAM_NAME:-RUDI}")"
export RUDI_PROJECT_NAME="$(properties_escape "${RUDI_PROJECT_NAME:-RUDI}")"
export RUDI_CONTACT_URL="${RUDI_CONTACT_URL:-mailto:${LETSENCRYPT_EMAIL}}"

# Stockage S3 de konsent (optionnel)
export KONSENT_S3_ENDPOINT="${KONSENT_S3_ENDPOINT:-}"
export KONSENT_S3_BUCKET="${KONSENT_S3_BUCKET:-}"
export KONSENT_S3_ACCESS_KEY="${KONSENT_S3_ACCESS_KEY:-}"
export KONSENT_S3_SECRET_KEY="${KONSENT_S3_SECRET_KEY:-}"
export KONSENT_S3_TRUST_ALL_CERTS="${KONSENT_S3_TRUST_ALL_CERTS:-false}"
if [ -z "$KONSENT_S3_ENDPOINT" ]; then
  log_warning "KONSENT_S3_ENDPOINT vide : les consentements (konsent) ne pourront pas être enregistrés"
fi

# List of variables to replace (CRITICAL: only these will be replaced)
# This prevents envsubst from replacing Spring Boot variables like ${server.ssl.key-store-password}
ENVSUBST_VARS='$DB_ACL $DB_APIGATEWAY $DB_KALIM $DB_KONSENT $DB_KOS $DB_PROJEKT $DB_SELFDATA $DB_STRUKTURE'
ENVSUBST_VARS="$ENVSUBST_VARS "'$MS_ACL $MS_APIGATEWAY $MS_KALIM $MS_KONSENT $MS_KONSULT $MS_KOS $MS_PROJEKT $MS_SELFDATA $MS_STRUKTURE'
ENVSUBST_VARS="$ENVSUBST_VARS "'$KEYSTORE_PASSWORD $CONSENT_KEYSTORE_PASSWORD $SELFDATA_KEYSTORE_PASSWORD $APIGATEWAY_KEYSTORE_PASSWORD $JWT_KEYSTORE_PASSWORD'
ENVSUBST_VARS="$ENVSUBST_VARS "'$EUREKA_USER $EUREKA_PASSWORD $DATAVERSE_API_TOKEN'
ENVSUBST_VARS="$ENVSUBST_VARS "'$ADMIN_REGISTRY $ADMIN_GATEWAY $ADMIN_APIGATEWAY'
ENVSUBST_VARS="$ENVSUBST_VARS "'$CONSENT_VALIDATE_SALT $CONSENT_REVOKE_SALT $TREATMENTVERSION_PUBLISH_SALT'
ENVSUBST_VARS="$ENVSUBST_VARS "'$SMTP_HOST $SMTP_PORT $SMTP_AUTH $SMTP_STARTTLS $SMTP_USERNAME $SMTP_PASSWORD $SMTP_FROM'
ENVSUBST_VARS="$ENVSUBST_VARS "'$base_dn'
ENVSUBST_VARS="$ENVSUBST_VARS "'$RUDI_TEAM_NAME $RUDI_PROJECT_NAME $RUDI_CONTACT_URL'
ENVSUBST_VARS="$ENVSUBST_VARS "'$KONSENT_S3_ENDPOINT $KONSENT_S3_BUCKET $KONSENT_S3_ACCESS_KEY $KONSENT_S3_SECRET_KEY $KONSENT_S3_TRUST_ALL_CERTS'

log_info "Processing microservice properties files..."
echo ""

# List of microservices
SERVICES=(acl apigateway gateway kalim konsent kos konsult projekt selfdata strukture registry)

TOTAL=${#SERVICES[@]}
CURRENT=0

for service in "${SERVICES[@]}"; do
  CURRENT=$((CURRENT + 1))
  PROP_FILE="$ROOT_DIR/config/$service/${service}.properties"
  
  echo "[$CURRENT/$TOTAL] Processing $service..."

  # Process with envsubst - ONLY replacing our specific variables
  envsubst "$ENVSUBST_VARS" < "${PROP_FILE}.template" > "$PROP_FILE"

done

echo ""
echo "========================================="
echo "✓ Properties files prepared!"
echo "========================================="
echo ""
echo "Processed $TOTAL microservice properties files."
echo ""
echo "Next: ./scripts/prepare-database-init.sh"
echo ""
