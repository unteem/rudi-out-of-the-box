# Comment configurer Dataverse et Solr pour RUDI ?

_Cas d'usage_ : je déploie RUDI sur un serveur vierge et je dois préparer
Dataverse pour qu'il accueille les métadonnées des jeux de données.

---

## Rôle de Dataverse et Solr dans RUDI

**Dataverse** est la base de métadonnées du catalogue RUDI. Il ne stocke pas
les fichiers des producteurs, qui restent sur les nœuds producteurs (voir
[Comment une donnée est-elle publiée sur le portail RUDI ?](./cycle-de-vie-donnees.md)).

| Collection | Contenu | Utilisée par |
|------------|---------|--------------|
| `rudi_data` | Métadonnées des jeux de données publiés | kalim (écriture), konsult, apigateway (lecture) |
| `rudi_archive` | Jeux de données supprimés / archivés | kalim |
| `rudi_media_data` | Médias propres au portail (logos, images de projets) | strukture, projekt, selfdata |

Les métadonnées RUDI sont décrites par un **bloc de métadonnées personnalisé**
`rudi` (fichier `rudi.tsv` du dépôt rudi-portal), en plus du bloc standard
`citation`.

**Solr** est le moteur d'indexation de Dataverse. Son schéma doit contenir les
champs `rudi_*` et les types `text_fr` / `rudi_id` : il est versionné dans
`config/solr/collection1/conf/` et copié dans le core `collection1` à sa
première création.

**Images utilisées** (officielles, aucun build local) :

| Service | Image |
|---------|-------|
| `dataverse` | `gdcc/dataverse:${dataverse_version}` |
| `solr` | `solr:9.8.0` |
| `dataverse-database` | `postgres:15.12-bookworm` |
| bootstrap (one-shot) | `gdcc/configbaker:${dataverse_version}` |

---

## Démarrer Dataverse et Solr

```bash
docker compose -f docker-compose-dataverse.yml up -d dataverse-database
docker compose -f docker-compose-dataverse.yml -f docker-compose-network.yml \
  --profile dataverse up -d
```

Dataverse met **3 à 5 minutes** à démarrer (déploiement Payara).

---

## Initialiser Dataverse pour RUDI (une seule fois)

### Option A — Script automatisé

```bash
./scripts/init-dataverse.sh
./scripts/prepare-properties.sh
```

Le script est idempotent et effectue les étapes 1 à 4 ci-dessous. Il écrit le
token API dans `.env` ; `prepare-properties.sh` le reporte dans les propriétés
des microservices.

### Option B — Étapes manuelles

Les endpoints `/api/admin` et `/api/builtin-users` de Dataverse ne sont
accessibles que depuis `localhost` (`dataverse_api_blocked_policy=localhost-only`
dans `docker-compose-dataverse.yml`) : les commandes ci-dessous sont donc
exécutées dans le conteneur Dataverse, ou dans un conteneur qui partage sa pile
réseau (`--network container:rudiplatform-dataverse-1`).

```bash
set -a; source .env; set +a
dv() { docker exec -i rudiplatform-dataverse-1 curl -s "$@"; }
```

#### Étape 1 — Bootstrap

Charge les blocs de métadonnées standards, les rôles, l'authentification
intégrée, l'utilisateur `dataverseAdmin`, la collection racine et les licences.
On appelle `setup-all.sh` du configbaker pour fixer le mot de passe de
`dataverseAdmin` (`DATAVERSE_ADMIN_PASSWORD`, généré dans `.env`) et son email :

```bash
cat > /tmp/user-admin.json << EOF
{"firstName":"Dataverse","lastName":"Admin","userName":"dataverseAdmin","affiliation":"RUDI","position":"Admin","email":"$LETSENCRYPT_EMAIL"}
EOF

docker run --rm --network container:rudiplatform-dataverse-1 \
  -e DATAVERSE_URL=http://localhost:8080 \
  -e DV_PASSWORD="$DATAVERSE_ADMIN_PASSWORD" \
  -v /tmp/user-admin.json:/scripts/bootstrap/base/data/user-admin.json:ro \
  "gdcc/configbaker:${dataverse_version}" \
  sh -c 'cd /scripts/bootstrap/base && ./setup-all.sh -p="$DV_PASSWORD"'
```

