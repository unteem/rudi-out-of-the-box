#!/bin/bash
# deploy-producer.sh - Deploy RUDI Producer Node
#
# Usage: ./deploy-producer.sh <producer_id> <producer_domain> <main_portal_url>
# Example: ./deploy-producer.sh 1 producer1.example.com https://rudi.example.com

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
PRODUCER_ID=$1
PRODUCER_DOMAIN=$2
MAIN_PORTAL=$3

if [ -z "$PRODUCER_ID" ] || [ -z "$PRODUCER_DOMAIN" ] || [ -z "$MAIN_PORTAL" ]; then
  echo "Usage: $0 <producer_id> <producer_domain> <main_portal_url>"
  echo ""
  echo "Example:"
  echo "  $0 1 producer1.example.com https://rudi.example.com"
  echo ""
  echo "This will deploy:"
  echo "  - Producer Node ID: 1"
  echo "  - Accessible at: https://producer1.example.com"
  echo "  - Connected to: https://rudi.example.com"
  exit 1
fi

echo "========================================="
echo "   RUDI Producer Node Deployment"
echo "========================================="
echo ""
log_info "Producer ID: $PRODUCER_ID"
log_info "Domain: $PRODUCER_DOMAIN"
log_info "Main Portal: $MAIN_PORTAL"
echo ""

# Setup directory
PRODUCER_DIR="/opt/rudi-producer$PRODUCER_ID"

if [ -d "$PRODUCER_DIR" ]; then
  log_warning "Directory $PRODUCER_DIR already exists"
  read -p "Overwrite existing installation? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_error "Aborted"
    exit 1
  fi
  log_info "Removing existing installation..."
  rm -rf "$PRODUCER_DIR"
fi

log_info "Creating directory structure..."
mkdir -p "$PRODUCER_DIR"/{config,data,database-data,certs,logs}
cd "$PRODUCER_DIR"

# Generate credentials
log_info "Generating credentials..."
PRODUCER_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
PRODUCER_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Save credentials
cat > .producer-credentials.env << EOF
# Producer Node $PRODUCER_ID Credentials
# Generated: $(date)
# KEEP THIS FILE SECURE!

PRODUCER_ID=$PRODUCER_ID
PRODUCER_UUID=$PRODUCER_UUID
PRODUCER_PASSWORD=$PRODUCER_PASSWORD
PRODUCER_DOMAIN=$PRODUCER_DOMAIN
MAIN_PORTAL=$MAIN_PORTAL
DB_PASSWORD=$DB_PASSWORD
EOF

chmod 600 .producer-credentials.env
log_success "Credentials generated"

# Create Docker Compose file
log_info "Creating Docker Compose configuration..."
cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  # Producer Node Manager - Manages access and interactions
  node-manager:
    image: rudiplatform/rudi-node-manager:latest
    container_name: producer${PRODUCER_ID}-manager
    environment:
      - NODE_UUID=${PRODUCER_UUID}
      - NODE_PASSWORD=${PRODUCER_PASSWORD}
      - PORTAL_URL=${MAIN_PORTAL}
      - NODE_DOMAIN=${PRODUCER_DOMAIN}
      - DB_HOST=producer-db
      - DB_PORT=5432
      - DB_NAME=rudi_producer
      - DB_USER=rudi
      - DB_PASSWORD=${DB_PASSWORD}
    ports:
      - "8443:8443"
    volumes:
      - ./config/node-manager:/etc/rudi/config
      - ./data/node-manager:/opt/rudi/data
      - ./logs/node-manager:/var/log/rudi
    depends_on:
      producer-db:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - producer-network

  # Producer Database
  producer-db:
    image: postgres:15
    container_name: producer${PRODUCER_ID}-db
    environment:
      - POSTGRES_DB=rudi_producer
      - POSTGRES_USER=rudi
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - ./database-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U rudi -d rudi_producer"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - producer-network

  # Optional: Reverse proxy for SSL termination
  # Uncomment if you want SSL termination at container level
  # nginx-proxy:
  #   image: nginx:alpine
  #   container_name: producer${PRODUCER_ID}-proxy
  #   ports:
  #     - "443:443"
  #   volumes:
  #     - ./certs:/etc/nginx/certs:ro
  #     - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
  #   depends_on:
  #     - node-manager
  #   restart: unless-stopped
  #   networks:
  #     - producer-network

networks:
  producer-network:
    driver: bridge

volumes:
  database-data:
COMPOSE_EOF

log_success "Docker Compose file created"

# Create basic configuration files
log_info "Creating configuration files..."

mkdir -p config/node-manager

cat > config/node-manager/application.yml << 'CONFIG_EOF'
# Producer Node Manager Configuration
server:
  port: 8443
  ssl:
    enabled: false  # SSL handled by reverse proxy

spring:
  application:
    name: rudi-producer-node
  datasource:
    url: jdbc:postgresql://producer-db:5432/rudi_producer
    username: rudi
    password: ${DB_PASSWORD}
    driver-class-name: org.postgresql.Driver

rudi:
  producer:
    uuid: ${NODE_UUID}
    domain: ${NODE_DOMAIN}
    portal:
      url: ${PORTAL_URL}
      
