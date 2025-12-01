# RUDI Deployment Automation Scripts

This directory contains automation scripts for deploying and managing the RUDI platform.

## Quick Start

For a complete automated deployment:

```bash
# 1. Run the main deployment script
./deploy.sh

# 2. Follow the prompts for configuration
# 3. Wait for deployment to complete
# 4. Access your RUDI platform
```

## Available Scripts

### 1. `deploy.sh` - Main Deployment Script

**Purpose**: Fully automated deployment of the RUDI platform

**Usage**:
```bash
./deploy.sh
```

**What it does**:
1. Checks prerequisites (Docker, Docker Compose, OpenSSL, keytool)
2. Creates/verifies .env configuration
3. Sets proper permissions
4. Generates RSA keys
5. Generates secure passwords
6. Handles SSL certificates
7. Generates SSL keystores
8. Updates all configuration files
9. Creates Docker network
10. Pulls Docker images
11. Deploys all services
12. Verifies deployment

**Interactive prompts**:
- Domain configuration
- RUDI version selection
- SSL certificate generation (self-signed for testing)
- Confirmation for regenerating keys/passwords

---

### 2. `generate-keys.sh` - Generate RSA Keys

**Purpose**: Generate unique RSA keypairs for all microservices

**Usage**:
```bash
./generate-keys.sh
```

**What it generates**:
- 4096-bit RSA keys for each microservice (acl, apigateway, gateway, kalim, konsent, kos, konsult, projekt, selfdata, strukture, registry)
- Root RSA key for shared components
- Proper permissions (600 for private, 644 for public)

**Output**: Keys saved in `config/[service]/key/id_rsa`

**Warning**: Running this multiple times will overwrite existing keys. Make backups first!

---

### 3. `generate-passwords.sh` - Generate Secure Passwords

**Purpose**: Generate cryptographically secure passwords for all components

**Usage**:
```bash
./generate-passwords.sh
```

**What it generates**:
- Database passwords (11 databases)
- Microservice OAuth2 client secrets (8 services)
- Application credentials (Eureka, Dataverse, keystores)
- Salt values for hashing

**Output**: `.passwords.env` (600 permissions)

**Important**: 
- File contains ALL sensitive credentials
- Store in a secure password manager
- Never commit to version control
- Create encrypted backups: `gpg -c .passwords.env`

---

### 4. `generate-ssl-keystores.sh` - Generate SSL Keystores

**Purpose**: Convert SSL certificates to Java KeyStore format for Spring Boot microservices

**Usage**:
```bash
./generate-ssl-keystores.sh
```

**Prerequisites**:
- `.passwords.env` must exist
- `.env` must exist with domain configuration
- SSL certificates in `certs/fullchain.pem` and `certs/privkey.pem`

**What it generates**:
- SSL keystores for all microservices
- Special keystores:
  - `rudi-consent.jks` - For PDF signing
  - `rudi-selfdata.jks` - For personal data encryption

**Interactive**: Offers to generate self-signed certificates if none exist

---

### 5. `update-configs.sh` - Update Configuration Files

**Purpose**: Apply generated passwords to all configuration files

**Usage**:
```bash
./update-configs.sh
```

**Prerequisites**:
- `.passwords.env` must exist
- `.env` must exist

**What it updates**:
1. Database initialization scripts (`config/rudi-init/01-usr.sql`)
2. Docker Compose files (all three)
3. Microservice property files (all services)
4. Special configurations (Konsent, Selfdata, Apigateway)
5. Security settings (disables `trust-all-certs`)

**Safety**:
- Creates backup before modifying: `config-backup-YYYYMMDD-HHMMSS/`
- Prompts for confirmation
- Provides rollback instructions

---

### 6. `deploy-producer.sh` - Deploy Producer Node

**Purpose**: Deploy a RUDI producer node on a separate server

**Usage**:
```bash
./deploy-producer.sh <producer_id> <producer_domain> <main_portal_url>
```

**Example**:
```bash
./deploy-producer.sh 1 producer1.example.com https://rudi.example.com
./deploy-producer.sh 2 producer2.example.com https://rudi.example.com
```

**What it does**:
1. Creates installation directory (`/opt/rudi-producer<id>`)
2. Generates unique UUID and credentials
3. Creates Docker Compose configuration
4. Deploys producer node services
5. Generates registration SQL for main portal

**Output**:
- Producer node running at specified domain
- Credentials in `.producer-credentials.env`
- Registration SQL in `register-on-portal.sql`

---

## Workflow Examples

### Initial Production Deployment

```bash
# 1. Clone repository
git clone https://github.com/rudi-platform/rudi-out-of-the-box.git
cd rudi-out-of-the-box

# 2. Place your SSL certificates
mkdir -p certs
cp /path/to/fullchain.pem certs/
cp /path/to/privkey.pem certs/

# 3. Run automated deployment
./scripts/deploy.sh

# 4. Follow prompts and wait for completion

# 5. Access platform at https://rudi.yourdomain.com
```

### Manual Step-by-Step Deployment

```bash
# 1. Generate RSA keys
./scripts/generate-keys.sh

# 2. Generate passwords
./scripts/generate-passwords.sh

# 3. Source passwords
source .passwords.env

# 4. Generate keystores
./scripts/generate-ssl-keystores.sh

# 5. Update configurations
./scripts/update-configs.sh

# 6. Deploy manually
docker compose -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml \
               -f docker-compose-magnolia.yml \
               -f docker-compose-network.yml \
               --profile "*" up -d
```

### Deploy Producer Nodes

