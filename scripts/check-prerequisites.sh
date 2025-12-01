#!/bin/bash
# check-prerequisites.sh - Check and optionally install RUDI prerequisites
#
# This script checks if all required tools are installed for RUDI deployment

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "   RUDI Prerequisites Checker"
echo "========================================="
echo ""

ALL_OK=true

# Function to check if command exists
check_cmd() {
  local cmd=$1
  local name=$2
  local install_hint=$3
  
  if command -v "$cmd" &> /dev/null; then
    echo -e "${GREEN}✅ $name${NC}"
    if [ "$cmd" = "docker" ]; then
      echo "   Version: $(docker --version)"
      echo "   Compose: $(docker compose version)"
    else
      local version=$($cmd --version 2>&1 | head -1 || $cmd version 2>&1 | head -1)
      echo "   Version: $version"
    fi
    return 0
  else
    echo -e "${RED}❌ $name NOT FOUND${NC}"
    if [ -n "$install_hint" ]; then
      echo -e "   ${YELLOW}Install:${NC} $install_hint"
    fi
    ALL_OK=false
    return 1
  fi
}

# Check required tools
echo "Required Prerequisites:"
echo "----------------------"
check_cmd "docker" "Docker" "curl -fsSL https://get.docker.com | sh"
check_cmd "git" "Git" "sudo apt install git"
check_cmd "openssl" "OpenSSL" "sudo apt install openssl"
check_cmd "keytool" "Keytool (Java JDK)" "sudo apt install openjdk-17-jdk"

# Check Java (keytool is part of JDK)
if command -v java &> /dev/null; then
  echo -e "${GREEN}✅ Java${NC}"
  echo "   Version: $(java -version 2>&1 | head -1)"
fi

echo ""
echo "Optional Prerequisites:"
echo "----------------------"

# Git LFS (only for dummy data)
if command -v git-lfs &> /dev/null; then
  echo -e "${GREEN}✅ Git LFS (for dummy data)${NC}"
  echo "   Version: $(git lfs version)"
else
  echo -e "${YELLOW}⚠️  Git LFS NOT FOUND${NC}"
  echo "   Only needed for testing with dummy data"
  echo "   Install: sudo apt install git-lfs"
fi

# PostgreSQL client (optional for management)
if command -v psql &> /dev/null; then
  echo -e "${GREEN}✅ PostgreSQL Client${NC}"
  echo "   Version: $(psql --version)"
else
  echo -e "${YELLOW}⚠️  PostgreSQL Client NOT FOUND${NC}"
  echo "   Optional, for database management"
  echo "   Install: sudo apt install postgresql-client"
fi

echo ""
echo "========================================="

if $ALL_OK; then
  echo -e "${GREEN}✅ All required prerequisites are installed!${NC}"
  echo ""
  echo "You're ready to deploy RUDI:"
  echo ""
  echo "  For production (clean): ./scripts/deploy-clean.sh"
  echo "  For testing: ./scripts/deploy.sh"
  echo ""
  exit 0
else
  echo -e "${RED}❌ Some required prerequisites are missing${NC}"
  echo ""
  echo "Quick install all prerequisites (Debian/Ubuntu):"
  echo ""
  echo "  # Install Docker"
  echo "  curl -fsSL https://get.docker.com -o get-docker.sh"
  echo "  sudo sh get-docker.sh"
  echo "  sudo usermod -aG docker \$USER"
  echo "  newgrp docker"
  echo ""
  echo "  # Install other tools"
  echo "  sudo apt update"
  echo "  sudo apt install -y docker-compose-plugin openjdk-17-jdk git openssl"
  echo ""
  echo "See DEBIAN-INSTALL-GUIDE.md for detailed instructions."
  echo ""
  exit 1
fi
