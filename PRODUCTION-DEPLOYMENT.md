# RUDI Platform - Production Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Security Hardening](#security-hardening)
5. [Step-by-Step Deployment](#step-by-step-deployment)
6. [Producer Node Setup](#producer-node-setup)
7. [Post-Deployment Configuration](#post-deployment-configuration)
8. [Monitoring and Maintenance](#monitoring-and-maintenance)
9. [Automation](#automation)

---

## Overview

This guide provides a comprehensive, production-ready deployment process for the RUDI platform, including setup of 2 producer nodes. The default RUDI Out-of-the-Box (ROOB) configuration is designed for quick testing with **insecure dummy data** and must be hardened for production use.

### Key Security Concerns in Default Setup

The default ROOB installation contains:
- **Hardcoded passwords** in configuration files and environment variables
- **Shared RSA keys** across all microservices in `/config/*/key/`
- **Self-signed SSL certificates** (`rudi-https-certificate.jks`)
- **Default Dataverse API token** (`90276ddd-d283-4688-b13d-5aa147efb8b0`)
- **Insecure database credentials** (e.g., `Rud1R00B-db-*`)
- **Disabled SSL verification** (`trust.trust-all-certs=true`)
- **Default test users** with known passwords

---

## Architecture

### Platform Components

The RUDI platform consists of three main stacks:

#### 1. RUDI Portal (docker-compose-rudi.yml)
- **registry**: Service discovery (Eureka)
- **gateway**: API Gateway
- **acl**: Authentication and authorization
- **apigateway**: Data access gateway
- **strukture**: Organization management
- **kalim**: Data harvesting
- **konsult**: Data consultation
- **kos**: SKOS vocabulary management
- **konsent**: Consent management
- **projekt**: Project management
- **selfdata**: Personal data management
- **portail**: Frontend application
- **database**: PostgreSQL (rudi schema)
- **mailhog**: Email testing tool

#### 2. Dataverse Stack (docker-compose-dataverse.yml)
- **dataverse**: Data repository
- **dataverse-database**: PostgreSQL
- **solr**: Search engine

#### 3. Magnolia CMS (docker-compose-magnolia.yml)
- **magnolia**: Content Management System
- **magnolia-database**: PostgreSQL

#### 4. Networking (docker-compose-network.yml)
- **reverse-proxy**: Traefik reverse proxy

### Producer Nodes

Producer nodes are external RUDI installations that publish data to your main portal. The default setup includes credentials for 3 producer nodes:
- **sib**: UUID `d7ffa7cc-8410-4b39-aa6b-c915079f4383`
- **nodestub**: UUID `5596b5b2-b227-4c74-a9a1-719e7c1008c7`
- **irisa**: UUID `d343dd99-fec6-443a-9293-a37fe8cdd1ad`

---

## Prerequisites

### Server Requirements

**Minimum Production Specifications:**
- **OS**: Ubuntu 22.04 LTS / Debian 12+ (recommended)
- **CPU**: 8 cores (16 recommended)
- **RAM**: 32GB (64GB recommended)
- **Storage**: 500GB SSD (1TB+ recommended for data growth)
- **Network**: Static IP address, proper DNS configuration

**For 2 Producer Nodes (each):**
- **CPU**: 4 cores
- **RAM**: 16GB
- **Storage**: 250GB SSD

### Software Requirements

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker Engine (don't use Docker Desktop in production)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose Plugin
sudo apt install docker-compose-plugin

# Install Git and Git LFS
sudo apt install git git-lfs
git lfs install

# Install essential tools
sudo apt install openssl postgresql-client jq curl wget
```

### Domain and DNS Configuration

You need:
1. **Main platform domain**: e.g., `rudi.yourdomain.com`
2. **Subdomains**:
   - `dataverse.yourdomain.com`
   - `magnolia.yourdomain.com`
   - `rudi.yourdomain.com` (portal)
3. **Producer node domains** (2 nodes):
   - `producer1.yourdomain.com`
   - `producer2.yourdomain.com`

### SSL Certificates

Obtain valid SSL certificates for all domains. Use Let's Encrypt or your organization's CA:

```bash
# Example with certbot (Let's Encrypt)
sudo apt install certbot
sudo certbot certonly --standalone -d rudi.yourdomain.com \
  -d dataverse.yourdomain.com \
  -d magnolia.yourdomain.com
```

---

## Security Hardening

### 1. Generate Unique RSA Keys

Each microservice needs its own RSA keypair for JWT signing:

```bash
#!/bin/bash
# generate-keys.sh

SERVICES=(acl apigateway gateway kalim konsent kos konsult projekt selfdata strukture registry)

for service in "${SERVICES[@]}"; do
  echo "Generating keys for $service..."
  mkdir -p config/$service/key
  
  # Generate 4096-bit RSA key
  ssh-keygen -t rsa -b 4096 -f config/$service/key/id_rsa -N "" -C "rudi-$service-$(date +%Y%m%d)"
  
  # Set proper permissions
  chmod 600 config/$service/key/id_rsa
  chmod 644 config/$service/key/id_rsa.pub
done

# Generate root key
mkdir -p config/key
ssh-keygen -t rsa -b 4096 -f config/key/id_rsa -N "" -C "rudi-root-$(date +%Y%m%d)"
chmod 600 config/key/id_rsa
chmod 644 config/key/id_rsa.pub

echo "Keys generated successfully!"
```

### 2. Generate SSL Keystores

Replace the default `rudi-https-certificate.jks` files:

```bash
#!/bin/bash
# generate-ssl-keystores.sh

# Variables
DOMAIN="yourdomain.com"
KEYSTORE_PASSWORD=$(openssl rand -base64 32)
CERT_PATH="/etc/letsencrypt/live/rudi.$DOMAIN"

SERVICES=(acl apigateway gateway kalim konsent kos konsult projekt selfdata strukture registry)

for service in "${SERVICES[@]}"; do
  echo "Creating keystore for $service..."
  
  # Convert PEM to PKCS12
  openssl pkcs12 -export \
    -in "$CERT_PATH/fullchain.pem" \
    -inkey "$CERT_PATH/privkey.pem" \
    -out "config/$service/rudi-https-certificate.p12" \
    -name "rudi-https" \
    -password "pass:$KEYSTORE_PASSWORD"
  
  # Convert PKCS12 to JKS
  keytool -importkeystore \
    -srckeystore "config/$service/rudi-https-certificate.p12" \
    -srcstoretype PKCS12 \
    -srcstorepass "$KEYSTORE_PASSWORD" \
    -destkeystore "config/$service/rudi-https-certificate.jks" \
    -deststoretype PKCS12 \
    -deststorepass "$KEYSTORE_PASSWORD" \
    -destkeypass "$KEYSTORE_PASSWORD" \
    -alias "rudi-https"
  
  echo "$KEYSTORE_PASSWORD" > "config/$service/.keystore-password"
  chmod 600 "config/$service/.keystore-password"
done

echo "Keystores generated. Store passwords securely!"
```

### 3. Generate Secure Passwords

Create a password generation script:

```bash
#!/bin/bash
# generate-passwords.sh

# Generate secure random passwords
generate_password() {
  openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Database passwords
echo "=== Database Passwords ==="
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

# Microservice passwords
echo "=== Microservice OAuth2 Client Secrets ==="
MS_ACL=$(generate_password)
MS_APIGATEWAY=$(generate_password)
MS_KALIM=$(generate_password)
MS_KONSENT=$(generate_password)
MS_KOS=$(generate_password)
MS_PROJEKT=$(generate_password)
MS_SELFDATA=$(generate_password)
MS_STRUKTURE=$(generate_password)

# Application passwords
echo "=== Application Passwords ==="
EUREKA_PASSWORD=$(generate_password)
DATAVERSE_API_TOKEN=$(uuidgen)
KEYSTORE_PASSWORD=$(generate_password)

# Save to secure file
cat > .passwords.env << EOF
# Generated on $(date)
# KEEP THIS FILE SECURE - DO NOT COMMIT TO VERSION CONTROL

# Database Passwords
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

# Microservice OAuth2 Secrets
MS_ACL=$MS_ACL
MS_APIGATEWAY=$MS_APIGATEWAY
MS_KALIM=$MS_KALIM
MS_KONSENT=$MS_KONSENT
MS_KOS=$MS_KOS
MS_PROJEKT=$MS_PROJEKT
MS_SELFDATA=$MS_SELFDATA
MS_STRUKTURE=$MS_STRUKTURE

# Application Passwords
EUREKA_PASSWORD=$EUREKA_PASSWORD
DATAVERSE_API_TOKEN=$DATAVERSE_API_TOKEN
KEYSTORE_PASSWORD=$KEYSTORE_PASSWORD
EOF

chmod 600 .passwords.env
echo "Passwords generated and saved to .passwords.env"
echo "IMPORTANT: Store this file in a secure password manager!"
```

### 4. Update Configuration Files

You must update passwords in:
1. **Database initialization**: `config/rudi-init/01-usr.sql`
2. **Docker Compose files**: All `docker-compose-*.yml`
3. **Microservice properties**: All `config/*/*.properties`
4. **Registry configuration**: `config/registry/registry.properties`

---

## Step-by-Step Deployment

### Step 1: Clone and Prepare Repository

```bash
# Clone repository
git clone https://github.com/rudi-platform/rudi-out-of-the-box.git
cd rudi-out-of-the-box

# Pull large files
git lfs pull

# Set permissions
chmod -R 755 config
chmod -R 777 data

# Create necessary directories
mkdir -p data/{rudi,dataverse,magnolia,solr}
mkdir -p database-data/{rudi,dataverse,magnolia}
mkdir -p certs
mkdir -p logs
```

### Step 2: Configure Domain

Edit `.env` file:

```bash
# .env
base_dn=yourdomain.com
rudi_version=v3.2.6
```

### Step 3: Security Hardening

```bash
# Generate all security materials
./generate-keys.sh
./generate-ssl-keystores.sh
./generate-passwords.sh

# Source the passwords
source .passwords.env
```

### Step 4: Update Database Initialization

Edit `config/rudi-init/01-usr.sql` and replace all passwords:

```sql
ALTER USER acl WITH PASSWORD '$DB_ACL';
ALTER USER kalim WITH PASSWORD '$DB_KALIM';
-- ... repeat for all users
```

### Step 5: Update Docker Compose Files

#### docker-compose-rudi.yml

```yaml
services:
  database:
    environment:
      - POSTGRES_PASSWORD=${DB_RUDI}
    volumes:
      - ./database-data/rudi:/var/lib/postgresql/data  # Add persistence
```

#### docker-compose-dataverse.yml

```yaml
services:
  dataverse-database:
    environment:
      - POSTGRES_PASSWORD=${DB_DATAVERSE}
    volumes:
      - ./database-data/dataverse:/var/lib/postgresql/data  # Add persistence
```

#### docker-compose-magnolia.yml

```yaml
services:
  magnolia-database:
    environment:
      - POSTGRES_PASSWORD=${DB_MAGNOLIA}
    volumes:
      - ./database-data/magnolia:/var/lib/postgresql/data  # Add persistence
```

### Step 6: Update Microservice Properties

For each microservice, edit `config/[service]/[service].properties`:

```properties
# Example: config/acl/acl.properties

# Update database password
spring.datasource.password=${DB_ACL}

# Update keystore password (read from generated file)
server.ssl.key-store-password=${KEYSTORE_PASSWORD}

# Update OAuth2 credentials
module.oauth2.client-secret=${MS_ACL}

# Enable SSL verification in production
trust.trust-all-certs=false

# Update Eureka credentials
eureka.client.serviceURL.defaultZone=https://admin:${EUREKA_PASSWORD}@registry:8761/eureka
```

### Step 7: Configure Traefik with SSL

Create `traefik.yml`:

```yaml
api:
  dashboard: true
  insecure: false

log:
  filePath: "/etc/traefik/logs/traefik.log"
  format: json
  level: "INFO"

accessLog:
  filePath: "/etc/traefik/logs/access.log"
  format: json

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    watch: true
    network: traefik
  file:
    filename: "/etc/traefik/traefik.yml"
    watch: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls: true

tls:
  stores:
    default:
      defaultCertificate:
        certFile: /etc/certs/fullchain.pem
        keyFile: /etc/certs/privkey.pem
  certificates:
    - certFile: /etc/certs/fullchain.pem
      keyFile: /etc/certs/privkey.pem
```

Update `docker-compose-network.yml`:

```yaml
services:
  reverse-proxy:
    image: traefik:v2.10
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"  # Dashboard (restrict in production)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./certs:/etc/certs:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./logs/traefik:/etc/traefik/logs
    restart: unless-stopped
    networks:
      - traefik

  # Update labels for all services
  dataverse:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dataverse.rule=Host(`dataverse.${base_dn}`)"
      - "traefik.http.routers.dataverse.entrypoints=websecure"
      - "traefik.http.routers.dataverse.tls=true"
      - "traefik.http.services.dataverse.loadbalancer.server.port=8080"

networks:
  traefik:
    external: true
```

### Step 8: Deploy the Platform

```bash
# Create Docker network
docker network create traefik

# Start services in order
echo "Starting databases..."
docker compose -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               up -d database dataverse-database magnolia-database

# Wait for databases to be healthy
echo "Waiting for databases..."
sleep 60

echo "Starting Dataverse stack..."
docker compose -f docker-compose-dataverse.yml \
               -f docker-compose-network.yml \
               --profile dataverse up -d

echo "Starting Magnolia stack..."
docker compose -f docker-compose-magnolia.yml \
               -f docker-compose-network.yml \
               --profile magnolia up -d

echo "Starting RUDI portal..."
docker compose -f docker-compose-rudi.yml \
               -f docker-compose-network.yml \
               --profile portail up -d

echo "Starting reverse proxy..."
docker compose -f docker-compose-network.yml up -d reverse-proxy

echo "Deployment complete!"
```

### Step 9: Verify Deployment

```bash
# Check all services are running
docker compose -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               -f docker-compose-network.yml \
               --profile "*" ps

# Check logs
docker compose logs -f --tail=100

# Test endpoints
curl -k https://rudi.yourdomain.com
curl -k https://dataverse.yourdomain.com
curl -k https://magnolia.yourdomain.com
```

---

## Producer Node Setup

Producer nodes are separate RUDI installations that can publish data to your main portal. Here's how to set up 2 producer nodes.

### Producer Node Architecture

Each producer node requires:
- Node Manager (manages access and interactions)
- Node Storage (stores data)
- Node Catalog (indexes datasets)
- Authentication with main portal

### Producer Node 1 Setup

On `producer1.yourdomain.com` server:

```bash
# 1. Clone the producer node repositories
mkdir -p /opt/rudi-producer1
cd /opt/rudi-producer1

git clone https://github.com/rudi-platform/rudi-node-manager.git
git clone https://github.com/rudi-platform/rudi-node-storage.git
git clone https://github.com/rudi-platform/rudi-node-catalog.git

# 2. Generate unique UUID for this producer node
PRODUCER1_UUID=$(uuidgen)
echo "Producer 1 UUID: $PRODUCER1_UUID"

# 3. Generate credentials
PRODUCER1_PASSWORD=$(openssl rand -base64 32)
echo "Producer 1 Password: $PRODUCER1_PASSWORD"

# Save credentials
cat > .producer1-credentials.env << EOF
PRODUCER1_UUID=$PRODUCER1_UUID
PRODUCER1_PASSWORD=$PRODUCER1_PASSWORD
PRODUCER1_DOMAIN=producer1.yourdomain.com
MAIN_PORTAL=https://rudi.yourdomain.com
EOF

chmod 600 .producer1-credentials.env
```

### Producer Node 2 Setup

On `producer2.yourdomain.com` server:

```bash
# Repeat same steps with unique credentials
PRODUCER2_UUID=$(uuidgen)
PRODUCER2_PASSWORD=$(openssl rand -base64 32)

cat > .producer2-credentials.env << EOF
PRODUCER2_UUID=$PRODUCER2_UUID
PRODUCER2_PASSWORD=$PRODUCER2_PASSWORD
PRODUCER2_DOMAIN=producer2.yourdomain.com
MAIN_PORTAL=https://rudi.yourdomain.com
EOF
```

### Register Producer Nodes in Main Portal

On the main portal server, add producer node credentials to the database:

```sql
-- Connect to the RUDI database
psql -U rudi -d rudi

-- Insert producer node 1
INSERT INTO acl_data.user_account 
  (uuid, login, password, type, created_date, updated_date)
VALUES 
  ('PRODUCER1_UUID', 'producer1', 'HASHED_PRODUCER1_PASSWORD', 'ROBOT', NOW(), NOW());

-- Insert producer node 2
INSERT INTO acl_data.user_account 
  (uuid, login, password, type, created_date, updated_date)
VALUES 
  ('PRODUCER2_UUID', 'producer2', 'HASHED_PRODUCER2_PASSWORD', 'ROBOT', NOW(), NOW());

-- Grant necessary roles
INSERT INTO acl_data.user_role (user_fk, role_fk)
SELECT u.id, r.id 
FROM acl_data.user_account u, acl_data.role r
WHERE u.login IN ('producer1', 'producer2')
  AND r.code = 'PROVIDER';
```

### Producer Node Docker Compose

Create `docker-compose-producer.yml` for each producer:

```yaml
version: '3.8'

services:
  node-manager:
    image: rudiplatform/rudi-node-manager:latest
    environment:
      - NODE_UUID=${PRODUCER_UUID}
      - NODE_PASSWORD=${PRODUCER_PASSWORD}
      - PORTAL_URL=${MAIN_PORTAL}
      - NODE_DOMAIN=${PRODUCER_DOMAIN}
    ports:
      - "8443:8443"
    volumes:
      - ./config/node-manager:/etc/rudi/config
      - ./data/node-manager:/opt/rudi/data
    restart: unless-stopped

  node-storage:
    image: rudiplatform/rudi-node-storage:latest
    environment:
      - NODE_UUID=${PRODUCER_UUID}
    volumes:
      - ./data/storage:/data
    restart: unless-stopped

  node-catalog:
    image: rudiplatform/rudi-node-catalog:latest
    environment:
      - NODE_UUID=${PRODUCER_UUID}
    depends_on:
      - node-storage
    restart: unless-stopped

  producer-db:
    image: postgres:15
    environment:
      - POSTGRES_DB=rudi_producer
      - POSTGRES_USER=rudi
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - ./database-data:/var/lib/postgresql/data
    restart: unless-stopped
```

### Configure Producer Node Communication

In the main portal's `config/strukture/strukture.properties`, configure known producer nodes:

```properties
# Producer Node Configuration
rudi.producer.nodes[0].uuid=${PRODUCER1_UUID}
rudi.producer.nodes[0].url=https://producer1.yourdomain.com
rudi.producer.nodes[0].enabled=true

rudi.producer.nodes[1].uuid=${PRODUCER2_UUID}
rudi.producer.nodes[1].url=https://producer2.yourdomain.com
rudi.producer.nodes[1].enabled=true
```

---

## Post-Deployment Configuration

### 1. Initialize Dataverse

```bash
# Access Dataverse container
docker exec -it dataverse bash

# Run initialization scripts
cd /opt/payara/init.d
./setup-all.sh

# Set API token
curl -X PUT -d "${DATAVERSE_API_TOKEN}" \
  http://localhost:8080/api/admin/apiTokenTimeout

# Create collections
curl -H "X-Dataverse-key: ${DATAVERSE_API_TOKEN}" \
  -X POST http://localhost:8080/api/dataverses/:root \
  -d @rudi-dataverse-config.json
```

### 2. Configure Magnolia CMS

1. Access Magnolia: `https://magnolia.yourdomain.com`
2. Login with default admin (change immediately)
3. Configure RUDI module settings
4. Set up content workflows
5. Create necessary pages and templates

### 3. Change Default Passwords

```bash
# Portal users - via database
psql -U rudi -d rudi << EOF
UPDATE acl_data.user_account 
SET password = crypt('NEW_PASSWORD', gen_salt('bf', 12))
WHERE login IN ('rudi', 'animateur@rennesmetropole.fr');
EOF

# Dataverse admin
docker exec dataverse curl -X PUT \
  -d "NEW_PASSWORD" \
  http://localhost:8080/api/admin/authenticationProviders/builtin/password/dataverseAdmin

# Magnolia users
# Change via Magnolia admin interface: Security > Users
```

### 4. Configure Email

Update `config/*/properties` files:

```properties
mail.smtp.host=smtp.yourdomain.com
mail.smtp.port=587
mail.smtp.auth=true
mail.smtp.starttls.enable=true
mail.smtp.username=noreply@yourdomain.com
mail.smtp.password=${SMTP_PASSWORD}
mail.from=noreply@yourdomain.com
```

### 5. Set Up Backups

Create backup script `/usr/local/bin/backup-rudi.sh`:

```bash
#!/bin/bash
# backup-rudi.sh

BACKUP_DIR="/backups/rudi"
DATE=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR/$DATE"

# Backup databases
docker exec database pg_dump -U rudi rudi | gzip > "$BACKUP_DIR/$DATE/rudi-db.sql.gz"
docker exec dataverse-database pg_dump -U dataverse dataverse | gzip > "$BACKUP_DIR/$DATE/dataverse-db.sql.gz"
docker exec magnolia-database pg_dump -U magnolia magnolia | gzip > "$BACKUP_DIR/$DATE/magnolia-db.sql.gz"

# Backup data volumes
tar czf "$BACKUP_DIR/$DATE/data-volumes.tar.gz" -C /opt/rudi-out-of-the-box data/

# Backup configurations (excluding secrets)
tar czf "$BACKUP_DIR/$DATE/configs.tar.gz" -C /opt/rudi-out-of-the-box config/ \
  --exclude='*.jks' --exclude='id_rsa' --exclude='*.passwords.env'

# Keep only last 30 days
find "$BACKUP_DIR" -type d -mtime +30 -exec rm -rf {} +

echo "Backup completed: $BACKUP_DIR/$DATE"
```

Add to crontab:

```bash
# Crontab entry - daily at 2 AM
0 2 * * * /usr/local/bin/backup-rudi.sh >> /var/log/rudi-backup.log 2>&1
```

---

## Monitoring and Maintenance

### 1. Health Checks

Create monitoring script `/usr/local/bin/monitor-rudi.sh`:

```bash
#!/bin/bash
# monitor-rudi.sh

SERVICES=(
  "https://rudi.yourdomain.com"
  "https://dataverse.yourdomain.com"
  "https://magnolia.yourdomain.com"
)

for service in "${SERVICES[@]}"; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "$service")
  
  if [ "$HTTP_CODE" -ne 200 ] && [ "$HTTP_CODE" -ne 302 ]; then
    echo "ALERT: $service returned HTTP $HTTP_CODE"
    # Send alert (email, Slack, etc.)
  else
    echo "OK: $service is healthy"
  fi
done

# Check Docker containers
UNHEALTHY=$(docker ps --filter "health=unhealthy" -q)
if [ -n "$UNHEALTHY" ]; then
  echo "ALERT: Unhealthy containers detected"
  docker ps --filter "health=unhealthy"
fi
```

### 2. Log Management

Configure log rotation in `/etc/logrotate.d/rudi`:

```
/var/log/rudi/*.log
/opt/rudi-out-of-the-box/logs/**/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        docker compose -f /opt/rudi-out-of-the-box/docker-compose-rudi.yml restart
    endscript
}
```

### 3. Resource Monitoring

Install monitoring stack (Prometheus + Grafana):

```yaml
# monitoring/docker-compose.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    ports:
      - "3000:3000"
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
```

### 4. Security Audits

Regular security checks:

```bash
# Check for exposed sensitive files
find config/ -name "*.jks" -o -name "id_rsa" -o -name "*.env" | while read file; do
  echo "Checking permissions: $file"
  stat -c "%a %n" "$file"
done

# Check Docker security
docker scan rudiplatform/rudi-microservice-acl:${rudi_version}

# Update dependencies
docker compose pull
```

---

## Automation

### Full Deployment Automation Script

Create `/opt/rudi-deployment/deploy.sh`:

```bash
#!/bin/bash
# deploy.sh - Automated RUDI Platform Deployment

set -e  # Exit on error

# Configuration
RUDI_DIR="/opt/rudi-out-of-the-box"
DOMAIN="yourdomain.com"
RUDI_VERSION="v3.2.6"

echo "====================================="
echo "RUDI Platform Automated Deployment"
echo "====================================="

# Step 1: Clone repository
if [ ! -d "$RUDI_DIR" ]; then
  echo "[1/10] Cloning repository..."
  git clone https://github.com/rudi-platform/rudi-out-of-the-box.git "$RUDI_DIR"
  cd "$RUDI_DIR"
  git lfs pull
else
  echo "[1/10] Repository already exists, updating..."
  cd "$RUDI_DIR"
  git pull
  git lfs pull
fi

# Step 2: Set permissions
echo "[2/10] Setting permissions..."
chmod -R 755 config
chmod -R 777 data
mkdir -p database-data/{rudi,dataverse,magnolia}
mkdir -p certs logs

# Step 3: Configure domain
echo "[3/10] Configuring domain..."
cat > .env << EOF
base_dn=$DOMAIN
rudi_version=$RUDI_VERSION
EOF

# Step 4: Generate security materials
echo "[4/10] Generating RSA keys..."
bash scripts/generate-keys.sh

echo "[5/10] Generating SSL keystores..."
bash scripts/generate-ssl-keystores.sh

echo "[6/10] Generating passwords..."
bash scripts/generate-passwords.sh
source .passwords.env

# Step 7: Update configurations
echo "[7/10] Updating configuration files..."
bash scripts/update-configs.sh

# Step 8: Copy SSL certificates
echo "[8/10] Copying SSL certificates..."
cp /etc/letsencrypt/live/rudi.$DOMAIN/{fullchain.pem,privkey.pem} certs/

# Step 9: Deploy services
echo "[9/10] Deploying services..."

# Create network
docker network create traefik 2>/dev/null || true

# Start databases
docker compose -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               up -d database dataverse-database magnolia-database

echo "Waiting for databases to initialize (60s)..."
sleep 60

# Start all services
docker compose -f docker-compose-magnolia.yml \
               -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-network.yml \
               --profile "*" up -d

# Step 10: Verify deployment
echo "[10/10] Verifying deployment..."
sleep 30

SERVICES_TO_CHECK=(
  "https://rudi.$DOMAIN"
  "https://dataverse.$DOMAIN"
  "https://magnolia.$DOMAIN"
)

ALL_HEALTHY=true
for service in "${SERVICES_TO_CHECK[@]}"; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "$service" || echo "000")
  
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "✓ $service is accessible (HTTP $HTTP_CODE)"
  else
    echo "✗ $service is NOT accessible (HTTP $HTTP_CODE)"
    ALL_HEALTHY=false
  fi
done

if $ALL_HEALTHY; then
  echo ""
  echo "====================================="
  echo "Deployment completed successfully!"
  echo "====================================="
  echo ""
  echo "Next steps:"
  echo "1. Access Magnolia: https://magnolia.$DOMAIN"
  echo "2. Access Dataverse: https://dataverse.$DOMAIN"
  echo "3. Access RUDI Portal: https://rudi.$DOMAIN"
  echo "4. Change all default passwords"
  echo "5. Configure producer nodes"
  echo "6. Set up backups and monitoring"
  echo ""
  echo "Credentials are stored in: $RUDI_DIR/.passwords.env"
  echo "KEEP THIS FILE SECURE!"
else
  echo ""
  echo "====================================="
  echo "Deployment completed with warnings"
  echo "====================================="
  echo "Some services may not be accessible yet."
  echo "Check logs: docker compose logs -f"
fi
```

### Producer Node Deployment Script

Create `/opt/rudi-producer-deployment/deploy-producer.sh`:

```bash
#!/bin/bash
# deploy-producer.sh - Deploy RUDI Producer Node

set -e

PRODUCER_ID=$1
PRODUCER_DOMAIN=$2
MAIN_PORTAL=$3

if [ -z "$PRODUCER_ID" ] || [ -z "$PRODUCER_DOMAIN" ] || [ -z "$MAIN_PORTAL" ]; then
  echo "Usage: $0 <producer_id> <producer_domain> <main_portal_url>"
  echo "Example: $0 1 producer1.domain.com https://rudi.domain.com"
  exit 1
fi

PRODUCER_DIR="/opt/rudi-producer$PRODUCER_ID"
PRODUCER_UUID=$(uuidgen)
PRODUCER_PASSWORD=$(openssl rand -base64 32)

echo "Deploying Producer Node $PRODUCER_ID"
echo "UUID: $PRODUCER_UUID"
echo "Domain: $PRODUCER_DOMAIN"

# Create directory structure
mkdir -p "$PRODUCER_DIR"/{config,data,database-data}
cd "$PRODUCER_DIR"

# Save credentials
cat > .producer-credentials.env << EOF
PRODUCER_ID=$PRODUCER_ID
PRODUCER_UUID=$PRODUCER_UUID
PRODUCER_PASSWORD=$PRODUCER_PASSWORD
PRODUCER_DOMAIN=$PRODUCER_DOMAIN
MAIN_PORTAL=$MAIN_PORTAL
DB_PASSWORD=$(openssl rand -base64 32)
EOF

chmod 600 .producer-credentials.env
source .producer-credentials.env

# Create Docker Compose file
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  node-manager:
    image: rudiplatform/rudi-node-manager:latest
    environment:
      - NODE_UUID=${PRODUCER_UUID}
      - NODE_PASSWORD=${PRODUCER_PASSWORD}
      - PORTAL_URL=${MAIN_PORTAL}
      - NODE_DOMAIN=${PRODUCER_DOMAIN}
    ports:
      - "8443:8443"
    volumes:
      - ./config/node-manager:/etc/rudi/config
      - ./data/node-manager:/opt/rudi/data
    restart: unless-stopped

  producer-db:
    image: postgres:15
    environment:
      - POSTGRES_DB=rudi_producer
      - POSTGRES_USER=rudi
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - ./database-data:/var/lib/postgresql/data
    restart: unless-stopped
EOF

# Deploy
docker compose --env-file .producer-credentials.env up -d

echo ""
echo "Producer Node $PRODUCER_ID deployed successfully!"
echo ""
echo "Next steps:"
echo "1. Register this node in main portal with UUID: $PRODUCER_UUID"
echo "2. Configure node settings"
echo "3. Test connectivity to main portal"
echo ""
echo "Credentials saved in: $PRODUCER_DIR/.producer-credentials.env"
```

### Update Script

Create `/opt/rudi-deployment/update.sh`:

```bash
#!/bin/bash
# update.sh - Update RUDI Platform

RUDI_DIR="/opt/rudi-out-of-the-box"
cd "$RUDI_DIR"

echo "Updating RUDI Platform..."

# Pull new images
docker compose -f docker-compose-magnolia.yml \
               -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               --profile "*" pull

# Backup before update
echo "Creating backup..."
/usr/local/bin/backup-rudi.sh

# Restart services with new images
echo "Restarting services..."
docker compose -f docker-compose-magnolia.yml \
               -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-network.yml \
               --profile "*" up -d

echo "Update completed!"
```

---

## Troubleshooting

### Common Issues

**Issue 1: Services can't connect to registry**
```bash
# Check registry logs
docker compose logs registry

# Verify Eureka credentials in each microservice properties file
# Should match: eureka.client.serviceURL.defaultZone
```

**Issue 2: SSL certificate errors**
```bash
# Verify certificate validity
openssl x509 -in certs/fullchain.pem -text -noout

# Check keystore password matches in all properties files
```

**Issue 3: Database connection errors**
```bash
# Check database status
docker compose ps database

# Test connection
docker exec database pg_isready -U rudi

# Verify passwords match in:
# - docker-compose-rudi.yml
# - config/*/[service].properties
```

**Issue 4: Producer nodes can't connect**
```bash
# Verify producer node credentials in main portal database
psql -U rudi -d rudi -c "SELECT uuid, login, type FROM acl_data.user_account WHERE type='ROBOT';"

# Check firewall rules
sudo ufw status

# Test connectivity
curl -k https://producer1.yourdomain.com
```

---

## Security Checklist

- [ ] All default passwords changed
- [ ] Unique RSA keys generated for each microservice
- [ ] Valid SSL certificates installed
- [ ] SSL verification enabled (`trust.trust-all-certs=false`)
- [ ] Database passwords rotated
- [ ] Firewall configured (only ports 80, 443 exposed)
- [ ] Secrets stored securely (not in git)
- [ ] Traefik dashboard access restricted
- [ ] Database ports not publicly exposed
- [ ] Regular security updates scheduled
- [ ] Backup and restore tested
- [ ] Monitoring and alerting configured
- [ ] Log retention policy implemented

---

## Maintenance Schedule

### Daily
- Monitor service health
- Check log files for errors
- Verify backup completion

### Weekly
- Review resource usage (CPU, RAM, disk)
- Check for security updates
- Test critical endpoints

### Monthly
- Update Docker images
- Rotate logs
- Review and update SSL certificates
- Database maintenance (VACUUM, ANALYZE)
- Test disaster recovery procedures

### Quarterly
- Security audit
- Performance optimization
- Review and update documentation
- Capacity planning

---

## Support and Resources

- **Official Documentation**: https://doc.rudi.fr/
- **GitHub Organization**: https://github.com/rudi-platform
- **Community Forum**: https://github.com/orgs/rudi-platform/discussions
- **Issue Tracker**: https://github.com/rudi-platform/rudi-out-of-the-box/issues

---

**Document Version**: 1.0  
**Last Updated**: December 2025  
**Author**: RUDI Platform Team
