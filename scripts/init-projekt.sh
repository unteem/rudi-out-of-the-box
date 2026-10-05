#!/bin/bash
# init-projekt.sh - Synchronise les listes de référence des réutilisations (projekt)
#
# Listes gérées : type de réutilisation, échelle territoriale, public cible,
# accompagnement souhaité. Les valeurs sont lues dans un fichier JSON :
#   config/projekt/referentiels.json         (personnalisé, non versionné)
#   config/projekt/referentiels.example.json (valeurs par défaut)
#
# Chaque entrée est identifiée par son code : créée si absente, mise à jour si
# son libellé, son ordre ou son état ("closed": true) diffère. Rien n'est
# supprimé. Le script peut être relancé à chaque modification du fichier.
#
# Usage :
#   ./scripts/init-projekt.sh --login admin@example.com --password MonMotDePasse
#
# Options (flags ou variables d'environnement) :
#   --login <login>      Login de l'administrateur  (env: PROJEKT_ADMIN_LOGIN)
#   --password <pass>    Mot de passe               (env: PROJEKT_ADMIN_PASSWORD)
#   --url <url>          URL du portail             (env: PROJEKT_URL, défaut: https://rudi.<base_dn>)
#   --file <fichier>     Fichier de référentiels    (env: PROJEKT_REFERENTIELS)
#   --dry-run            Affiche les changements sans les appliquer

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

DRY_RUN=false

# ─── Parse arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --login)    PROJEKT_ADMIN_LOGIN="$2";    shift 2 ;;
    --password) PROJEKT_ADMIN_PASSWORD="$2"; shift 2 ;;
    --url)      PROJEKT_URL="$2";            shift 2 ;;
    --file)     PROJEKT_REFERENTIELS="$2";   shift 2 ;;
    --dry-run)  DRY_RUN=true;                shift ;;
    -h|--help)
      echo "Usage: $0 --login <login> --password <password> [--url <url>] [--file <json>] [--dry-run]"
      echo ""
      echo "Variables d'environnement équivalentes :"
      echo "  PROJEKT_ADMIN_LOGIN, PROJEKT_ADMIN_PASSWORD, PROJEKT_URL, PROJEKT_REFERENTIELS"
      exit 0
      ;;
    *)
      log_error "Argument inconnu : $1"
      echo "Lancer '$0 --help' pour l'usage."
      exit 1
      ;;
  esac
done

# ─── Charger .env pour base_dn ────────────────────────────────────────────────

if [ -f "$ROOT_DIR/.env" ]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi

# ─── Valeurs par défaut ───────────────────────────────────────────────────────

PROJEKT_URL="${PROJEKT_URL:-https://rudi.${base_dn}}"

if [ -z "$PROJEKT_REFERENTIELS" ]; then
  if [ -f "$ROOT_DIR/config/projekt/referentiels.json" ]; then
    PROJEKT_REFERENTIELS="$ROOT_DIR/config/projekt/referentiels.json"
  else
    PROJEKT_REFERENTIELS="$ROOT_DIR/config/projekt/referentiels.example.json"
  fi
fi

# ─── Validation ───────────────────────────────────────────────────────────────

MISSING=()
[ -z "$PROJEKT_ADMIN_LOGIN" ]    && MISSING+=("PROJEKT_ADMIN_LOGIN (--login)")
[ -z "$PROJEKT_ADMIN_PASSWORD" ] && MISSING+=("PROJEKT_ADMIN_PASSWORD (--password)")

