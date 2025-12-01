#!/bin/bash
# update-configs.sh - Update RUDI configuration files with generated passwords
#
# This script updates all configuration files with passwords from .passwords.env
# WARNING: This will modify configuration files in place

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Updating Configuration Files"
echo "========================================="
echo ""

# Check if passwords file exists
if [ ! -f "$ROOT_DIR/.passwords.env" ]; then
  echo "ERROR: .passwords.env not found!"
  echo "Please run generate-passwords.sh first"
  exit 1
fi

# Source passwords
source "$ROOT_DIR/.passwords.env"
source "$ROOT_DIR/.env"

echo "WARNING: This will modify configuration files in place!"
echo "A backup will be created first."
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Create backup
BACKUP_DIR="$ROOT_DIR/config-backup-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup: $BACKUP_DIR"
cp -r "$ROOT_DIR/config" "$BACKUP_DIR"

# Function to update property file
update_property() {
  local file=$1
  local key=$2
  local value=$3
  
  if [ -f "$file" ]; then
    # Escape special characters in value
    escaped_value=$(echo "$value" | sed 's/[\/&]/\\&/g')
    
    # Update or add property
    if grep -q "^${key}=" "$file"; then
      sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$file"
    else
      echo "${key}=${escaped_value}" >> "$file"
    fi
  fi
}

echo ""
echo "[1/5] Updating database initialization scripts..."

# Update 01-usr.sql
if [ -f "$ROOT_DIR/config/rudi-init/01-usr.sql" ]; then
  sed -i "s/Rud1R00B-db-acl/${DB_ACL}/g" "$ROOT_DIR/config/rudi-init/01-usr.sql"
  sed -i "s/Rud1R00B-db-kalim/${DB_KALIM}/g" "$ROOT_DIR/config/rudi-init/01-usr.sql"
  sed -i "s/Rud1R00B-db-konsent/${DB_KONSENT}/g" "$ROOT_DIR/config/rudi-init/01-usr.sql"
  sed -i "s/Rud1R00B-db-kos/${DB_KOS}/g" "$ROOT_DIR/config/rudi-init/01-usr.sql"
  sed -i "s/Rud1R00B-db-selfdata/${DB_SELFDATA}/g" "$ROOT_DIR/config/rudi-init/01-usr.sql"
  sed -i "s/Rud1R00B-db-strukture/${DB_STRUKTURE}/g" "$ROOT_DIR/config/rudi-init/01-usr.sql"
  sed -i "s/Rud1R00B-db-projekt/${DB_PROJEKT}/g" "$ROOT_DIR/config/rudi-init/01-usr.sql"
  sed -i "s/Rud1R00B-db-apigateway/${DB_APIGATEWAY}/g" "$ROOT_DIR/config/rudi-init/01-usr.sql"
  echo "  ✓ Updated 01-usr.sql"
fi

echo ""
echo "[2/5] Updating Docker Compose files..."

# Update docker-compose-rudi.yml
if [ -f "$ROOT_DIR/docker-compose-rudi.yml" ]; then
  sed -i "s/POSTGRES_PASSWORD=Rud1R00B-db-rudi/POSTGRES_PASSWORD=${DB_RUDI}/g" "$ROOT_DIR/docker-compose-rudi.yml"
  echo "  ✓ Updated docker-compose-rudi.yml"
fi

# Update docker-compose-dataverse.yml
if [ -f "$ROOT_DIR/docker-compose-dataverse.yml" ]; then
  sed -i "s/POSTGRES_PASSWORD=Rud1R00B-db-dataverse/POSTGRES_PASSWORD=${DB_DATAVERSE}/g" "$ROOT_DIR/docker-compose-dataverse.yml"
  sed -i "s/DATAVERSE_DB_PASSWORD=Rud1R00B-db-dataverse/DATAVERSE_DB_PASSWORD=${DB_DATAVERSE}/g" "$ROOT_DIR/docker-compose-dataverse.yml"
  echo "  ✓ Updated docker-compose-dataverse.yml"
fi

# Update docker-compose-magnolia.yml
if [ -f "$ROOT_DIR/docker-compose-magnolia.yml" ]; then
  sed -i "s/POSTGRES_PASSWORD=Rud1R00B-db-magnolia/POSTGRES_PASSWORD=${DB_MAGNOLIA}/g" "$ROOT_DIR/docker-compose-magnolia.yml"
  sed -i "s/MAGNOLIA_BDD_PASSWORD=Rud1R00B-db-magnolia/MAGNOLIA_BDD_PASSWORD=${DB_MAGNOLIA}/g" "$ROOT_DIR/docker-compose-magnolia.yml"
  echo "  ✓ Updated docker-compose-magnolia.yml"
fi

echo ""
echo "[3/5] Updating microservice property files..."

# List of microservices
SERVICES=(acl apigateway gateway kalim konsent kos konsult projekt selfdata strukture)

