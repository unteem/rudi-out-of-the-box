#!/bin/bash
# generate-passwords.sh - Generate secure random passwords for RUDI platform
#
# Appends generated secrets to .env so Docker Compose can load them
# automatically without any --env-file flags.
#
# Prerequisites: .env must exist (copy from .env.example)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found."
  echo "Copy the template first: cp .env.example .env"
  exit 1
fi

echo "========================================="
echo "Generating Secure Passwords"
echo "========================================="
echo ""

# Function to generate a secure random password
generate_password() {
  openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to generate UUID
generate_uuid() {
  if command -v uuidgen &> /dev/null; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

echo "Generating passwords..."
echo ""

# Database passwords
echo "[1/4] Generating database passwords..."
DB_RUDI=$(generate_password)
DB_DATAVERSE=$(generate_password)
DB_MAGNOLIA=$(generate_password)
DB_ACL=$(generate_password)
DB_APIGATEWAY=$(generate_password)
DB_KALIM=$(generate_password)
DB_KONSENT=$(generate_password)
DB_KOS=$(generate_password)
DB_PROJEKT=$(generate_password)
DB_SELFDATA=$(generate_password)
DB_STRUKTURE=$(generate_password)
DB_TEMPLATE=$(generate_password)

# Microservice OAuth2 client secrets
echo "[2/4] Generating microservice OAuth2 secrets..."
MS_ACL=$(generate_password)
MS_APIGATEWAY=$(generate_password)
MS_KALIM=$(generate_password)
MS_KONSENT=$(generate_password)
MS_KONSULT=$(generate_password)
MS_KOS=$(generate_password)
MS_PROJEKT=$(generate_password)
MS_SELFDATA=$(generate_password)
MS_STRUKTURE=$(generate_password)

# Application passwords and tokens
echo "[3/4] Generating application credentials..."
EUREKA_USER="admin"
EUREKA_PASSWORD=$(generate_password)
DATAVERSE_ADMIN_PASSWORD=$(generate_password)
KEYSTORE_PASSWORD=$(generate_password)
CONSENT_KEYSTORE_PASSWORD=$(generate_password)
SELFDATA_KEYSTORE_PASSWORD=$(generate_password)
APIGATEWAY_KEYSTORE_PASSWORD=$(generate_password)
JWT_KEYSTORE_PASSWORD=$(generate_password)

# Spring Security admin passwords
ADMIN_REGISTRY=$(generate_password)
ADMIN_GATEWAY=$(generate_password)
ADMIN_APIGATEWAY=$(generate_password)

# Salt values for hashing
CONSENT_VALIDATE_SALT=$(generate_password)
CONSENT_REVOKE_SALT=$(generate_password)
TREATMENTVERSION_PUBLISH_SALT=$(generate_password)

# Append to .env — remove any previously generated secrets first
echo "[4/4] Writing secrets to $ENV_FILE..."

# Strip previously generated secrets block if re-running
sed -i '/^# ===* Generated secrets/,/^# ===* End generated secrets/d' "$ENV_FILE" 2>/dev/null || true

cat >> "$ENV_FILE" << EOF

# ============================================================
# Generated secrets — do not edit manually
# Generated on: $(date)
# ============================================================

# Database passwords
DB_RUDI=$DB_RUDI
DB_DATAVERSE=$DB_DATAVERSE
DB_MAGNOLIA=$DB_MAGNOLIA
DB_ACL=$DB_ACL
DB_APIGATEWAY=$DB_APIGATEWAY
DB_KALIM=$DB_KALIM
DB_KONSENT=$DB_KONSENT
DB_KOS=$DB_KOS
DB_PROJEKT=$DB_PROJEKT
DB_SELFDATA=$DB_SELFDATA
DB_STRUKTURE=$DB_STRUKTURE
DB_TEMPLATE=$DB_TEMPLATE

# Microservice OAuth2 client secrets
MS_ACL=$MS_ACL
MS_APIGATEWAY=$MS_APIGATEWAY
MS_KALIM=$MS_KALIM
MS_KONSENT=$MS_KONSENT
MS_KONSULT=$MS_KONSULT
MS_KOS=$MS_KOS
MS_PROJEKT=$MS_PROJEKT
MS_SELFDATA=$MS_SELFDATA
MS_STRUKTURE=$MS_STRUKTURE

# Application credentials
EUREKA_USER=$EUREKA_USER
EUREKA_PASSWORD=$EUREKA_PASSWORD
DATAVERSE_ADMIN_PASSWORD=$DATAVERSE_ADMIN_PASSWORD
# Renseigné par init-dataverse.sh
DATAVERSE_API_TOKEN=

# Keystore passwords
KEYSTORE_PASSWORD=$KEYSTORE_PASSWORD
CONSENT_KEYSTORE_PASSWORD=$CONSENT_KEYSTORE_PASSWORD
SELFDATA_KEYSTORE_PASSWORD=$SELFDATA_KEYSTORE_PASSWORD
APIGATEWAY_KEYSTORE_PASSWORD=$APIGATEWAY_KEYSTORE_PASSWORD
JWT_KEYSTORE_PASSWORD=$JWT_KEYSTORE_PASSWORD

# Spring Security admin passwords
ADMIN_REGISTRY=$ADMIN_REGISTRY
ADMIN_GATEWAY=$ADMIN_GATEWAY
ADMIN_APIGATEWAY=$ADMIN_APIGATEWAY

# Salt values for hashing
CONSENT_VALIDATE_SALT=$CONSENT_VALIDATE_SALT
CONSENT_REVOKE_SALT=$CONSENT_REVOKE_SALT
TREATMENTVERSION_PUBLISH_SALT=$TREATMENTVERSION_PUBLISH_SALT

# ============================================================
# End generated secrets
# ============================================================
EOF

chmod 600 "$ENV_FILE"

echo ""
echo "========================================="
echo "✓ Passwords generated successfully!"
echo "========================================="
echo ""
echo "Secrets written to: $ENV_FILE"
echo ""
echo "IMPORTANT: Back up .env securely — it contains all secrets."
echo "  gpg -c $ENV_FILE"
echo ""
echo "Next: ./scripts/generate-ssl-keystores.sh"
echo ""