```bash
# On producer server 1
./scripts/deploy-producer.sh 1 producer1.example.com https://rudi.example.com

# On producer server 2
./scripts/deploy-producer.sh 2 producer2.example.com https://rudi.example.com

# On main portal server - register producers
psql -U rudi -d rudi -f /opt/rudi-producer1/register-on-portal.sql
psql -U rudi -d rudi -f /opt/rudi-producer2/register-on-portal.sql
```

### Update Existing Deployment

```bash
# 1. Backup current installation
cp -r config config-backup-manual

# 2. Regenerate passwords (if needed for security)
./scripts/generate-passwords.sh

# 3. Update configurations
./scripts/update-configs.sh

# 4. Restart services
docker compose -f docker-compose-*.yml --profile "*" restart
```

### Regenerate Security Materials

```bash
# If keys or certificates are compromised

# 1. Backup everything
tar czf backup-$(date +%Y%m%d).tar.gz config/ .passwords.env

# 2. Generate new keys
./scripts/generate-keys.sh

# 3. Generate new passwords
./scripts/generate-passwords.sh

# 4. Generate new keystores
./scripts/generate-ssl-keystores.sh

# 5. Update all configs
./scripts/update-configs.sh

# 6. Redeploy
docker compose -f docker-compose-*.yml --profile "*" down
docker compose -f docker-compose-*.yml --profile "*" up -d
```

---

## Environment Variables

### Required in `.env`
```bash
base_dn=yourdomain.com        # Your domain name
rudi_version=v3.2.6           # RUDI version to deploy
```

### Generated in `.passwords.env`
```bash
# Database passwords (11 entries)
DB_RUDI=...
DB_DATAVERSE=...
# ... etc

# Microservice secrets (8 entries)
MS_ACL=...
MS_APIGATEWAY=...
# ... etc

# Application credentials
EUREKA_PASSWORD=...
DATAVERSE_API_TOKEN=...
KEYSTORE_PASSWORD=...
# ... etc
```

### Optional Environment Variables
```bash
CERT_DIR=/path/to/certs       # Custom certificate directory
CERT_FILE=/path/to/cert.pem   # Custom certificate file
KEY_FILE=/path/to/key.pem     # Custom private key file
```

---

## Troubleshooting

### Script fails with "permission denied"
```bash
chmod +x scripts/*.sh
```

### "Docker is not installed"
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### "keytool command not found"
```bash
# Ubuntu/Debian
sudo apt install default-jdk

# RHEL/CentOS
sudo yum install java-11-openjdk-devel
```

### ".passwords.env not found"
Run `./generate-passwords.sh` first

### "SSL certificates not found"
Either:
1. Place your certificates in `certs/` directory
2. Let script generate self-signed (testing only)
3. Set `CERT_FILE` and `KEY_FILE` environment variables

### Services fail to start
```bash
# Check logs
docker compose -f docker-compose-*.yml --profile "*" logs -f

# Check specific service
docker logs <container_name>

# Verify configuration
./scripts/update-configs.sh  # Re-run config update
```

### Database connection errors
Verify passwords match in:
- `.passwords.env`
- `docker-compose-rudi.yml`
- `config/[service]/[service].properties`

### Producer node can't connect to main portal
1. Verify producer UUID in main portal database
2. Check firewall rules between servers
3. Verify SSL certificates
4. Check logs: `docker compose logs -f node-manager`

---

## Security Best Practices

1. **Never commit secrets**
   ```bash
   # Add to .gitignore
   echo ".passwords.env" >> .gitignore
   echo ".env.local" >> .gitignore
   echo "config-backup-*" >> .gitignore
   ```

2. **Encrypt sensitive files**
   ```bash
   # Encrypt passwords file
   gpg -c .passwords.env
   
   # Decrypt when needed
   gpg .passwords.env.gpg
   ```

3. **Regular key rotation**
   - Regenerate keys every 6-12 months
   - Update passwords quarterly
   - Rotate SSL certificates before expiry

4. **Secure file permissions**
   ```bash
   chmod 600 .passwords.env
   chmod 600 config/*/key/id_rsa
   chmod 600 config/*/*.jks
   ```

5. **Backup security materials**
   ```bash
   # Create encrypted backup
   tar czf - config/ .passwords.env | gpg -c > rudi-secrets-$(date +%Y%m%d).tar.gz.gpg
   ```

---

## Files Created by Scripts

```
rudi-out-of-the-box/
├── .env                           # Domain configuration
├── .passwords.env                 # All passwords (SENSITIVE!)
├── .env.local                     # Environment overrides
├── .keystore-info.txt            # Keystore reference
├── config/
│   ├── key/
│   │   ├── id_rsa                # Root private key (SENSITIVE!)
│   │   └── id_rsa.pub            # Root public key
│   ├── [service]/
│   │   ├── key/
│   │   │   ├── id_rsa            # Service private key (SENSITIVE!)
│   │   │   └── id_rsa.pub        # Service public key
│   │   ├── rudi-https-certificate.jks  # SSL keystore (SENSITIVE!)
│   │   └── [service].properties  # Updated configuration
│   └── ...
├── config-backup-YYYYMMDD-HHMMSS/  # Automatic backup
└── certs/
    ├── fullchain.pem             # SSL certificate
    └── privkey.pem               # SSL private key (SENSITIVE!)
```

---

## Support

- **Main Documentation**: [PRODUCTION-DEPLOYMENT.md](../PRODUCTION-DEPLOYMENT.md)
- **RUDI Documentation**: https://doc.rudi.fr/
- **GitHub Issues**: https://github.com/rudi-platform/rudi-out-of-the-box/issues
- **Community Discussions**: https://github.com/orgs/rudi-platform/discussions

---

**Last Updated**: December 2025  
**Version**: 1.0
