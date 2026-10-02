#!/bin/bash
# generate-ssl-keystores.sh - Generate SSL keystores for RUDI microservices
#
# This script converts PEM SSL certificates to Java KeyStore (JKS) format
# Required for Spring Boot microservices

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Generating SSL Keystores"
echo "========================================="
echo ""

# Check for required tools
if ! command -v keytool &> /dev/null; then
  echo "ERROR: keytool not found!"
  echo ""
  echo "keytool is part of Java JDK. Install it with:"
  echo ""
  echo "  # Debian/Ubuntu:"
  echo "  sudo apt install openjdk-17-jdk"
  echo ""
  echo "  # Or:"
  echo "  sudo apt install default-jdk"
  echo ""
  echo "After installation, verify:"
  echo "  keytool -version"
  exit 1
fi

if ! command -v openssl &> /dev/null; then
  echo "ERROR: openssl not found!"
  echo ""
  echo "Install OpenSSL with:"
  echo "  sudo apt install openssl"
  exit 1
fi

echo "✓ Found keytool: $(which keytool)"
echo "✓ Found openssl: $(which openssl)"
echo ""

# Check .env exists and source it
if [ ! -f "$ROOT_DIR/.env" ]; then
  echo "ERROR: .env not found!"
  echo "Copy the template first: cp .env.example .env"
  exit 1
fi

set -a; source "$ROOT_DIR/.env"; set +a

# Default certificate location (adjust for your setup)
CERT_DIR="${CERT_DIR:-$ROOT_DIR/certs}"
CERT_FILE="${CERT_FILE:-$CERT_DIR/fullchain.pem}"
KEY_FILE="${KEY_FILE:-$CERT_DIR/privkey.pem}"

echo "Configuration:"
echo "  Domain: $base_dn"
echo "  Certificate directory: $CERT_DIR"
echo "  Certificate file: $CERT_FILE"
echo "  Key file: $KEY_FILE"
echo ""

# Generate internal self-signed certificate if not already present.
# These certs are used ONLY for inter-service HTTPS inside the Docker network —
# never exposed to end users. Traefik handles public TLS via Let's Encrypt.
# Self-signed is perfectly fine here.
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  echo "No certificates found in $CERT_DIR — generating self-signed certificate for internal use..."
  mkdir -p "$CERT_DIR"
  openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/CN=rudi.$base_dn/O=RUDI Platform/C=FR" \
    -addext "subjectAltName=DNS:registry,DNS:acl,DNS:apigateway,DNS:gateway,DNS:kalim,DNS:konsent,DNS:konsult,DNS:kos,DNS:projekt,DNS:selfdata,DNS:strukture,DNS:localhost,DNS:rudi.$base_dn,DNS:dataverse.$base_dn,DNS:magnolia.$base_dn,DNS:*.$base_dn" \
    2>/dev/null
  echo "  ✓ Self-signed certificate generated (10 years validity)"
fi

# List of services that need SSL keystores
SERVICES=(acl apigateway gateway kalim konsent kos konsult projekt selfdata strukture registry)

