#!/bin/bash
# init-dataverse.sh - Initialise Dataverse pour RUDI (déploiement vierge)
#
# Étapes :
#   1. Bootstrap Dataverse (gdcc/configbaker) : blocs de métadonnées standards,
#      rôles, utilisateur dataverseAdmin (mot de passe DATAVERSE_ADMIN_PASSWORD),
#      collection racine, licences
#   2. Écriture du token API de dataverseAdmin dans .env (DATAVERSE_API_TOKEN)
#   3. Chargement du bloc de métadonnées RUDI (rudi.tsv, depuis rudi-portal au tag rudi_version)
#   4. Création et publication des collections rudi_data, rudi_archive (blocs
#      citation + rudi) et rudi_media_data (bloc citation)
#   5. Facettes de recherche de rudi_data (thème, organisation productrice), lues par
#      konsult pour la section « Rechercher par thématique » et les filtres du catalogue
#
# Idempotent : chaque étape déjà effectuée est ignorée.
#
# Usage :
#   ./scripts/init-dataverse.sh [--email <contact>] [--version <tag>]
#
# Options (flags ou variables d'environnement) :
#   --email <email>      Contact des collections   (env: DATAVERSE_CONTACT_EMAIL, défaut: LETSENCRYPT_EMAIL)
#   --version <tag>      Tag rudi-portal pour rudi.tsv (env: RUDI_TSV_VERSION, défaut: rudi_version)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ─── Arguments ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)   DATAVERSE_CONTACT_EMAIL="$2"; shift 2 ;;
    --version) RUDI_TSV_VERSION="$2";        shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--email <contact>] [--version <tag>]"
      exit 0
      ;;
    *)
      log_error "Argument inconnu : $1"
      exit 1
      ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  log_error ".env introuvable"
  exit 1
fi
set -a; source "$ENV_FILE"; set +a

DATAVERSE_CONTACT_EMAIL="${DATAVERSE_CONTACT_EMAIL:-$LETSENCRYPT_EMAIL}"
RUDI_TSV_VERSION="${RUDI_TSV_VERSION:-$rudi_version}"
RUDI_TSV_URL="https://raw.githubusercontent.com/rudi-platform/rudi-portal/${RUDI_TSV_VERSION}/rudi-facet/rudi-facet-kaccess/src/main/resources/metadata/rudi.tsv"
CONTAINER="rudiplatform-dataverse-1"

if [ -z "$DATAVERSE_CONTACT_EMAIL" ]; then
  log_error "Email de contact manquant (--email ou LETSENCRYPT_EMAIL dans .env)"
  exit 1
fi

# Les endpoints /api/admin ne sont accessibles que depuis localhost après le
# bootstrap : tous les appels sont donc exécutés dans le conteneur Dataverse.
# Chaque réponse est vérifiée par l'appelant : un échec de curl ne doit pas
# interrompre le script en silence (set -e).
dv() {
  docker exec -i "$CONTAINER" curl -s "$@" || true
}

echo "========================================="
echo "   Initialisation Dataverse pour RUDI"
echo "========================================="
echo ""

# ─── Attendre Dataverse ───────────────────────────────────────────────────────

log_info "Attente de Dataverse..."
for i in $(seq 1 40); do
  if dv http://localhost:8080/api/info/version 2>/dev/null | grep -q '"version"'; then
    break
  fi
  if [ "$i" -eq 40 ]; then
    log_error "Dataverse ne répond pas (conteneur $CONTAINER)"
    exit 1
  fi
  sleep 15
done
log_success "Dataverse prêt"

# ─── 1. Bootstrap ─────────────────────────────────────────────────────────────
#
# On appelle directement setup-all.sh du configbaker (au lieu de bootstrap.sh)
# pour fixer le mot de passe de dataverseAdmin (-p=) et son email.

