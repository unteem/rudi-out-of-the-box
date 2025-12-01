#!/bin/bash
# generate-passwords.sh - Generate secure random passwords for RUDI platform
#
# This script generates cryptographically secure passwords for:
# - Database users
# - Microservice OAuth2 clients
# - Application components (Eureka, Dataverse, etc.)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="$ROOT_DIR/.passwords.env"

echo "========================================="
echo "Generating Secure Passwords"
echo "========================================="
echo ""

# Function to generate a secure random password
generate_password() {
  # Generate 32-character base64 password, removing special chars that might cause issues
  openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to generate UUID
generate_uuid() {
  if command -v uuidgen &> /dev/null; then
    uuidgen
  else
    # Fallback if uuidgen not available
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

# Microservice OAuth2 client secrets
echo "[2/4] Generating microservice OAuth2 secrets..."
MS_ACL=$(generate_password)
MS_APIGATEWAY=$(generate_password)
MS_KALIM=$(generate_password)
MS_KONSENT=$(generate_password)
MS_KOS=$(generate_password)
MS_PROJEKT=$(generate_password)
MS_SELFDATA=$(generate_password)
MS_STRUKTURE=$(generate_password)

# Application passwords and tokens
echo "[3/4] Generating application credentials..."
EUREKA_PASSWORD=$(generate_password)
EUREKA_USER="admin"
DATAVERSE_API_TOKEN=$(generate_uuid)
KEYSTORE_PASSWORD=$(generate_password)
CONSENT_KEYSTORE_PASSWORD=$(generate_password)
SELFDATA_KEYSTORE_PASSWORD=$(generate_password)
APIGATEWAY_KEYSTORE_PASSWORD=$(generate_password)

# Salt values for hashing
CONSENT_VALIDATE_SALT=$(generate_password)
CONSENT_REVOKE_SALT=$(generate_password)
TREATMENTVERSION_PUBLISH_SALT=$(generate_password)

# Save to file
echo "[4/4] Saving passwords to $OUTPUT_FILE..."

cat > "$OUTPUT_FILE" << EOF
# =========================================
# RUDI Platform Passwords
# Generated on: $(date)
# =========================================
# 
# KEEP THIS FILE SECURE!
# - DO NOT commit to version control
# - Store in a secure password manager
# - Restrict file permissions (chmod 600)
# - Create encrypted backups
#
# =========================================

# =======================================
# Database Passwords
# =======================================
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

# =======================================
# Microservice OAuth2 Client Secrets
# =======================================
MS_ACL=$MS_ACL
MS_APIGATEWAY=$MS_APIGATEWAY
MS_KALIM=$MS_KALIM
MS_KONSENT=$MS_KONSENT
MS_KOS=$MS_KOS
MS_PROJEKT=$MS_PROJEKT
MS_SELFDATA=$MS_SELFDATA
MS_STRUKTURE=$MS_STRUKTURE

# =======================================
# Application Credentials
# =======================================
EUREKA_USER=$EUREKA_USER
EUREKA_PASSWORD=$EUREKA_PASSWORD
DATAVERSE_API_TOKEN=$DATAVERSE_API_TOKEN

# =======================================
# Keystore Passwords
# =======================================
KEYSTORE_PASSWORD=$KEYSTORE_PASSWORD
CONSENT_KEYSTORE_PASSWORD=$CONSENT_KEYSTORE_PASSWORD
SELFDATA_KEYSTORE_PASSWORD=$SELFDATA_KEYSTORE_PASSWORD
APIGATEWAY_KEYSTORE_PASSWORD=$APIGATEWAY_KEYSTORE_PASSWORD

# =======================================
# Salt Values for Hashing
# =======================================
CONSENT_VALIDATE_SALT=$CONSENT_VALIDATE_SALT
CONSENT_REVOKE_SALT=$CONSENT_REVOKE_SALT
TREATMENTVERSION_PUBLISH_SALT=$TREATMENTVERSION_PUBLISH_SALT

# =======================================
# Connection Strings (for reference)
# =======================================
# Main RUDI Database:
#   Host: database:5432
#   Database: rudi
#   User: rudi
#   Password: \$DB_RUDI
#
# Dataverse Database:
#   Host: dataverse-database:5432
#   Database: dataverse
#   User: dataverse
#   Password: \$DB_DATAVERSE
#
# Magnolia Database:
#   Host: magnolia-database:5432
#   Database: magnolia
#   User: magnolia
#   Password: \$DB_MAGNOLIA
#
# Eureka Registry:
#   URL: https://\$EUREKA_USER:\$EUREKA_PASSWORD@registry:8761/eureka
#
# =======================================
EOF

# Set restrictive permissions
chmod 600 "$OUTPUT_FILE"

echo ""
echo "========================================="
echo "✓ Passwords generated successfully!"
echo "========================================="
echo ""
echo "File location: $OUTPUT_FILE"
echo "File permissions: $(stat -c '%a' "$OUTPUT_FILE")"
echo ""
echo "IMPORTANT SECURITY NOTES:"
echo "1. This file contains sensitive credentials"
echo "2. Store in a secure password manager immediately"
echo "3. Never commit this file to version control"
echo "4. Add to .gitignore: echo '.passwords.env' >> .gitignore"
echo "5. Create encrypted backup: gpg -c $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "1. Source the file: source $OUTPUT_FILE"
echo "2. Run update-configs.sh to apply passwords"
echo ""
