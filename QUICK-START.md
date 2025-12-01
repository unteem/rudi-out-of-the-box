# RUDI Platform - Quick Start Guide

Get your RUDI platform up and running in minutes!

## For Testing/Development

### Prerequisites

Install required tools:
```bash
# Docker and Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt install docker-compose-plugin

# Other tools
sudo apt install git git-lfs default-jdk
```

### One-Command Deployment

```bash
# Clone the repository
git clone https://github.com/rudi-platform/rudi-out-of-the-box.git
cd rudi-out-of-the-box
git lfs pull

# Run the automated deployment script
./scripts/deploy.sh
```

That's it! The script will:
- Generate all security materials
- Configure the platform
- Deploy all services
- Verify the installation

Access your platform:
- **Portal**: http://rudi.localhost/
- **Dataverse**: http://dataverse.localhost
- **Magnolia CMS**: http://magnolia.localhost

Default credentials are in: `documentation/identifiants.md`

---

## For Production

### 1. Prerequisites

**Server**: Ubuntu 22.04 LTS with:
- 8+ CPU cores
- 32GB+ RAM
- 500GB+ SSD storage
- Static IP and DNS configured

**Required**:
- Valid SSL certificates for your domain
- Proper domain/subdomain configuration

### 2. Prepare SSL Certificates

```bash
# Place your SSL certificates
mkdir -p certs
cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem certs/
cp /etc/letsencrypt/live/yourdomain.com/privkey.pem certs/
```

### 3. Configure Domain

Edit `.env`:
```bash
base_dn=yourdomain.com
rudi_version=v3.2.6
```

### 4. Deploy

```bash
./scripts/deploy.sh
```

Follow the prompts and wait for completion (10-15 minutes).

### 5. Post-Deployment

**CRITICAL - Change all default passwords immediately!**