log_info "[1/5] Bootstrap Dataverse (configbaker ${dataverse_version})..."
API_TOKEN=""
BLOCK_COUNT=$(dv http://localhost:8080/api/metadatablocks | grep -o '"name"' | wc -l)

if [ "$BLOCK_COUNT" -gt 0 ]; then
  log_warning "Dataverse déjà initialisé — bootstrap ignoré"
else
  if [ -z "$DATAVERSE_ADMIN_PASSWORD" ]; then
    log_error "DATAVERSE_ADMIN_PASSWORD absent de .env (voir generate-passwords.sh)"
    exit 1
  fi
  ADMIN_JSON=$(mktemp)
  trap 'rm -f "$ADMIN_JSON"' EXIT
  printf '{"firstName":"Dataverse","lastName":"Admin","userName":"dataverseAdmin","affiliation":"RUDI","position":"Admin","email":"%s"}\n' \
    "$DATAVERSE_CONTACT_EMAIL" > "$ADMIN_JSON"
  chmod 644 "$ADMIN_JSON"

  # Le configbaker partage la pile réseau du conteneur Dataverse : ses appels
  # arrivent de localhost, seule origine autorisée sur /api/admin.
  BOOTSTRAP_OUT=$(docker run --rm --network "container:$CONTAINER" \
    -e DATAVERSE_URL=http://localhost:8080 \
    -e DV_PASSWORD="$DATAVERSE_ADMIN_PASSWORD" \
    -v "$ADMIN_JSON:/scripts/bootstrap/base/data/user-admin.json:ro" \
    "gdcc/configbaker:${dataverse_version}" \
    sh -c 'cd /scripts/bootstrap/base && ./setup-all.sh -p="$DV_PASSWORD"' 2>&1) || true

  # Le succès se juge sur la présence du token, pas sur le code de retour
  API_TOKEN=$(echo "$BOOTSTRAP_OUT" | grep -o '"apiToken":"[^"]*"' | head -n1 | cut -d'"' -f4)
  if [ -z "$API_TOKEN" ]; then
    log_error "Token API introuvable. Sortie du bootstrap :"
    echo "$BOOTSTRAP_OUT" >&2
    exit 1
  fi
  log_success "Bootstrap terminé (dataverseAdmin / DATAVERSE_ADMIN_PASSWORD)"
fi

# ─── 2. Token API dans .env ───────────────────────────────────────────────────

log_info "[2/5] Token API..."
if [ -n "$API_TOKEN" ]; then
  if grep -q "^DATAVERSE_API_TOKEN=" "$ENV_FILE"; then
    sed -i "s/^DATAVERSE_API_TOKEN=.*/DATAVERSE_API_TOKEN=${API_TOKEN}/" "$ENV_FILE"
  else
    echo "DATAVERSE_API_TOKEN=${API_TOKEN}" >> "$ENV_FILE"
  fi
  DATAVERSE_API_TOKEN="$API_TOKEN"
  log_success "DATAVERSE_API_TOKEN écrit dans .env"
else
  log_info "Utilisation du DATAVERSE_API_TOKEN existant de .env"
fi

if [ -z "$DATAVERSE_API_TOKEN" ]; then
  log_error "DATAVERSE_API_TOKEN absent de .env"
  exit 1
fi

# ─── 3. Bloc de métadonnées RUDI ──────────────────────────────────────────────

log_info "[3/5] Bloc de métadonnées rudi..."
if dv http://localhost:8080/api/metadatablocks/rudi | grep -q '"status":"OK"'; then
  log_warning "Bloc rudi déjà chargé — ignoré"
else
  log_info "Téléchargement de rudi.tsv ($RUDI_TSV_VERSION)..."
  RUDI_TSV=$(curl -fsSL "$RUDI_TSV_URL") || {
    log_error "Impossible de télécharger $RUDI_TSV_URL"
    exit 1
  }
  RESULT=$(echo "$RUDI_TSV" | dv -X POST \
    -H "Content-type: text/tab-separated-values" \
    --data-binary @- \
    http://localhost:8080/api/admin/datasetfield/load)
  if ! echo "$RESULT" | grep -q '"status":"OK"'; then
    log_error "Échec du chargement de rudi.tsv : $RESULT"
    exit 1
  fi
  log_success "Bloc rudi chargé"
fi

# ─── 4. Collections RUDI ──────────────────────────────────────────────────────

log_info "[4/5] Collections RUDI..."

# Une collection ne peut être publiée que si la collection racine l'est
if dv -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
     "http://localhost:8080/api/dataverses/:root" | grep -q '"isReleased":true'; then
  log_warning "Collection racine déjà publiée — ignorée"
else
  RESULT=$(dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
    "http://localhost:8080/api/dataverses/:root/actions/:publish")
  if ! echo "$RESULT" | grep -q '"status":"OK"'; then
    log_error "Échec de la publication de la collection racine : $RESULT"
    exit 1
  fi
  log_success "Collection racine publiée"
fi

# Chaque étape est idempotente : une relance termine une collection
# partiellement initialisée.
create_collection() {
  local alias=$1 name=$2 blocks=$3 info result

  info=$(dv -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" "http://localhost:8080/api/dataverses/$alias")

  if ! echo "$info" | grep -q '"status":"OK"'; then
    result=$(dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
      -H "Content-type: application/json" \
      "http://localhost:8080/api/dataverses/:root" \
      -d "{\"alias\":\"$alias\",\"name\":\"$name\",\"dataverseType\":\"UNCATEGORIZED\",\"dataverseContacts\":[{\"contactEmail\":\"$DATAVERSE_CONTACT_EMAIL\"}]}")
    if ! echo "$result" | grep -q '"status":"OK"'; then
      log_error "Échec de la création de $alias : $result"
      exit 1
    fi
    log_success "Collection $alias créée"
  fi

  result=$(dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
    -H "Content-type: application/json" \
    "http://localhost:8080/api/dataverses/$alias/metadatablocks" \
    -d "$blocks")
  if ! echo "$result" | grep -q '"status":"OK"'; then
    log_error "Échec de l'association des blocs $blocks à $alias : $result"
    exit 1
  fi

  if echo "$info" | grep -q '"isReleased":true'; then
    log_warning "Collection $alias déjà publiée"
    return
  fi

  result=$(dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
    "http://localhost:8080/api/dataverses/$alias/actions/:publish")
  if ! echo "$result" | grep -q '"status":"OK"'; then
    log_error "Échec de la publication de $alias : $result"
    exit 1
  fi
  log_success "Collection $alias publiée (blocs $blocks)"
}

# Les médias du portail (logos, images de projets) n'utilisent que le bloc
# citation : les champs obligatoires du bloc rudi ne les concernent pas.
create_collection "rudi_data"       "RUDI Data"    '["citation","rudi"]'
create_collection "rudi_archive"    "RUDI Archive" '["citation","rudi"]'
create_collection "rudi_media_data" "RUDI Media"   '["citation"]'

# ─── 5. Facettes de recherche ─────────────────────────────────────────────────
#
# konsult lit les valeurs de ces champs dans les facettes de la recherche
# Dataverse (show_facets) : sans elles, la liste des thèmes est vide et l'accueil
# du portail reste en chargement. Dataverse ne renvoie que les facettes
# configurées sur la collection. L'appel remplace la liste : il est idempotent.

log_info "[5/5] Facettes de recherche de rudi_data..."
RUDI_FACETS='["rudi_theme","rudi_keywords","rudi_producer_organization_name","rudi_temporal_spread_start_date","rudi_temporal_spread_end_date","rudi_producer_organization_id"]'
RESULT=$(dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
  -H "Content-type: application/json" \
  "http://localhost:8080/api/dataverses/rudi_data/facets" \
  -d "$RUDI_FACETS")
if ! echo "$RESULT" | grep -q '"status":"OK"'; then
  log_error "Échec de la configuration des facettes de rudi_data : $RESULT"
  exit 1
fi
log_success "Facettes de rudi_data : $RUDI_FACETS"

echo ""
echo "========================================="
echo "✓ Dataverse initialisé pour RUDI"
echo "========================================="
echo ""
log_info "Connexion : https://${DATAVERSE_DOMAIN:-dataverse.${base_dn}} — dataverseAdmin / DATAVERSE_ADMIN_PASSWORD (.env)"
echo ""
if [ -n "$API_TOKEN" ]; then
  log_info "Le token a changé : regénérer les propriétés RUDI puis (re)démarrer les microservices :"
  echo "  ./scripts/prepare-properties.sh"
fi
echo ""
