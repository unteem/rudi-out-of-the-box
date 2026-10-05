# Comment déployer RUDI Out-of-the-Box en production ?

_Cas d'usage_ : je veux déployer la plateforme RUDI sur un serveur de production
avec un nœud producteur, en remplaçant les configurations de démonstration par des
secrets générés de manière sécurisée.

Deux chemins équivalents :

- **Option A** : déploiement automatisé avec `scripts/deploy.sh`
- **Option B** : les mêmes opérations, étape par étape

Le déploiement part de bases vides. Les données de démonstration sont une
[étape optionnelle](#données-de-démonstration-optionnel).

---

## Prérequis

### Serveur

- Linux (Ubuntu 22.04 LTS ou Debian 12+)
- 8 cœurs CPU (16 recommandés), 32 Go de RAM (64 Go recommandés), 500 Go SSD
- Docker Engine + plugin Docker Compose
- Git, OpenSSL, JDK Java (pour `keytool`), Python 3, curl

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
sudo usermod -aG docker $USER && newgrp docker
sudo apt install docker-compose-plugin git openssl openjdk-17-jdk python3 curl
keytool -version
```

### DNS

Configurer les entrées DNS **avant de démarrer les services** : Traefik demande
les certificats Let's Encrypt au premier démarrage (challenge HTTP-01).

| Nom d'hôte | Usage |
|------------|-------|
| `rudi.<domaine>` | Portail et API des microservices |
| `dataverse.<domaine>` | Dataverse |
| `magnolia.<domaine>` | CMS Magnolia |
| `producteur.<domaine>` | Nœud producteur |

---

## Option A — Déploiement automatisé

### 1. Cloner le dépôt et configurer `.env`

```bash
git clone https://github.com/rudi-platform/rudi-out-of-the-box.git
cd rudi-out-of-the-box
cp .env.example .env
# Éditer .env : base_dn, rudi_version, dataverse_version, LETSENCRYPT_EMAIL
```

### 2. Lancer le déploiement

```bash
./scripts/deploy.sh
```

Le script enchaîne les étapes 3 à 12 de l'Option B : répertoires, secrets,
keystores, fichiers de configuration, Traefik, bases de données, Dataverse et
Magnolia, initialisation de Dataverse, portail RUDI, secrets OAuth2.

### 3. Terminer la configuration

Ces étapes nécessitent une intervention et sont identiques à l'Option B :

1. [Configurer Magnolia](#étape-13--configurer-magnolia)
2. [Créer le premier administrateur RUDI](#étape-14--créer-le-premier-administrateur-rudi)
3. [Initialiser les vocabulaires KOS](#étape-15--initialiser-les-vocabulaires-kos)
4. [Définir les listes de référence des réutilisations](#étape-16--définir-les-listes-de-référence-des-réutilisations)
5. [Déployer le nœud producteur](#étape-17--déployer-le-nœud-producteur)
6. [Vérifier la chaîne de publication](#étape-18--vérifier-la-chaîne-de-publication)

---

## Option B — Déploiement étape par étape

> Docker Compose charge `.env` automatiquement. Dans le shell, charger les
> variables avec `set -a; source .env; set +a` avant les commandes qui les
> utilisent.

### Étape 1 — Cloner le dépôt

```bash
git clone https://github.com/rudi-platform/rudi-out-of-the-box.git
cd rudi-out-of-the-box
```

### Étape 2 — Configurer `.env`

```bash
cp .env.example .env
```

Renseigner :

```
base_dn=mondomaine.fr
rudi_version=v3.3.13
dataverse_version=6.9-noble
LETSENCRYPT_EMAIL=admin@mondomaine.fr
```

### Étape 3 — Créer les répertoires

```bash
mkdir -p data/{rudi,dataverse,magnolia,producer} data/solr/solr-data
mkdir -p database-data/{rudi,dataverse,magnolia} traefik logs
sudo chown -R 8983:8983 data/solr       # Solr tourne avec l'UID 8983
sudo chown -R 5001:5001 data/producer   # rudinode tourne avec l'UID 5001
```

### Étape 4 — Générer les secrets

```bash
./scripts/generate-passwords.sh
```

Ajoute un bloc « Generated secrets » à la fin de `.env` : mots de passe des
bases, secrets OAuth2 des microservices, mots de passe des keystores, mot de
passe `dataverseAdmin`. **Sauvegarder `.env` de manière sécurisée** (par exemple
`gpg -c .env`).

### Étape 5 — Générer les keystores

```bash
./scripts/generate-ssl-keystores.sh
```

| Keystore | Usage |
|----------|-------|
| `config/<service>/rudi-https-certificate.jks` | HTTPS interne entre microservices |
| `config/acl/rudi-jwt.jks` | Signature des tokens JWT ([détails](./configuration-acl-jwt.md)) |
| `config/konsent/rudi-consent.jks` | Signature des consentements |
| `config/selfdata/rudi-selfdata.jks` | Chiffrement des données personnelles |
| `config/apigateway/rudi-apigateway.jks` | Chiffrement des clés d'accès aux médias |

Un certificat auto-signé est créé si `certs/` est vide : il ne sert qu'au HTTPS
interne, Traefik gère le TLS public. Les keystores applicatifs existants ne sont
jamais écrasés : les régénérer rendrait illisibles les données déjà chiffrées.

### Étape 6 — Préparer les fichiers de configuration

```bash
./scripts/prepare-database-init.sh
./scripts/prepare-properties.sh
```

Génère `config/rudi-init/01-usr.sql`, `config/acl/03-oauth-secrets.sql` et
`config/<service>/<service>.properties` à partir des `.template` et de `.env`.

### Étape 7 — Préparer Traefik et le réseau Docker

```bash
touch traefik/acme.json && chmod 600 traefik/acme.json
docker network create traefik
```

### Étape 8 — Démarrer les bases de données

```bash
COMPOSE_ALL="-f docker-compose-magnolia.yml -f docker-compose-rudi.yml -f docker-compose-dataverse.yml -f docker-compose-network.yml"

docker compose $COMPOSE_ALL up -d database dataverse-database magnolia-database
sleep 60
```

> `docker-compose-network.yml` porte le routage Traefik : sans lui, les
> services ne sont pas joignables depuis l'extérieur.

### Étape 9 — Démarrer Dataverse, Solr et Magnolia

Dataverse doit être initialisé **avant** le portail RUDI, dont les
microservices ont besoin du token API Dataverse.

```bash
docker compose $COMPOSE_ALL --profile dataverse --profile magnolia up -d
```

Dataverse met 3 à 5 minutes à démarrer.

### Étape 10 — Initialiser Dataverse

```bash
./scripts/init-dataverse.sh
./scripts/prepare-properties.sh
```

Bootstrap, token API écrit dans `.env`, bloc de métadonnées `rudi`, collections
`rudi_data`, `rudi_archive` et `rudi_media_data`. Le détail des commandes
équivalentes est dans
[Comment configurer Dataverse et Solr ?](./configuration-dataverse.md).

### Étape 11 — Démarrer le portail RUDI

```bash
docker compose $COMPOSE_ALL --profile "*" up -d
```

Tant que l'étape 12 n'est pas faite, les microservices ne peuvent pas obtenir de
token auprès d'ACL : des erreurs `[invalid_client]` dans les logs (kalim, par
exemple) sont normales à ce stade.

### Étape 12 — Appliquer les secrets OAuth2 des microservices

Les migrations Flyway d'ACL créent les comptes des microservices avec un mot de
passe par défaut. On les remplace par les secrets `MS_*` de `.env` une fois
Flyway terminé :

```bash
until docker exec rudiplatform-database-1 psql -U rudi -d rudi \
  -c "SELECT 1 FROM acl_data.user_ WHERE login='kalim';" &>/dev/null; do
  echo "Attente de Flyway..."; sleep 10
done

docker exec -i rudiplatform-database-1 psql -U rudi -d rudi \
  < config/acl/03-oauth-secrets.sql

docker compose -f docker-compose-rudi.yml restart \
  acl kalim strukture konsult kos projekt selfdata konsent apigateway
```

### Étape 13 — Configurer Magnolia

Connexion initiale (`superuser` / `superuser`), changement de mot de passe,
configuration de l'URL du portail : voir
[Comment configurer Magnolia CMS ?](./configuration-magnolia.md).

La paire de clés d'activation de Magnolia est générée dans
`config/magnolia/default/magnolia-activation-keypair.properties` (répertoire
monté dans le conteneur). Elle contient une clé privée : la sauvegarder.

### Étape 14 — Créer le premier administrateur RUDI

```bash
docker exec -it rudiplatform-database-1 psql -U rudi -d rudi
```

```sql
INSERT INTO acl_data.user_ (uuid, company, firstname, lastname, login, password, type)
VALUES (
  gen_random_uuid(),
  'monorganisation',
  'Prénom',
  'Nom',
  'admin@mondomaine.fr',
  crypt('MotDePasseSecurise123!', gen_salt('bf')),
  'PERSON'
);

INSERT INTO acl_data.user_role (user_fk, role_fk)
SELECT u.id, r.id
FROM acl_data.user_ u, acl_data.role r
WHERE u.login = 'admin@mondomaine.fr'
  AND r.code = 'ADMINISTRATOR';
```

L'extension `pgcrypto` (fonctions `crypt` et `gen_salt`) est installée par
`config/rudi-init/02-extension.sql`.

### Étape 15 — Initialiser les vocabulaires KOS

```bash
./scripts/init-kos.sh --login admin@mondomaine.fr --password 'MotDePasseSecurise123!'
```

Sans les thèmes et licences, le portail n'affiche pas les tuiles thématiques et
kalim rejette les métadonnées. Voir
[Comment initialiser les vocabulaires KOS ?](./configuration-kos.md).

### Étape 16 — Définir les listes de référence des réutilisations

Le formulaire de déclaration d'une réutilisation propose quatre listes
déroulantes que le portail ne pré-remplit pas (ou presque) : type de
réutilisation, échelle, public cible et accompagnement souhaité. Le front
n'offre pas d'écran pour les gérer : leurs valeurs sont définies dans un
fichier JSON, puis envoyées à l'API projekt.

```bash
# 1. Adapter les valeurs (facultatif : sans ce fichier, l'exemple est utilisé)
cp config/projekt/referentiels.example.json config/projekt/referentiels.json
vi config/projekt/referentiels.json

# 2. Prévisualiser puis appliquer
./scripts/init-projekt.sh --login admin@mondomaine.fr --password 'MotDePasseSecurise123!' --dry-run
./scripts/init-projekt.sh --login admin@mondomaine.fr --password 'MotDePasseSecurise123!'
```

Chaque entrée a un `code` (identifiant stable, 30 caractères maximum), un
`label` (texte affiché) et un `order` (position dans la liste) :

```json
{
  "types": [
    { "code": "traitement", "label": "Traitement de données", "order": 1 },
    { "code": "application", "label": "Application", "order": 2 }
  ],
  "territorial_scales": [ ... ],
  "target_audiences": [ ... ],
  "supports": [ ... ]
}
```

Le script compare le fichier au portail par `code` : il crée les entrées
absentes et met à jour celles dont le libellé ou l'ordre a changé. Il ne
supprime rien, car des réutilisations peuvent déjà utiliser une valeur. Pour
retirer un choix du formulaire, ajouter `"closed": true` à l'entrée. Pour
modifier les listes plus tard, éditer le fichier et relancer le script.

<details>
<summary>Équivalent manuel (API projekt)</summary>

```bash
TOKEN=$(curl -s -X POST "https://rudi.$base_dn/authenticate" \
  --data-urlencode "login=admin@mondomaine.fr" \
  --data-urlencode 'password=MotDePasseSecurise123!' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['jwtToken'].replace('Bearer ',''))")
API="https://rudi.$base_dn/projekt/v1"

# Lister les valeurs existantes (ressources : types, territorial-scales,
# target-audience, supports)
curl -s -H "Authorization: Bearer $TOKEN" "$API/types?limit=1000"

# Ajouter une valeur
curl -s -X POST "$API/types" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code": "application", "label": "Application", "order": 2, "opening_date": "2026-01-01T00:00:00"}'

# Modifier ou fermer une valeur : renvoyer l'objet complet avec son uuid
# (PUT $API/<ressource>/<uuid>, sauf target-audience : PUT $API/target-audience)
# en changeant label, order ou closing_date.
```

</details>

### Étape 17 — Déployer le nœud producteur

Le nœud est d'abord déclaré dans le portail (fournisseur, nœud, compte ROBOT),
puis démarré avec les identifiants obtenus. Détail et équivalent manuel :
[Comment déployer et déclarer un nœud producteur RUDI ?](./configuration-producer-node.md).

```bash
# 1. Déclarer le nœud (écrit PRODUCER_* dans .env)
./scripts/deploy-producer.sh \
  --domain producteur.mondomaine.fr \
  --login admin@mondomaine.fr \
  --password 'MotDePasseSecurise123!' \
  --label "Mon Organisation Productrice"

# 2. Démarrer le nœud
docker compose -f docker-compose-producer.yml up -d

# 3. Remplacer le super-administrateur par défaut du manager
SU=$(curl -s --json '{"usr": "admin", "pwd": "MotDePasseManager!"}' \
  https://producteur.mondomaine.fr/manager/api/open/hash-credentials)
echo "SU=$SU" > config/producer/manager.env
docker compose -f docker-compose-producer.yml up -d producer-manager
```

Le manager est accessible sur `https://producteur.mondomaine.fr/manager/`.

### Étape 18 — Vérifier la chaîne de publication

Publier un premier jeu de données de test depuis le nœud producteur et vérifier
qu'il apparaît sur le portail : voir
[Comment une donnée est-elle publiée sur le portail RUDI ?](./cycle-de-vie-donnees.md#publier-un-premier-jeu-de-données-de-test).

---

## Données de démonstration (optionnel)

Les données de démonstration sont stockées hors du dépôt. Structure attendue :

```
dummy-data/
├── rudi/           # dump PostgreSQL RUDI + scripts d'import
├── dataverse/      # dump PostgreSQL Dataverse + fichiers des datasets
└── magnolia/       # dump PostgreSQL Magnolia + datastore JCR
```

Placer ce dossier à la racine du dépôt, puis :

```bash
./scripts/import-data.sh --all        # tout importer
./scripts/import-data.sh --rudi       # portail RUDI
./scripts/import-data.sh --dataverse  # Dataverse
./scripts/import-data.sh --magnolia   # Magnolia
```

> **Attention** : écrase les données existantes. À réserver à un déploiement
> vierge ou à un environnement de test.

---

## Persistance et sauvegardes

| Donnée | Emplacement |
|--------|-------------|
| Bases PostgreSQL | `database-data/{rudi,dataverse,magnolia}` |
| Index Solr | `data/solr/solr-data` |
| Contenu Magnolia (JCR) | `data/magnolia/repository` |
| Secrets | `.env` |
| Keystores | `config/*/*.jks` |
| Clé d'activation Magnolia | `config/magnolia/default/magnolia-activation-keypair.properties` |

Les données survivent aux `docker compose down`. Voir aussi
[Comment faire persister mes données ?](./data-persistence.md).

```bash
docker exec rudiplatform-database-1 pg_dump -U rudi rudi \
  | gzip > /backups/rudi-$(date +%Y%m%d).sql.gz
docker exec rudiplatform-dataverse-database-1 pg_dump -U dataverse dataverse \
  | gzip > /backups/dataverse-$(date +%Y%m%d).sql.gz
docker exec rudiplatform-magnolia-database-1 pg_dump -U magnolia magnolia \
  | gzip > /backups/magnolia-$(date +%Y%m%d).sql.gz

tar czf /backups/secrets-$(date +%Y%m%d).tar.gz \
  .env config/*/*.jks \
  config/magnolia/default/magnolia-activation-keypair.properties
```

---

## Pour aller plus loin

- [Architecture, routage et checklist de sécurité](../../PRODUCTION-DEPLOYMENT.md)
- [Référence des scripts](../../scripts/README.md)
- [Dépannage](../../TROUBLESHOOTING.md)
- [Configuration SMTP](./configuration-mail.md)
- [Mettre en place un SSO](./configuration-sso.md)
- [Certificats SSL Traefik](./treafik-certificat-ssl.md)
- [Remplacer Traefik par Apache](./treafik-to-apache.md)
- [Logs](./configuration-logs.md)