for service in "${SERVICES[@]}"; do
  PROP_FILE="$ROOT_DIR/config/$service/${service}.properties"
  
  if [ ! -f "$PROP_FILE" ]; then
    echo "  ⚠ Skipping $service (file not found)"
    continue
  fi
  
  echo "  Updating $service..."
  
  # Update database password
  DB_PASSWORD_VAR="DB_${service^^}"
  update_property "$PROP_FILE" "spring.datasource.password" "${!DB_PASSWORD_VAR}"
  
  # Update OAuth2 client secret
  MS_PASSWORD_VAR="MS_${service^^}"
  update_property "$PROP_FILE" "module.oauth2.client-secret" "${!MS_PASSWORD_VAR}"
  
  # Update keystore password
  update_property "$PROP_FILE" "server.ssl.key-store-password" "$KEYSTORE_PASSWORD"
  update_property "$PROP_FILE" "eureka.client.tls.key-password" "$KEYSTORE_PASSWORD"
  update_property "$PROP_FILE" "eureka.client.tls.key-store-password" "$KEYSTORE_PASSWORD"
  update_property "$PROP_FILE" "eureka.client.tls.trust-store-password" "$KEYSTORE_PASSWORD"
  
  # Update Eureka URL with new password
  update_property "$PROP_FILE" "eureka.client.serviceURL.defaultZone" "https://${EUREKA_USER}:${EUREKA_PASSWORD}@registry:8761/eureka"
  
  # Disable trust-all-certs for production
  update_property "$PROP_FILE" "trust.trust-all-certs" "false"
  update_property "$PROP_FILE" "module.oauth2.trust-all-certs" "false"
done

# Special updates for specific services
echo ""
echo "[4/5] Updating service-specific configurations..."

# Konsent - PDF signing keystore
if [ -f "$ROOT_DIR/config/konsent/konsent.properties" ]; then
  update_property "$ROOT_DIR/config/konsent/konsent.properties" "rudi.pdf.sign.keyStorePassword" "$CONSENT_KEYSTORE_PASSWORD"
  update_property "$ROOT_DIR/config/konsent/konsent.properties" "rudi.pdf.sign.keyStoreKeyPassword" "$CONSENT_KEYSTORE_PASSWORD"
  update_property "$ROOT_DIR/config/konsent/konsent.properties" "rudi.consent.validate.sha.salt" "$CONSENT_VALIDATE_SALT"
  update_property "$ROOT_DIR/config/konsent/konsent.properties" "rudi.consent.revoke.sha.salt" "$CONSENT_REVOKE_SALT"
  update_property "$ROOT_DIR/config/konsent/konsent.properties" "rudi.treatmentversion.publish.sha.salt" "$TREATMENTVERSION_PUBLISH_SALT"
  echo "  ✓ Updated konsent special properties"
fi

# Selfdata - matching data keystore
if [ -f "$ROOT_DIR/config/selfdata/selfdata.properties" ]; then
  update_property "$ROOT_DIR/config/selfdata/selfdata.properties" "rudi.selfdata.matchingdata.keystore.keystore-password" "$SELFDATA_KEYSTORE_PASSWORD"
  echo "  ✓ Updated selfdata special properties"
fi

# Apigateway - encryption key
if [ -f "$ROOT_DIR/config/apigateway/apigateway.properties" ]; then
  update_property "$ROOT_DIR/config/apigateway/apigateway.properties" "encryption-key.jks.default-key-password" "$APIGATEWAY_KEYSTORE_PASSWORD"
  echo "  ✓ Updated apigateway special properties"
fi

# Strukture - Dataverse API token
if [ -f "$ROOT_DIR/config/strukture/strukture.properties" ]; then
  update_property "$ROOT_DIR/config/strukture/strukture.properties" "dataverse.api.token" "$DATAVERSE_API_TOKEN"
  echo "  ✓ Updated strukture special properties"
fi

# Registry
if [ -f "$ROOT_DIR/config/registry/registry.properties" ]; then
  update_property "$ROOT_DIR/config/registry/registry.properties" "eureka.password" "$EUREKA_PASSWORD"
  echo "  ✓ Updated registry properties"
fi

echo ""
echo "[5/5] Creating environment override file..."

# Create .env.local for Docker Compose to use
cat > "$ROOT_DIR/.env.local" << EOF
# Auto-generated environment overrides
# Source: update-configs.sh on $(date)

# Database passwords
POSTGRES_PASSWORD_RUDI=${DB_RUDI}
POSTGRES_PASSWORD_DATAVERSE=${DB_DATAVERSE}
POSTGRES_PASSWORD_MAGNOLIA=${DB_MAGNOLIA}

# Dataverse
DATAVERSE_API_TOKEN=${DATAVERSE_API_TOKEN}

# Application
EUREKA_PASSWORD=${EUREKA_PASSWORD}
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD}
EOF

chmod 600 "$ROOT_DIR/.env.local"
echo "  ✓ Created .env.local"

echo ""
echo "========================================="
echo "✓ Configuration update complete!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Backup created: $BACKUP_DIR"
echo "  - Updated database init scripts"
echo "  - Updated Docker Compose files"
echo "  - Updated ${#SERVICES[@]} microservice configurations"
echo "  - Created .env.local for environment overrides"
echo ""
echo "What was changed:"
echo "  ✓ All database passwords"
echo "  ✓ All OAuth2 client secrets"
echo "  ✓ All keystore passwords"
echo "  ✓ Eureka credentials"
echo "  ✓ Dataverse API token"
echo "  ✓ Security settings (disabled trust-all-certs)"
echo "  ✓ Special keystore passwords (consent, selfdata, apigateway)"
echo ""
echo "Next steps:"
echo "  1. Review changes: diff -r $BACKUP_DIR config/"
echo "  2. Deploy platform: docker compose up -d"
echo "  3. Verify all services start correctly"
echo "  4. Change application user passwords via UI/database"
echo ""
echo "IMPORTANT:"
echo "  - If deployment fails, restore from backup:"
echo "    rm -rf config && mv $BACKUP_DIR config"
echo ""