See: [PRODUCTION-DEPLOYMENT.md](PRODUCTION-DEPLOYMENT.md#post-deployment-configuration)

---

## Deploy Producer Nodes

To set up 2 producer nodes:

### On Producer Server 1:
```bash
./scripts/deploy-producer.sh 1 producer1.yourdomain.com https://rudi.yourdomain.com
```

### On Producer Server 2:
```bash
./scripts/deploy-producer.sh 2 producer2.yourdomain.com https://rudi.yourdomain.com
```

### Register on Main Portal:
```bash
# On main portal server
psql -U rudi -d rudi -f /path/to/register-on-portal.sql
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Traefik Reverse Proxy                     │
│                   (SSL Termination, Routing)                 │
└─────────────────┬──────────────────┬────────────────────────┘
                  │                  │
    ┌─────────────┴────────┐    ┌───┴──────────────┐
    │   RUDI Portal        │    │   Dataverse      │
    │   - Frontend         │    │   - Data Repo    │
    │   - 10 Microservices │    │   - Solr         │
    │   - PostgreSQL       │    │   - PostgreSQL   │
    └──────────────────────┘    └──────────────────┘
              │
    ┌─────────┴──────────┐
    │   Magnolia CMS     │
    │   - Content        │
    │   - PostgreSQL     │
    └────────────────────┘

External Producer Nodes:
┌──────────────────┐       ┌──────────────────┐
│  Producer Node 1 │       │  Producer Node 2 │
│  - Node Manager  │       │  - Node Manager  │
│  - Node Storage  │       │  - Node Storage  │
│  - Node Catalog  │       │  - Node Catalog  │
└──────────────────┘       └──────────────────┘
```

---

## Key Components

### Main Platform (docker-compose-rudi.yml)
- **Gateway**: API Gateway for routing
- **ACL**: Authentication & authorization
- **Strukture**: Organization management
- **Kalim**: Data harvesting
- **Konsult**: Data consultation
- **Konsent**: Consent management
- **Projekt**: Project management
- **Selfdata**: Personal data management
- **KOS**: Vocabulary management
- **APIGateway**: Data access gateway
- **Registry**: Service discovery (Eureka)
- **Portail**: Frontend application

### Data Repository (docker-compose-dataverse.yml)
- **Dataverse**: Data catalog and repository
- **Solr**: Search engine

### CMS (docker-compose-magnolia.yml)
- **Magnolia**: Content management system

---

## Management Commands

### View Status
```bash
docker compose -f docker-compose-*.yml --profile "*" ps
```

### View Logs
```bash
# All services
docker compose -f docker-compose-*.yml --profile "*" logs -f

# Specific service
docker compose -f docker-compose-rudi.yml logs -f acl
```

### Stop Services
```bash
# Stop (keep data)
docker compose -f docker-compose-*.yml --profile "*" stop

# Stop and remove (keep data)
docker compose -f docker-compose-*.yml --profile "*" down

# Stop and remove everything (DELETE DATA)
docker compose -f docker-compose-*.yml --profile "*" down -v
```

### Restart Services
```bash
# Restart all
docker compose -f docker-compose-*.yml --profile "*" restart

# Restart specific service
docker compose -f docker-compose-rudi.yml restart acl
```

### Update Platform
```bash
# Pull new images
docker compose -f docker-compose-*.yml --profile "*" pull

# Recreate containers with new images
docker compose -f docker-compose-*.yml --profile "*" up -d
```

---

## Default Credentials (CHANGE IN PRODUCTION!)

### RUDI Users
- **Admin**: rudi / Rud1R00B-admin
- **Animator**: animateur@rennesmetropole.fr / Rud1R00B-animateur
- **User**: reutilisateur@rennesmetropole.fr / Rud1R00B-reutilisateur

### Services
- **Dataverse**: dataverseAdmin / Rud1R00B-dvadmin
- **Magnolia**: superuser / Rud1R00B-mgl-admin
- **Mailhog**: rudi-mailhog / Rud1R00B-mh

### Databases
- **RUDI**: rudi / Rud1R00B-db-rudi (port 35432)
- **Dataverse**: dataverse / Rud1R00B-db-dataverse (port 35433)
- **Magnolia**: magnolia / Rud1R00B-db-magnolia (port 35434)

Full list: `documentation/identifiants.md`

---

## Troubleshooting

### Services won't start
```bash
# Check logs
docker compose -f docker-compose-*.yml --profile "*" logs -f

# Check disk space
df -h

# Check memory
free -h

# Restart services
docker compose -f docker-compose-*.yml --profile "*" restart
```

### Can't access services
```bash
# Check if services are running
docker compose ps

# Check ports
sudo netstat -tulpn | grep LISTEN

# For localhost: add to /etc/hosts
127.0.0.1 rudi.localhost dataverse.localhost magnolia.localhost
```

### Database connection errors
```bash
# Wait for databases to initialize (takes 1-2 minutes)
docker compose logs database dataverse-database magnolia-database

# Check database health
docker compose ps | grep healthy
```

### "Permission denied" errors
```bash
chmod -R 777 data
chmod -R 755 config
```

### Reset everything
```bash
# Stop and remove all containers and volumes
docker compose -f docker-compose-*.yml --profile "*" down -v

# Clean up
rm -rf database-data/* data/*

# Redeploy
./scripts/deploy.sh
```

---

## Security Checklist for Production

Before going live:

- [ ] Changed all default passwords
- [ ] Generated unique RSA keys
- [ ] Installed valid SSL certificates
- [ ] Configured firewall (only 80, 443 open)
- [ ] Enabled proper logging
- [ ] Set up automated backups
- [ ] Configured monitoring
- [ ] Reviewed and updated configuration files
- [ ] Tested disaster recovery
- [ ] Documented custom configuration

See detailed security guide: [PRODUCTION-DEPLOYMENT.md](PRODUCTION-DEPLOYMENT.md#security-hardening)

---

## Next Steps

### For Development/Testing
1. Explore the platform at http://rudi.localhost
2. Create test data
3. Experiment with different features
4. Review documentation at https://doc.rudi.fr

### For Production
1. Follow complete production guide: [PRODUCTION-DEPLOYMENT.md](PRODUCTION-DEPLOYMENT.md)
2. Set up producer nodes
3. Configure backups and monitoring
4. Customize for your organization
5. Train users

---

## Getting Help

- **Documentation**: [PRODUCTION-DEPLOYMENT.md](PRODUCTION-DEPLOYMENT.md)
- **Scripts Help**: [scripts/README.md](scripts/README.md)
- **Official Docs**: https://doc.rudi.fr/
- **GitHub Issues**: https://github.com/rudi-platform/rudi-out-of-the-box/issues
- **Community**: https://github.com/orgs/rudi-platform/discussions

---

## Resources

- **Main Documentation**: https://doc.rudi.fr/
- **RUDI Website**: https://rudi.fr/
- **Rennes Instance**: https://rudi.rennesmetropole.fr/
- **Blog**: https://blog.rudi.bzh/
- **GitHub Organization**: https://github.com/rudi-platform

---

**Happy deploying!** 🚀

For questions or issues, please open an issue on GitHub.