La sortie contient le token API de `dataverseAdmin` :
`{"status":"OK","data":{...,"apiToken":"xxxxxxxx-xxxx-..."}}`.

#### Étape 2 — Reporter le token dans RUDI

```bash
sed -i "s/^DATAVERSE_API_TOKEN=.*/DATAVERSE_API_TOKEN=<token>/" .env
set -a; source .env; set +a
./scripts/prepare-properties.sh
```

#### Étape 3 — Charger le bloc de métadonnées `rudi`

Le fichier est récupéré dans rudi-portal, au tag correspondant à `rudi_version` :

```bash
curl -fsSL "https://raw.githubusercontent.com/rudi-platform/rudi-portal/${rudi_version}/rudi-facet/rudi-facet-kaccess/src/main/resources/metadata/rudi.tsv" \
  | dv -X POST -H "Content-type: text/tab-separated-values" --data-binary @- \
      http://localhost:8080/api/admin/datasetfield/load

# Vérifier
dv http://localhost:8080/api/metadatablocks/rudi | head -c 200
```

#### Étape 4 — Créer les collections RUDI

La collection racine doit être publiée en premier : Dataverse refuse de publier
une collection dont la collection parente ne l'est pas. Ensuite, pour chaque
collection : création sous la racine, association des blocs `citation` et
`rudi`, publication.

```bash
dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
  http://localhost:8080/api/dataverses/:root/actions/:publish

for entry in "rudi_data:RUDI Data" "rudi_archive:RUDI Archive" "rudi_media_data:RUDI Media"; do
  alias=${entry%%:*}; name=${entry#*:}

  dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" -H "Content-type: application/json" \
    http://localhost:8080/api/dataverses/:root \
    -d "{\"alias\":\"$alias\",\"name\":\"$name\",\"dataverseType\":\"UNCATEGORIZED\",\"dataverseContacts\":[{\"contactEmail\":\"$LETSENCRYPT_EMAIL\"}]}"

  dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" -H "Content-type: application/json" \
    http://localhost:8080/api/dataverses/$alias/metadatablocks -d '["citation","rudi"]'

  dv -X POST -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
    http://localhost:8080/api/dataverses/$alias/actions/:publish
done
```

---

## Compte administrateur Dataverse

Interface : `https://dataverse.<domaine>`, compte `dataverseAdmin`, mot de passe
`DATAVERSE_ADMIN_PASSWORD` (dans `.env`).

---

## Vérifier l'intégration RUDI ↔ Dataverse

```bash
# Dataverse joignable depuis kalim
docker exec rudiplatform-kalim-1 curl -s http://dataverse:8080/api/info/version

# Token configuré dans kalim
grep "dataverse.api" config/kalim/kalim.properties

# Collections présentes
dv -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" http://localhost:8080/api/dataverses/rudi_data
```

---

## Volumes et persistance

| Chemin hôte | Chemin conteneur | Contenu |
|-------------|------------------|---------|
| `database-data/dataverse/` | `/var/lib/postgresql/data` | Base PostgreSQL Dataverse |
| `data/solr/solr-data/` | `/var/solr` | Core et index Solr (UID 8983) |
| `config/solr/collection1/` | `/template` (lecture seule) | Schéma Solr RUDI, copié à la création du core |
| `data/dataverse/dataverse-files/` | `/data` | Fichiers Dataverse (médias du portail) |

Le schéma n'est copié qu'à la **première** création du core. Pour appliquer une
modification de `config/solr/collection1/conf/` sur une instance existante,
copier les fichiers dans `data/solr/solr-data/data/collection1/conf/`, redémarrer
Solr puis réindexer :

```bash
docker compose -f docker-compose-dataverse.yml --profile dataverse restart solr
dv http://localhost:8080/api/admin/index/clear
dv http://localhost:8080/api/admin/index
```

---

## Montée de version

Modifier `dataverse_version` dans `.env`, puis :

```bash
docker compose -f docker-compose-dataverse.yml --profile dataverse pull
docker compose -f docker-compose-dataverse.yml -f docker-compose-network.yml \
  --profile dataverse up -d
```

Consulter les notes de version Dataverse et les
[changelogs RUDI](../changelogs/) : une montée de version peut nécessiter une
mise à jour du schéma Solr ou du bloc `rudi`.
