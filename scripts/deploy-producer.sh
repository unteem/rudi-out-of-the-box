#!/bin/bash
# deploy-producer.sh - Déclare un nœud producteur via l'API RUDI
#
# Étapes (voir documentation/cookbook/configuration-producer-node.md) :
#   1. Authentification administrateur
#   2. Création du fournisseur (strukture)
#   3. Déclaration du nœud producteur (strukture)
#   4. Création de l'utilisateur ROBOT (acl)
#
# Usage :
#   ./scripts/deploy-producer.sh --domain producteur.example.com --login admin@example.com --password MonPass
#
# Options (flags ou variables d'environnement) :
#   --domain   <domaine>   Domaine du nœud producteur        (env: PRODUCER_DOMAIN)
#   --portal   <url>       URL du portail                    (env: MAIN_PORTAL, défaut: https://rudi.<base_dn>)
#   --login    <login>     Login administrateur RUDI         (env: RUDI_ADMIN_LOGIN)
#   --password <password>  Mot de passe administrateur       (env: RUDI_ADMIN_PASSWORD)
#   --label    <label>     Nom du fournisseur                (env: PRODUCER_LABEL, défaut: domaine)

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
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ─── Parse arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)   PRODUCER_DOMAIN="$2";     shift 2 ;;
    --portal)   MAIN_PORTAL="$2";         shift 2 ;;
    --login)    RUDI_ADMIN_LOGIN="$2";    shift 2 ;;
    --password) RUDI_ADMIN_PASSWORD="$2"; shift 2 ;;
    --label)    PRODUCER_LABEL="$2";      shift 2 ;;
    -h|--help)
      echo "Usage: $0 --domain <domaine> --login <login> --password <password> [options]"
      echo ""
      echo "Options :"
      echo "  --domain   Domaine du nœud producteur"
      echo "  --portal   URL du portail (défaut: https://rudi.<base_dn>)"
      echo "  --login    Login administrateur RUDI"
      echo "  --password Mot de passe administrateur"
      echo "  --label    Nom du fournisseur (défaut: domaine)"
      exit 0
      ;;
    *)
      log_error "Argument inconnu : $1"
      echo "Lancer '$0 --help' pour l'usage."
      exit 1
      ;;
  esac
done

# ─── Charger .env ─────────────────────────────────────────────────────────────

if [ -f "$ROOT_DIR/.env" ]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi

MAIN_PORTAL="${MAIN_PORTAL:-https://rudi.${base_dn}}"
PRODUCER_LABEL="${PRODUCER_LABEL:-$PRODUCER_DOMAIN}"

# ─── Validation ───────────────────────────────────────────────────────────────

MISSING=()
[ -z "$PRODUCER_DOMAIN" ]     && MISSING+=("PRODUCER_DOMAIN (--domain)")
[ -z "$RUDI_ADMIN_LOGIN" ]    && MISSING+=("RUDI_ADMIN_LOGIN (--login)")
[ -z "$RUDI_ADMIN_PASSWORD" ] && MISSING+=("RUDI_ADMIN_PASSWORD (--password)")

