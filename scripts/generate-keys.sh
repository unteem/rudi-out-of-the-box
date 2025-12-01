#!/bin/bash
# generate-keys.sh - Generate unique RSA keypairs for all RUDI microservices
# 
# This script generates 4096-bit RSA keys for JWT signing
# Each microservice gets its own unique keypair for security

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Generating RSA Keys for RUDI Microservices"
echo "========================================="
echo ""

# List of all microservices that need RSA keys
SERVICES=(acl apigateway gateway kalim konsent kos konsult projekt selfdata strukture registry)

# Counter for progress
TOTAL=${#SERVICES[@]}
CURRENT=0

for service in "${SERVICES[@]}"; do
  CURRENT=$((CURRENT + 1))
  echo "[$CURRENT/$TOTAL] Generating keys for $service..."
  
  # Create key directory if it doesn't exist
  mkdir -p "$ROOT_DIR/config/$service/key"
  
  # Generate 4096-bit RSA key without passphrase
  ssh-keygen -t rsa -b 4096 \
    -f "$ROOT_DIR/config/$service/key/id_rsa" \
    -N "" \
    -C "rudi-$service-$(date +%Y%m%d)" \
    -q
  
  # Set proper permissions (private key should be read-only)
  chmod 600 "$ROOT_DIR/config/$service/key/id_rsa"
  chmod 644 "$ROOT_DIR/config/$service/key/id_rsa.pub"
  
  echo "  ✓ Keys generated: config/$service/key/id_rsa"
done

# Generate root key (used by some shared components)
echo "[$((TOTAL + 1))/$((TOTAL + 1))] Generating root key..."
mkdir -p "$ROOT_DIR/config/key"
ssh-keygen -t rsa -b 4096 \
  -f "$ROOT_DIR/config/key/id_rsa" \
  -N "" \
  -C "rudi-root-$(date +%Y%m%d)" \
  -q

chmod 600 "$ROOT_DIR/config/key/id_rsa"
chmod 644 "$ROOT_DIR/config/key/id_rsa.pub"

echo "  ✓ Root key generated: config/key/id_rsa"
echo ""
echo "========================================="
echo "✓ All keys generated successfully!"
echo "========================================="
echo ""
echo "IMPORTANT:"
echo "- Private keys (id_rsa) are set to 600 (read/write owner only)"
echo "- Public keys (id_rsa.pub) are set to 644 (readable by all)"
echo "- DO NOT commit these keys to version control"
echo "- Keep secure backups of all private keys"
echo ""