if [ ${#MISSING[@]} -gt 0 ]; then
  log_error "Paramètres manquants :"
  for m in "${MISSING[@]}"; do echo "  - $m"; done
  echo ""
  echo "Usage : $0 --login <login> --password <password>"
  exit 1
fi

if [ ! -f "$PROJEKT_REFERENTIELS" ]; then
  log_error "Fichier introuvable : $PROJEKT_REFERENTIELS"
  exit 1
fi

echo "========================================="
echo "   Listes de référence des réutilisations"
echo "========================================="
echo ""
log_info "Portail : $PROJEKT_URL"
log_info "Fichier : $PROJEKT_REFERENTIELS"
log_info "Login :   $PROJEKT_ADMIN_LOGIN"
$DRY_RUN && log_warning "Mode --dry-run : aucune modification ne sera appliquée"
echo ""

# ─── Obtenir un token JWT ─────────────────────────────────────────────────────

log_info "Authentification..."

TOKEN_RESPONSE=$(curl -sk -X POST \
  "$PROJEKT_URL/authenticate" \
  --data-urlencode "login=${PROJEKT_ADMIN_LOGIN}" \
  --data-urlencode "password=${PROJEKT_ADMIN_PASSWORD}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('jwtToken','').replace('Bearer ',''))" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
  log_error "Authentification échouée."
  log_error "Réponse : $TOKEN_RESPONSE"
  exit 1
fi
log_success "Token obtenu"
echo ""

# ─── Synchronisation ──────────────────────────────────────────────────────────

API="$PROJEKT_URL/projekt/v1" TOKEN="$ACCESS_TOKEN" FILE="$PROJEKT_REFERENTIELS" DRY_RUN="$DRY_RUN" \
python3 - <<'EOF'
import json, os, ssl, sys, urllib.request, urllib.error
from datetime import datetime

API, TOKEN, FILE = os.environ["API"], os.environ["TOKEN"], os.environ["FILE"]
DRY_RUN = os.environ["DRY_RUN"] == "true"
CTX = ssl._create_unverified_context()
NOW = datetime.now().isoformat(timespec="seconds")

# clé du fichier -> (libellé, ressource API, PUT avec l'UUID dans le chemin)
LISTS = {
    "types":              ("Type de réutilisation",   "types",              True),
    "territorial_scales": ("Échelle",                 "territorial-scales", True),
    "target_audiences":   ("Public cible",            "target-audience",    False),
    "supports":           ("Accompagnement souhaité", "supports",           True),
}

def call(method, path, body=None):
    req = urllib.request.Request(
        f"{API}/{path}", method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, context=CTX) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.exit(f"[ERROR] {method} {path} : HTTP {e.code} {e.read().decode(errors='replace')[:300]}")

try:
    wanted = json.load(open(FILE, encoding="utf-8"))
except ValueError as e:
    sys.exit(f"[ERROR] {FILE} n'est pas un JSON valide : {e}")

unknown = set(wanted) - set(LISTS)
if unknown:
    sys.exit(f"[ERROR] Listes inconnues dans {FILE} : {', '.join(sorted(unknown))} "
             f"(attendues : {', '.join(LISTS)})")

for key, (title, resource, uuid_in_path) in LISTS.items():
    if key not in wanted:
        continue
    print(f"── {title} ({resource})")
    existing = {e["code"]: e for e in (call("GET", f"{resource}?limit=1000") or {}).get("elements", [])}
    seen = set()
    for item in wanted[key]:
        code, label = item.get("code", ""), item.get("label", "")
        if not code or not label or len(code) > 30 or len(label) > 100:
            sys.exit(f"[ERROR] Entrée invalide dans '{key}' : {item} "
                     "(code ≤ 30 caractères et label ≤ 100 caractères obligatoires)")
        if code in seen:
            sys.exit(f"[ERROR] Code en double dans '{key}' : {code}")
        seen.add(code)
        order = int(item.get("order", len(seen)))
        closed = bool(item.get("closed", False))
        current = existing.get(code)

        if current is None:
            if closed:
                print(f"   =  {code} : fermé et absent du portail, ignoré")
                continue
            print(f"   +  {code} : {label}")
            if not DRY_RUN:
                call("POST", resource, {"code": code, "label": label, "order": order, "opening_date": NOW})
            continue

        is_closed = bool(current.get("closing_date"))
        if current.get("label") == label and current.get("order") == order and is_closed == closed:
            print(f"   =  {code} : {label}")
            continue

        update = dict(current, label=label, order=order)
        if closed and not is_closed:
            update["closing_date"] = NOW
        elif not closed:
            update["closing_date"] = None
        print(f"   ~  {code} : {label}" + (" (fermé)" if closed else ""))
        if not DRY_RUN:
            call("PUT", f"{resource}/{current['uuid']}" if uuid_in_path else resource, update)

    for code, e in existing.items():
        if code not in seen and not e.get("closing_date"):
            print(f"   ?  {code} : {e.get('label')} — présent sur le portail mais absent du fichier "
                  "(ajouter \"closed\": true pour le retirer du formulaire)")
EOF

echo ""
log_success "Listes de référence synchronisées"
echo ""
