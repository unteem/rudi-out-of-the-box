# Comment déployer et déclarer un nœud producteur RUDI ?

_Cas d'usage_ : je veux connecter un nœud producteur RUDI au portail afin
qu'il puisse publier des jeux de données.

---

## Architecture

Un nœud producteur RUDI est composé de :

- **L'application `rudinode`** : base MongoDB et modules catalog, storage et
  manager (`docker-compose-producer.yml`), sur le même serveur et derrière le
  même Traefik que le portail
- **Trois entités dans le portail** :
  1. **Fournisseur** (`strukture`) : l'organisation qui opère le nœud
  2. **Nœud** (`strukture`) : l'URL technique du nœud
  3. **Utilisateur ROBOT** (`acl`) : le compte machine utilisé par le nœud

Le `login` de l'utilisateur ROBOT est **l'UUID du nœud** : c'est ainsi que
strukture et kalim retrouvent le nœud (et son fournisseur) à partir des appels
authentifiés. Attention, la collection Bruno indique à tort l'UUID du
fournisseur.

Le nœud a besoin de ces identifiants pour démarrer : on le **déclare d'abord**
dans le portail, puis on le **démarre**.

Pour comprendre comment les données circulent ensuite entre le nœud et le
portail, voir [Comment une donnée est-elle publiée sur le portail RUDI ?](./cycle-de-vie-donnees.md).

---

## Prérequis

- Le portail RUDI est démarré et accessible
- Un compte administrateur RUDI (`ADMINISTRATOR`)
- Le DNS `producteur.<domaine>` pointe vers le serveur
- Le répertoire `data/producer` appartient à l'UID 5001 (étape 3 de
  [roob-to-prod.md](./roob-to-prod.md#étape-3--créer-les-répertoires)) :

  ```bash
  mkdir -p data/producer && sudo chown -R 5001:5001 data/producer
  ```

---

## Étape 1 — Déclarer le nœud dans le portail

### Option A — Script automatisé

```bash
./scripts/deploy-producer.sh \
  --domain producteur.mondomaine.fr \
  --login admin@mondomaine.fr \
  --password 'MonMotDePasse!' \
  --label "Mon Organisation Productrice"
```

Le script effectue les appels de l'option B, écrit `PRODUCER_DOMAIN`,
`PRODUCER_PROVIDER_UUID`, `PRODUCER_NODE_UUID`, `PRODUCER_PASSWORD` et
`PRODUCER_PASSWORD_B64` dans `.env` et
crée le fichier vide `config/producer/manager.env` (voir étape 3). En cas
d'échec, il supprime le fournisseur créé.

### Option B — Appels API manuels

Mettre les mots de passe entre guillemets **simples** : entre guillemets
doubles, bash interprète `!`.

**S'authentifier :**

```bash
RUDI_URL="https://rudi.mondomaine.fr"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

TOKEN=$(curl -sf -X POST "$RUDI_URL/authenticate" \
  --data-urlencode 'login=admin@mondomaine.fr' \
  --data-urlencode 'password=MonMotDePasse!' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['jwtToken'].replace('Bearer ',''))")
```

**Créer le fournisseur.** strukture génère lui-même l'UUID (un UUID envoyé dans
la requête est ignoré) : on le lit dans la réponse.

```bash
PROVIDER_UUID=$(curl -sf -X POST "$RUDI_URL/strukture/v1/providers" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"code\": \"mon-organisation\",
    \"label\": \"Mon Organisation Productrice\",
    \"openingDate\": \"$NOW\"
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
echo "Fournisseur : $PROVIDER_UUID"
```

**Déclarer le nœud.** L'URL est celle de l'API publique du catalog
(`/catalog/v1`) : le portail y ajoute `/resources` pour moissonner les
métadonnées.

```bash
NODE_UUID=$(curl -sf -X POST "$RUDI_URL/strukture/v1/providers/$PROVIDER_UUID/nodes" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"version\": \"v1\",
    \"url\": \"https://producteur.mondomaine.fr/catalog/v1\",
    \"openingDate\": \"$NOW\",
    \"notifiable\": true,
    \"harvestable\": true
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
echo "Nœud : $NODE_UUID"
```

**Créer l'utilisateur ROBOT**, dont le login est l'UUID du nœud :