if [ ${#MISSING[@]} -gt 0 ]; then
  log_error "Paramètres manquants :"
  for m in "${MISSING[@]}"; do echo "  - $m"; done
  echo ""
  echo "Usage : $0 --domain <domaine> --login <login> --password <password>"
  exit 1
fi

# URL de l'API du nœud : kalim y ajoute /resources pour le moissonnage
NODE_URL="https://$PRODUCER_DOMAIN/catalog/v1"

echo "========================================="
echo "   Déclaration Nœud Producteur RUDI"
echo "========================================="
echo ""
log_info "Portail :    $MAIN_PORTAL"
log_info "Nœud :       $NODE_URL"
log_info "Fournisseur : $PRODUCER_LABEL"
echo ""

# ─── Credentials ROBOT ────────────────────────────────────────────────────────
#
# Les UUID du fournisseur et du nœud sont générés par strukture et lus dans
# ses réponses : les UUID envoyés dans les requêtes sont ignorés.

ROBOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
ROBOT_PASSWORD_B64=$(echo -n "$ROBOT_PASSWORD" | base64 -w 0)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PROVIDER_UUID=""
DONE=false

# ─── Helpers API ──────────────────────────────────────────────────────────────

# api_call <méthode> <url> [json] : appel authentifié ; affiche le corps de la
# réponse, renvoie 1 si le code HTTP n'est pas 2xx
api_call() {
  local response http_code body
  response=$(curl -sk --max-time 30 -w "\n%{http_code}" -X "$1" "$2" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    ${3:+-d "$3"})
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [[ ! "$http_code" =~ ^2 ]]; then
    log_error "$1 $2 → HTTP $http_code"
    log_error "Réponse : $body"
    return 1
  fi
  echo "$body"
}

json_uuid() {
  python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null
}

# En cas d'échec après la création du fournisseur, on le supprime pour ne pas
# laisser de déclaration partielle dans le portail.
rollback() {
  if ! $DONE && [ -n "$PROVIDER_UUID" ]; then
    log_warning "Échec : suppression du fournisseur $PROVIDER_UUID"
    api_call DELETE "$MAIN_PORTAL/strukture/v1/providers/$PROVIDER_UUID" > /dev/null \
      || log_error "Suppression impossible : supprimer le fournisseur manuellement"
  fi
}
trap rollback EXIT

# ─── Étape 1 — Authentification ───────────────────────────────────────────────

log_info "[1/4] Authentification..."

TOKEN_RESPONSE=$(curl -sk --max-time 30 -X POST "$MAIN_PORTAL/authenticate" \
  --data-urlencode "login=${RUDI_ADMIN_LOGIN}" \
  --data-urlencode "password=${RUDI_ADMIN_PASSWORD}")

TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('jwtToken','').replace('Bearer ',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  log_error "Authentification échouée sur $MAIN_PORTAL/authenticate"
  log_error "Réponse : $TOKEN_RESPONSE"
  exit 1
fi
log_success "Authentifié"

# ─── Étape 2 — Créer le fournisseur ───────────────────────────────────────────

log_info "[2/4] Création du fournisseur..."

PROVIDER_CODE=$(echo "$PRODUCER_LABEL" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

PROVIDER_UUID=$(api_call POST "$MAIN_PORTAL/strukture/v1/providers" "{
  \"code\": \"$PROVIDER_CODE\",
  \"label\": \"$PRODUCER_LABEL\",
  \"openingDate\": \"$NOW\"
}" | json_uuid)
if [ -z "$PROVIDER_UUID" ]; then
  log_error "UUID du fournisseur absent de la réponse"
  exit 1
fi
log_success "Fournisseur créé (UUID : $PROVIDER_UUID)"

# ─── Étape 3 — Déclarer le nœud ───────────────────────────────────────────────

log_info "[3/4] Déclaration du nœud..."

NODE_UUID=$(api_call POST "$MAIN_PORTAL/strukture/v1/providers/$PROVIDER_UUID/nodes" "{
  \"version\": \"v1\",
  \"url\": \"$NODE_URL\",
  \"openingDate\": \"$NOW\",
  \"notifiable\": true,
  \"harvestable\": true
}" | json_uuid)
if [ -z "$NODE_UUID" ]; then
  log_error "Échec de la déclaration du nœud"
  exit 1
fi
log_success "Nœud déclaré (UUID : $NODE_UUID, URL : $NODE_URL)"

# ─── Étape 4 — Créer l'utilisateur ROBOT ──────────────────────────────────────

log_info "[4/4] Création de l'utilisateur ROBOT..."

# Le login du compte ROBOT est l'UUID du nœud : strukture et kalim retrouvent
# le nœud authentifié par ce login (getNodeProviderFromUser, getAuthenticatedNodeProvider)
api_call POST "$MAIN_PORTAL/acl/v1/users" "{
  \"login\": \"$NODE_UUID\",
  \"password\": \"$ROBOT_PASSWORD\",
  \"lastname\": \"$PRODUCER_LABEL\",
  \"firstname\": \"Nœud Producteur\",
  \"company\": \"$PRODUCER_LABEL\",
  \"type\": \"ROBOT\",
  \"roles\": [{
    \"uuid\": \"af8cbc17-b7e0-43c1-92e2-f42a1d18e103\",
    \"code\": \"PROVIDER\"
  }]
}" > /dev/null || exit 1
log_success "Utilisateur ROBOT créé"
DONE=true

# ─── Fichier d'identifiants du manager (SU=..., à renseigner après démarrage) ─

mkdir -p "$ROOT_DIR/config/producer"
touch "$ROOT_DIR/config/producer/manager.env"
chmod 600 "$ROOT_DIR/config/producer/manager.env"

# ─── Écrire les credentials dans .env ─────────────────────────────────────────

log_info "Mise à jour de .env..."

ENV_FILE="$ROOT_DIR/.env"
sed -i "/^PRODUCER_DOMAIN=/d"        "$ENV_FILE"
sed -i "/^PRODUCER_UUID=/d"          "$ENV_FILE"
sed -i "/^PRODUCER_NODE_UUID=/d"     "$ENV_FILE"
sed -i "/^PRODUCER_PROVIDER_UUID=/d" "$ENV_FILE"
sed -i "/^PRODUCER_PASSWORD=/d"      "$ENV_FILE"
sed -i "/^PRODUCER_PASSWORD_B64=/d"  "$ENV_FILE"

cat >> "$ENV_FILE" << EOF
PRODUCER_DOMAIN=${PRODUCER_DOMAIN}
PRODUCER_PROVIDER_UUID=${PROVIDER_UUID}
PRODUCER_NODE_UUID=${NODE_UUID}
PRODUCER_PASSWORD=${ROBOT_PASSWORD}
PRODUCER_PASSWORD_B64=${ROBOT_PASSWORD_B64}
EOF

log_success ".env mis à jour"

# ─── Résumé ───────────────────────────────────────────────────────────────────

echo ""
echo "========================================="
echo "Nœud producteur déclaré !"
echo "========================================="
echo ""
echo "Fournisseur UUID : $PROVIDER_UUID"
echo "Nœud UUID :       $NODE_UUID"
echo "Nœud URL :        $NODE_URL"
echo ""
echo "Credentials ROBOT (écrits dans .env) :"
echo "  Login (= UUID du nœud) : $NODE_UUID"
echo "  Password :              $ROBOT_PASSWORD"
echo "  Password (base64) :     $ROBOT_PASSWORD_B64"
echo ""
echo "Démarrer le nœud producteur :"
echo "  docker compose -f docker-compose-producer.yml up -d"
echo ""
log_warning "Puis définir les identifiants du manager (variable SU) :"
echo "  voir « Étape 3 — Définir les identifiants du manager » dans documentation/cookbook/configuration-producer-node.md"
echo ""
log_info "Voir documentation/cookbook/configuration-producer-node.md pour les détails"
echo ""
