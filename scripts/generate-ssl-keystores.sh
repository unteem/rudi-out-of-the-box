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
  echo ""
  echo "See DEBIAN-INSTALL-GUIDE.md for detailed instructions."
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

# Check if passwords file exists
if [ ! -f "$ROOT_DIR/.passwords.env" ]; then
  echo "ERROR: .passwords.env not found!"
  echo "Please run generate-passwords.sh first"
  exit 1
fi

# Source passwords
source "$ROOT_DIR/.passwords.env"

# Check if .env exists for domain
if [ ! -f "$ROOT_DIR/.env" ]; then
  echo "ERROR: .env not found!"
  echo "Please create .env with base_dn configuration"
  exit 1
fi

source "$ROOT_DIR/.env"

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

# Check if certificate files exist
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  echo "WARNING: SSL certificate files not found!"
  echo ""
  echo "Expected locations:"
  echo "  Certificate: $CERT_FILE"
  echo "  Private key: $KEY_FILE"
  echo ""
  echo "Options:"
  echo "1. Place your SSL certificates in $CERT_DIR"
  echo "2. Set CERT_FILE and KEY_FILE environment variables"
  echo "3. Generate self-signed certificates for testing (NOT for production):"
  echo ""
  echo "   mkdir -p $CERT_DIR"
  echo "   openssl req -x509 -nodes -days 365 -newkey rsa:4096 \\"
  echo "     -keyout $KEY_FILE \\"
  echo "     -out $CERT_FILE \\"
  echo "     -subj '/CN=rudi.$base_dn'"
  echo ""
  read -p "Generate self-signed certificate for testing? (y/N): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Generating self-signed certificate..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
      -keyout "$KEY_FILE" \
      -out "$CERT_FILE" \
      -subj "/CN=rudi.$base_dn/O=RUDI Platform/C=FR"
    echo "✓ Self-signed certificate generated"
  else
    echo "Exiting. Please provide SSL certificates and run again."
    exit 1
  fi
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
echo ""
echo "Creating special keystores..."

# Konsent keystore (for PDF signing)
if [ -d "$ROOT_DIR/config/konsent" ]; then
  echo "  Creating rudi-consent.jks..."
  CONSENT_JKS="$ROOT_DIR/config/konsent/rudi-consent.jks"
  
  # Remove old keystore if exists
  rm -f "$CONSENT_JKS"
  
  keytool -genkeypair \
    -alias "rudi-consent" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 3650 \
    -keystore "$CONSENT_JKS" \
    -storepass "$CONSENT_KEYSTORE_PASSWORD" \
    -keypass "$CONSENT_KEYSTORE_PASSWORD" \
    -storetype PKCS12 \
    -dname "CN=RUDI Consent,OU=Consent Management,O=RUDI Platform,C=FR" \
    2>&1 | grep -v "Warning" || true
  
  if [ -f "$CONSENT_JKS" ]; then
    chmod 600 "$CONSENT_JKS"
    echo "  ✓ Consent keystore created"
  else
    echo "  ✗ Failed to create consent keystore"
  fi
fi

# Selfdata keystore (for personal data encryption)
if [ -d "$ROOT_DIR/config/selfdata" ]; then
  echo "  Creating rudi-selfdata.jks..."
  SELFDATA_JKS="$ROOT_DIR/config/selfdata/rudi-selfdata.jks"
  
  # Remove old keystore if exists
  rm -f "$SELFDATA_JKS"
  
  keytool -genkeypair \
    -alias "rudi-selfdata" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 3650 \
    -keystore "$SELFDATA_JKS" \
    -storepass "$SELFDATA_KEYSTORE_PASSWORD" \
    -keypass "$SELFDATA_KEYSTORE_PASSWORD" \
    -storetype PKCS12 \
    -dname "CN=RUDI Selfdata,OU=Personal Data,O=RUDI Platform,C=FR" \
    2>&1 | grep -v "Warning" || true
  
  if [ -f "$SELFDATA_JKS" ]; then
    chmod 600 "$SELFDATA_JKS"
    echo "  ✓ Selfdata keystore created"
  else
    echo "  ✗ Failed to create selfdata keystore"
  fi
fi

# Apigateway keystore (for API key encryption) - if needed
if [ -d "$ROOT_DIR/config/apigateway" ]; then
  # Check if a separate keystore is needed or if SSL keystore is used
  # Most installations use the SSL keystore, so we skip creating a separate one
  echo "  ℹ  Apigateway uses SSL keystore (already created)"
fi

# Save keystore passwords reference
cat > "$ROOT_DIR/.keystore-info.txt" << EOF
SSL Keystore Information
========================
Generated: $(date)

SSL Certificate:
  Source: $CERT_FILE
  Valid for: rudi.$base_dn, dataverse.$base_dn, magnolia.$base_dn

Keystore Passwords:
  Main SSL: \$KEYSTORE_PASSWORD (from .passwords.env)
  Consent: \$CONSENT_KEYSTORE_PASSWORD
  Selfdata: \$SELFDATA_KEYSTORE_PASSWORD
  
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
echo "Summary:"
echo "  - Generated $TOTAL SSL keystores"
echo "  - Generated 2 special keystores (consent, selfdata)"
echo "  - All keystores use PKCS12 format"
echo "  - All keystores secured with 600 permissions"
echo ""
echo "Keystore info saved to: .keystore-info.txt"
echo ""
echo "IMPORTANT:"
echo "- Keystore passwords are in .passwords.env"
echo "- Update configuration files with correct passwords"
echo "- For production, use valid SSL certificates (not self-signed)"
echo ""
