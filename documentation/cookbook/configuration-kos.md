# Comment initialiser les vocabulaires KOS ?

_Cas d'usage_ : je viens de déployer RUDI et je veux que le portail affiche les
thématiques et les licences correctement.

---

## Rôle de KOS dans RUDI

**KOS (Knowledge Organization System)** est le microservice de vocabulaire contrôlé
de RUDI. Il implémente le standard W3C SKOS et gère deux vocabulaires essentiels :

| Vocabulaire | Code | Contenu | Utilisé dans le portail |
|-------------|------|---------|------------------------|
| Thématiques | `scheme-keyword` | 14 thèmes : Économie, Transport, Santé, Environnement, Éducation, Culture… | Tuiles de la page d'accueil, filtres du catalogue, fiche dataset |
| Licences | `scheme-licence` | CC0, CC-BY, MIT, Apache, ODbL, Etalab 1.0/2.0… | Label de licence sur chaque jeu de données |

**Sans données KOS :**
- La page d'accueil n'affiche pas les tuiles thématiques
- Le catalogue n'a pas de filtres par thème
- Les fiches de jeux de données n'affichent pas le label de licence

---

## Pourquoi ces données ne sont-elles pas auto-initialisées ?

Les migrations Flyway de KOS créent uniquement le schéma de base de données
(tables `kos_data.*`). Elles n'insèrent aucune donnée. Les fichiers source
`scheme-keyword.json` et `scheme-licence.json` sont embarqués dans le jar KOS
mais doivent être importés manuellement via l'API REST.

---

## Importer les vocabulaires (déploiement vierge)

### Option A — Script automatisé

```bash
./scripts/init-kos.sh --login admin@example.com --password MonMotDePasse
```

Le script télécharge les schèmes directement depuis GitHub (tag correspondant à
`rudi_version` dans `.env`) et les importe via l'API KOS. Idempotent — ne fait
rien si les schèmes existent déjà.

```bash
# Spécifier un tag explicitement
./scripts/init-kos.sh --login admin@example.com --password MonMotDePasse \
  --version v3.4.1

# Via variables d'environnement
KOS_ADMIN_LOGIN=admin@example.com KOS_ADMIN_PASSWORD=MonMotDePasse \
  ./scripts/init-kos.sh
```

### Option B — Import manuel via l'API

Récupérer un token JWT puis importer directement depuis GitHub :

```bash
TOKEN="<votre-token-jwt>"
VERSION="$rudi_version"  # après set -a; source .env; set +a
BASE="https://raw.githubusercontent.com/rudi-platform/rudi-portal/$VERSION"
KOS_PATH="rudi-microservice/rudi-microservice-kos/rudi-microservice-kos-service/src/main/resources/skos"

# Importer les thèmes
curl -fsSL "$BASE/$KOS_PATH/scheme-keyword.json" | \
  curl -X POST "https://rudi.<domaine>/kos/v1/skosSchemes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d @-

# Importer les licences
curl -X POST "https://rudi.<domaine>/kos/v1/skosSchemes" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @-
```

### Option C — Import depuis le dump RUDI (si données de démonstration souhaitées)

Le dump `dummy-data/rudi/rudi.backup` contient les données KOS avec les thèmes
et licences. Pour importer uniquement la partie KOS :

```bash
# Restaurer uniquement le schéma kos_data depuis le dump
docker cp dummy-data/rudi/rudi.backup rudiplatform-database-1:/tmp/rudi.backup

docker exec -e PGPASSWORD="$DB_RUDI" rudiplatform-database-1 \
  pg_restore -U rudi -d rudi \
  --schema=kos_data \
  --clean --if-exists \
  /tmp/rudi.backup

docker exec rudiplatform-database-1 rm /tmp/rudi.backup
```

> Cette option importe uniquement les données du schéma `kos_data` sans
> toucher aux autres données (utilisateurs, organisations, datasets de démo).

---

## Vérifier l'import

```bash
# Lister les schèmes importés
curl -s "https://rudi.<domaine>/kos/v1/skosSchemes" | python3 -m json.tool

# Lister les thèmes
curl -s "https://rudi.<domaine>/kos/v1/skosConcepts?schemes=scheme-keyword" \
  | python3 -m json.tool

# Vérifier le nombre de concepts
curl -s "https://rudi.<domaine>/kos/v1/skosConcepts?schemes=scheme-keyword" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d[\"total\"]} thèmes')"
# Attendu : 14 thèmes
```

---

## Ajouter un thème personnalisé

L'API KOS permet d'ajouter des concepts à un schème existant.
Exemple : ajouter un thème "Intelligence artificielle" :

```bash
TOKEN="<votre-token-jwt>"
SCHEME_UUID="<uuid-du-scheme-keyword>"  # récupéré depuis GET /kos/v1/skosSchemes

curl -X POST \
  "https://rudi.<domaine>/kos/v1/skosSchemes/$SCHEME_UUID/skosConcepts?asTopConcept=true" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "concept_code": "artificial-intelligence",
    "concept_role": "theme",
    "concept_icon": "assets/pictos/economy.svg",
    "pref_label": [
      {"lang": "fr", "text": "Intelligence artificielle"},
      {"lang": "en", "text": "Artificial intelligence"}
    ]
  }'
```

---

## Persistance

Les données KOS sont stockées dans le schéma `kos_data` de la base de données
RUDI (partagée avec les autres microservices). Elles sont persistées dans
`database-data/rudi/` et survivent aux redémarrages des containers.

Aucune action particulière n'est nécessaire pour la persistance — sauvegarder
`database-data/rudi/` suffit à préserver les vocabulaires.
