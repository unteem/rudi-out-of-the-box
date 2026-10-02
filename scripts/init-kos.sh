#!/bin/bash
# init-kos.sh - Initialise les vocabulaires KOS (thèmes et licences)
#
# Télécharge les schèmes directement depuis le dépôt rudi-portal
# et les importe via l'API KOS.
#
# Usage :
#   ./scripts/init-kos.sh --login admin@example.com --password MonMotDePasse
#
# Options (flags ou variables d'environnement) :
#   --login <login>      Login de l'administrateur  (env: KOS_ADMIN_LOGIN)
#   --password <pass>    Mot de passe               (env: KOS_ADMIN_PASSWORD)
#   --url <url>          URL du portail             (env: KOS_URL, défaut: https://rudi.<base_dn>)
#   --version <version>  Tag rudi-portal            (env: KOS_VERSION, défaut: rudi_version depuis .env)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ─── Parse arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --login)    KOS_ADMIN_LOGIN="$2";    shift 2 ;;
    --password) KOS_ADMIN_PASSWORD="$2"; shift 2 ;;
    --url)      KOS_URL="$2";            shift 2 ;;
    --version)  KOS_VERSION="$2";        shift 2 ;;
    -h|--help)
      echo "Usage: $0 --login <login> --password <password> [--url <url>] [--version <tag>]"
      echo ""
      echo "Variables d'environnement équivalentes :"
      echo "  KOS_ADMIN_LOGIN, KOS_ADMIN_PASSWORD, KOS_URL, KOS_VERSION"
      exit 0
      ;;
    *)
      log_error "Argument inconnu : $1"
      echo "Lancer '$0 --help' pour l'usage."
      exit 1
      ;;
  esac
done

# ─── Charger .env pour base_dn et rudi_version ────────────────────────────────

if [ -f "$ROOT_DIR/.env" ]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi

# ─── Valeurs par défaut ───────────────────────────────────────────────────────

KOS_URL="${KOS_URL:-https://rudi.${base_dn}}"
KOS_VERSION="${KOS_VERSION:-${rudi_version:-main}}"
KOS_API="$KOS_URL/kos/v1"

GITHUB_BASE="https://raw.githubusercontent.com/rudi-platform/rudi-portal/${KOS_VERSION}"
SCHEME_KEYWORD_URL="$GITHUB_BASE/rudi-microservice/rudi-microservice-kos/rudi-microservice-kos-service/src/main/resources/skos/scheme-keyword.json"
SCHEME_LICENCE_URL="$GITHUB_BASE/rudi-microservice/rudi-microservice-kos/rudi-microservice-kos-service/src/main/resources/skos/scheme-licence.json"

# ─── Validation ───────────────────────────────────────────────────────────────

MISSING=()
[ -z "$KOS_ADMIN_LOGIN" ]    && MISSING+=("KOS_ADMIN_LOGIN (--login)")
[ -z "$KOS_ADMIN_PASSWORD" ] && MISSING+=("KOS_ADMIN_PASSWORD (--password)")

if [ ${#MISSING[@]} -gt 0 ]; then
  log_error "Paramètres manquants :"
  for m in "${MISSING[@]}"; do echo "  - $m"; done
  echo ""
  echo "Usage : $0 --login <login> --password <password>"
  exit 1
fi

echo "========================================="
echo "   Initialisation vocabulaires KOS"
echo "========================================="
echo ""
log_info "Portail :  $KOS_URL"
log_info "Version :  $KOS_VERSION"
log_info "Login :    $KOS_ADMIN_LOGIN"
echo ""

# ─── Obtenir un token JWT ─────────────────────────────────────────────────────

log_info "Authentification..."

TOKEN_RESPONSE=$(curl -sk -X POST \
  "$KOS_URL/authenticate" \
  --data-urlencode "login=${KOS_ADMIN_LOGIN}" \
  --data-urlencode "password=${KOS_ADMIN_PASSWORD}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('jwtToken','').replace('Bearer ',''))" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
  log_error "Authentification échouée."
  log_error "Réponse : $TOKEN_RESPONSE"
  exit 1
fi
log_success "Token obtenu"

# ─── Vérifier si KOS est déjà initialisé ─────────────────────────────────────

EXISTING=$(curl -sk "$KOS_API/skosSchemes" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total',0))" 2>/dev/null)

if [ "${EXISTING:-0}" -gt 0 ]; then
  log_warning "KOS contient déjà $EXISTING schème(s) — rien à faire."
  exit 0
fi

# ─── Télécharger et importer les vocabulaires ─────────────────────────────────

import_scheme() {
  local name=$1
  local url=$2

  log_info "Téléchargement de $name depuis GitHub ($KOS_VERSION)..."
  local json
  json=$(curl -fsSL "$url" 2>/dev/null) || {
    log_error "Impossible de télécharger $name depuis : $url"
    exit 1
  }

  log_info "Import de $name..."
  local result
  result=$(curl -sk -X POST "$KOS_API/skosSchemes" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --data-raw "$json")

  if echo "$result" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('scheme_id') else 1)" 2>/dev/null; then
    log_success "$name importé"
  else
    log_error "Échec import $name : $result"
    exit 1
  fi
}

import_scheme "scheme-keyword (thèmes)" "$SCHEME_KEYWORD_URL"
import_scheme "scheme-licence (licences)" "$SCHEME_LICENCE_URL"

echo ""
echo "========================================="
echo "✓ Vocabulaires KOS initialisés !"
echo "========================================="
echo ""
log_info "Vérifier : $KOS_API/skosSchemes"
echo ""