logging:
  level:
    root: INFO
    org.rudi: DEBUG
  file:
    name: /var/log/rudi/node-manager.log
CONFIG_EOF

log_success "Configuration files created"

# Create README
cat > README.md << 'README_EOF'
# RUDI Producer Node

This is a RUDI Producer Node installation.

## Configuration

- Producer ID: ${PRODUCER_ID}
- UUID: ${PRODUCER_UUID}
- Domain: ${PRODUCER_DOMAIN}
- Main Portal: ${MAIN_PORTAL}

## Management Commands

### Start services
```bash
docker compose up -d
```

### Stop services
```bash
docker compose stop
```

### View logs
```bash
docker compose logs -f
```

### Check status
```bash
docker compose ps
```

### Restart services
```bash
docker compose restart
```

## Registration

To register this producer node with the main portal:

1. Access the main portal admin interface
2. Navigate to Producer Nodes management
3. Add new producer node with:
   - UUID: `${PRODUCER_UUID}`
   - URL: `https://${PRODUCER_DOMAIN}`
   - Password: (see .producer-credentials.env)

Or via SQL on the main portal database:

```sql
INSERT INTO acl_data.user_account 
  (uuid, login, password, type, created_date, updated_date)
VALUES 
  ('${PRODUCER_UUID}', 'producer${PRODUCER_ID}', 
   crypt('PASSWORD_HERE', gen_salt('bf', 12)), 
   'ROBOT', NOW(), NOW());

INSERT INTO acl_data.user_role (user_fk, role_fk)
SELECT u.id, r.id 
FROM acl_data.user_account u, acl_data.role r
WHERE u.login = 'producer${PRODUCER_ID}'
  AND r.code = 'PROVIDER';
```

## Monitoring

Health check: `curl -k https://${PRODUCER_DOMAIN}/actuator/health`

## Backup

Database backup:
```bash
docker exec producer${PRODUCER_ID}-db pg_dump -U rudi rudi_producer > backup.sql
```

## Support

See main RUDI documentation: https://doc.rudi.fr/
README_EOF

# Replace variables in README
sed -i "s/\${PRODUCER_ID}/$PRODUCER_ID/g" README.md
sed -i "s/\${PRODUCER_UUID}/$PRODUCER_UUID/g" README.md
sed -i "s/\${PRODUCER_DOMAIN}/$PRODUCER_DOMAIN/g" README.md
sed -i "s/\${MAIN_PORTAL}/$MAIN_PORTAL/g" README.md

log_success "README created"

# Deploy
log_info "Deploying producer node..."
docker compose --env-file .producer-credentials.env up -d

# Wait for services
log_info "Waiting for services to start (20 seconds)..."
sleep 20

# Check status
echo ""
echo "========================================="
echo "Service Status"
echo "========================================="
docker compose ps

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
log_success "Producer Node $PRODUCER_ID deployed successfully!"
echo ""
echo "Installation directory: $PRODUCER_DIR"
echo "Access URL: https://$PRODUCER_DOMAIN"
echo ""
echo "CREDENTIALS (also in .producer-credentials.env):"
echo "  UUID: $PRODUCER_UUID"
echo "  Password: $PRODUCER_PASSWORD"
echo ""
echo "IMPORTANT NEXT STEPS:"
echo ""
echo "1. Register this node in the main portal:"
echo "   - Portal URL: $MAIN_PORTAL/admin"
echo "   - Use UUID: $PRODUCER_UUID"
echo "   - Use Password from above"
echo ""
echo "2. Configure SSL/TLS:"
echo "   - Place certificates in: $PRODUCER_DIR/certs/"
echo "   - Or use a reverse proxy (nginx, traefik, etc.)"
echo ""
echo "3. Test connectivity:"
echo "   curl -k https://$PRODUCER_DOMAIN/actuator/health"
echo ""
echo "4. View logs:"
echo "   cd $PRODUCER_DIR && docker compose logs -f"
echo ""
echo "5. Set up backups:"
echo "   See README.md in $PRODUCER_DIR"
echo ""

# Create registration SQL file for main portal
cat > register-on-portal.sql << EOF
-- Registration SQL for Main Portal
-- Run this on the main portal's database

-- Insert producer node user
INSERT INTO acl_data.user_account 
  (uuid, login, password, type, created_date, updated_date)
VALUES 
  ('$PRODUCER_UUID', 'producer$PRODUCER_ID', 
   crypt('$PRODUCER_PASSWORD', gen_salt('bf', 12)), 
   'ROBOT', NOW(), NOW());

-- Grant PROVIDER role
INSERT INTO acl_data.user_role (user_fk, role_fk)
SELECT u.id, r.id 
FROM acl_data.user_account u, acl_data.role r
WHERE u.login = 'producer$PRODUCER_ID'
  AND r.code = 'PROVIDER';

-- Verify
SELECT uuid, login, type, created_date 
FROM acl_data.user_account 
WHERE uuid = '$PRODUCER_UUID';
EOF

chmod 600 register-on-portal.sql

echo "Registration SQL saved to: $PRODUCER_DIR/register-on-portal.sql"
echo "Run this on the main portal database to register the node"
echo ""