```bash
ROBOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

curl -sf -X POST "$RUDI_URL/acl/v1/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"login\": \"$NODE_UUID\",
    \"password\": \"$ROBOT_PASSWORD\",
    \"lastname\": \"Mon Organisation\",
    \"firstname\": \"Nœud Producteur\",
    \"company\": \"Mon Organisation\",
    \"type\": \"ROBOT\",
    \"roles\": [{\"uuid\": \"af8cbc17-b7e0-43c1-92e2-f42a1d18e103\", \"code\": \"PROVIDER\"}]
  }"
```

**Renseigner `.env`** et préparer le fichier d'identifiants du manager :

```bash
cat >> .env << EOF
PRODUCER_DOMAIN=producteur.mondomaine.fr
PRODUCER_PROVIDER_UUID=$PROVIDER_UUID
PRODUCER_NODE_UUID=$NODE_UUID
PRODUCER_PASSWORD=$ROBOT_PASSWORD
PRODUCER_PASSWORD_B64=$(echo -n "$ROBOT_PASSWORD" | base64 -w 0)
EOF

mkdir -p config/producer
touch config/producer/manager.env && chmod 600 config/producer/manager.env
```

---

## Étape 2 — Démarrer le nœud

```bash
docker compose -f docker-compose-producer.yml up -d
```

Le nœud reprend le découpage du dépôt `rudi-node-container` : quatre conteneurs
issus de l'image `rudinode` (`rudinode_image:rudinode_version` dans `.env`),
qui partagent le volume `data/producer` (base, médias, clés, logs).

| Conteneur | Port interne | Route publique | Rôle |
|-----------|--------------|----------------|------|
| `producer-db` | 27017 | — | MongoDB |
| `producer-catalog` | 3030 | `/catalog` (et `/api`, redirigé) | API des métadonnées |
| `producer-storage` | 3031 | `/storage` | Fichiers de données |
| `producer-manager` | 3032 | `/manager` | Interface d'administration (`/manager/`) |

Points de configuration propres à ce découpage, déjà présents dans
`docker-compose-producer.yml` :

- `CATALOG_MIGRATION_ACTIVE=true` (catalog) : applique les migrations du schéma
  MongoDB au démarrage ; sans cela, le catalog refuse de démarrer sur une base
  neuve.
- `SAFE_DIR=/data/safe/manager` (manager) : conserve sur le volume les clés avec
  lesquelles le manager signe ses requêtes vers le catalog et le storage.

---

## Étape 3 — Définir les identifiants du manager

Au premier démarrage, le manager crée un super-administrateur `PM Admin` dont
le mot de passe est celui de la configuration par défaut de l'image, identique
pour toutes les instances. Il faut le remplacer : on fait hacher ses propres
identifiants par le manager, puis on les lui passe dans la variable `SU`, qui
écrase le super-administrateur existant.

```bash
# 1. Hacher identifiant + mot de passe (API ouverte du manager)
SU=$(curl -s --json '{"usr": "admin", "pwd": "MonMotDePasse!"}' \
  https://producteur.mondomaine.fr/manager/api/open/hash-credentials)
echo "$SU"   # chaîne base64 « usr:mot_de_passe_haché »

# 2. Fichier lu par le service producer-manager (exclu de git)
echo "SU=$SU" > config/producer/manager.env

# 3. Recréer le manager
docker compose -f docker-compose-producer.yml up -d producer-manager
```

Le compte est enregistré dans la base du manager (`data/producer/db`). Le
fichier peut être conservé : il réapplique les mêmes identifiants à chaque
démarrage.

---

## Étape 4 — Vérifier

```bash
# API publique du catalog
curl -s https://producteur.mondomaine.fr/catalog/v1/resources | head -c 200

# Manager (doit retourner "test")
curl -s https://producteur.mondomaine.fr/manager/api/open/test

# Côté portail : fournisseur et nœud déclarés
curl -sf -H "Authorization: Bearer $TOKEN" \
  "$RUDI_URL/strukture/v1/providers/$PROVIDER_UUID/nodes" | python3 -m json.tool
```

Se connecter ensuite au manager sur `https://producteur.mondomaine.fr/manager/`
avec les identifiants de l'étape 3.

---

## Opérations de maintenance

### Modifier l'URL du nœud

```bash
curl -sf -X PATCH "$RUDI_URL/strukture/v1/providers/$PROVIDER_UUID/nodes/$NODE_UUID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"https://nouvelle-url.fr/catalog/v1\"}"
```

### Supprimer un fournisseur

```bash
curl -sf -X DELETE -H "Authorization: Bearer $TOKEN" \
  "$RUDI_URL/strukture/v1/providers/$PROVIDER_UUID"
```

### Logs du nœud producteur

```bash
docker compose -f docker-compose-producer.yml logs -f
```