TOTAL=${#SERVICES[@]}
CURRENT=0

for service in "${SERVICES[@]}"; do
  CURRENT=$((CURRENT + 1))
  echo "[$CURRENT/$TOTAL] Creating keystore for $service..."
  
  SERVICE_DIR="$ROOT_DIR/config/$service"
  FINAL_JKS="$SERVICE_DIR/rudi-https-certificate.jks"
  
  # Use service-specific password or default
  PASSWORD="${KEYSTORE_PASSWORD}"
  
  # Direct conversion from PEM to PKCS12 keystore with .jks extension
  # Modern Java (8+) supports PKCS12 keystores with .jks extension
  openssl pkcs12 -export \
    -in "$CERT_FILE" \
    -inkey "$KEY_FILE" \
    -out "$FINAL_JKS" \
    -name "rudi-https" \
    -password "pass:$PASSWORD" \
    2>/dev/null
  
  if [ $? -ne 0 ]; then
    echo "  ✗ Failed to create keystore for $service"
    echo "  Check that certificate and key files are valid"
    continue
  fi
  
  # Set proper permissions
  chmod 600 "$FINAL_JKS"
  
  echo "  ✓ Keystore created: config/$service/rudi-https-certificate.jks"
done

# Special keystores for specific services
#
# These hold application keys (consent signing, personal data encryption,
# media key encryption, JWT signing). Regenerating them makes previously
# encrypted/signed data unreadable, so existing keystores are never overwritten.
# Delete the file explicitly to force regeneration.
echo ""
echo "Creating application keystores..."

# generate_app_keystore <path> <alias> <password> <dname> <keysize>
generate_app_keystore() {
  local jks=$1 alias=$2 password=$3 dname=$4 keysize=$5
  if [ -f "$jks" ]; then
    echo "  = ${jks#$ROOT_DIR/} already exists — kept"
    return
  fi
  keytool -genkeypair \
    -alias "$alias" \
    -keyalg RSA \
    -keysize "$keysize" \
    -validity 3650 \
    -keystore "$jks" \
    -storepass "$password" \
    -keypass "$password" \
    -storetype PKCS12 \
    -dname "$dname" \
    2>&1 | grep -v "Warning" || true
  if [ -f "$jks" ]; then
    chmod 600 "$jks"
    echo "  ✓ ${jks#$ROOT_DIR/} created (alias: $alias)"
  else
    echo "  ✗ Failed to create ${jks#$ROOT_DIR/}"
    exit 1
  fi
}

# Konsent: consent PDF signing
generate_app_keystore "$ROOT_DIR/config/konsent/rudi-consent.jks" "rudi-consent" \
  "$CONSENT_KEYSTORE_PASSWORD" "CN=RUDI Consent,OU=Consent Management,O=RUDI Platform,C=FR" 4096

# Selfdata: personal data encryption
generate_app_keystore "$ROOT_DIR/config/selfdata/rudi-selfdata.jks" "rudi-selfdata" \
  "$SELFDATA_KEYSTORE_PASSWORD" "CN=RUDI Selfdata,OU=Personal Data,O=RUDI Platform,C=FR" 4096

# Apigateway: media access key encryption (replaces the dev keystore bundled in the jar)
generate_app_keystore "$ROOT_DIR/config/apigateway/rudi-apigateway.jks" "defaultkey" \
  "$APIGATEWAY_KEYSTORE_PASSWORD" "CN=RUDI Apigateway,OU=Data Encryption,O=RUDI Platform,C=FR" 4096

# ACL: JWT signing (security.jwt.keystore). Without it, ACL generates a random
# key at each startup and all tokens are invalidated on restart.
generate_app_keystore "$ROOT_DIR/config/acl/rudi-jwt.jks" "rudi-jwt" \
  "$JWT_KEYSTORE_PASSWORD" "CN=RUDI JWT,OU=Authentication,O=RUDI Platform,C=FR" 2048

# Save keystore passwords reference
cat > "$ROOT_DIR/.keystore-info.txt" << EOF
SSL Keystore Information
========================
Generated: $(date)

SSL Certificate:
  Source: $CERT_FILE
  Valid for: rudi.$base_dn, dataverse.$base_dn, magnolia.$base_dn

Keystore Passwords:
  Main SSL: \$KEYSTORE_PASSWORD (from .env)
  Consent: \$CONSENT_KEYSTORE_PASSWORD
  Selfdata: \$SELFDATA_KEYSTORE_PASSWORD
  Apigateway: \$APIGATEWAY_KEYSTORE_PASSWORD
  JWT (ACL): \$JWT_KEYSTORE_PASSWORD
  
All keystores use alias: rudi-https (or service-specific)
All keystores use PKCS12 format (compatible with modern Java)

To view keystore contents:
  keytool -list -v -keystore config/[service]/rudi-https-certificate.jks \
    -storepass \$KEYSTORE_PASSWORD
EOF

chmod 600 "$ROOT_DIR/.keystore-info.txt"

echo ""
echo "========================================="
echo "✓ All keystores generated successfully!"
echo "========================================="
echo ""
echo "Generated $TOTAL SSL keystores + application keystores (consent, selfdata, apigateway, JWT)."
echo "Keystore info saved to: .keystore-info.txt"
echo ""
echo "Next: ./scripts/prepare-properties.sh"
echo ""
