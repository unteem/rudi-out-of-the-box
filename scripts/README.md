# Scripts de déploiement RUDI

Scripts d'automatisation pour le déploiement et la gestion de la plateforme RUDI.

Pour le guide de déploiement complet, voir [documentation/cookbook/roob-to-prod.md](../documentation/cookbook/roob-to-prod.md).

---

## `check-prerequisites.sh`

Vérifie que tous les outils nécessaires sont installés avant le déploiement.

```bash
./scripts/check-prerequisites.sh
```

Vérifie : Docker, Docker Compose, Git, OpenSSL, `keytool` (JDK Java). Indique ce qui manque avec les commandes d'installation.

---

## `deploy.sh`

Déploiement automatisé complet, avec des bases de données vides. Correspond aux
étapes 3 à 12 de l'Option B de [roob-to-prod.md](../documentation/cookbook/roob-to-prod.md).

```bash
./scripts/deploy.sh
```

Étapes exécutées :
1. Vérification des prérequis et chargement de `.env`
2. Création des répertoires et permissions
3. Génération des secrets (`generate-passwords.sh`)
4. Génération des keystores (`generate-ssl-keystores.sh`)
5. Préparation des fichiers de config (`prepare-database-init.sh`, `prepare-properties.sh`)
6. Création de `traefik/acme.json` et du réseau Docker `traefik`
7. Démarrage des bases, puis de Dataverse, Solr et Magnolia
8. Initialisation de Dataverse (`init-dataverse.sh`) et regénération des propriétés
9. Démarrage du portail RUDI
10. Application des secrets OAuth2 des microservices (`config/acl/03-oauth-secrets.sql`)
11. Vérification de l'accessibilité des services

Pour charger des données de test, utiliser `import-data.sh` après le démarrage.

---

## `import-data.sh`

Charge des données de démonstration dans les bases de données d'une plateforme **déjà démarrée**.

```bash
./scripts/import-data.sh              # interactif — demande base par base
./scripts/import-data.sh --all        # tout importer
./scripts/import-data.sh --rudi       # portail RUDI (~318 Mo)
./scripts/import-data.sh --dataverse  # collections Dataverse (~67 Mo)
./scripts/import-data.sh --magnolia   # contenu CMS Magnolia (~2 Mo)
```

À utiliser uniquement après que `deploy.sh` s'est terminé avec succès. Les fichiers de données (`dummy-data/`) doivent être présents dans le répertoire — ils sont stockés séparément du dépôt (stockage externe, ex. S3).

> **Attention** : écrase les données existantes dans les bases concernées. À n'utiliser que sur un déploiement vierge ou un environnement de test dédié.

---

## `generate-passwords.sh`

Génère des mots de passe aléatoires cryptographiquement sûrs pour tous les composants de la plateforme.

```bash
./scripts/generate-passwords.sh
```

Ajoute les secrets générés à la fin de `.env` :
- Mots de passe des bases de données : `DB_RUDI`, `DB_DATAVERSE`, `DB_MAGNOLIA`, `DB_ACL`, `DB_KALIM`…
- Secrets OAuth2 des microservices : `MS_ACL`, `MS_KALIM`…
- Mots de passe des keystores : `KEYSTORE_PASSWORD`, `CONSENT_KEYSTORE_PASSWORD`, `SELFDATA_KEYSTORE_PASSWORD`, `APIGATEWAY_KEYSTORE_PASSWORD`, `JWT_KEYSTORE_PASSWORD`
- Credentials applicatifs : `EUREKA_PASSWORD`, `DATAVERSE_ADMIN_PASSWORD`, mots de passe admin, salts de hachage
- `DATAVERSE_API_TOKEN`, vide, renseigné ensuite par `init-dataverse.sh`

Relancer le script remplace tout le bloc de secrets : à ne faire que sur un
déploiement vierge.

`.env` contient désormais tous les secrets. Le sauvegarder de manière sécurisée :

```bash
gpg -c .env
```

---

## `generate-ssl-keystores.sh`

Génère les keystores PKCS12 des microservices.

```bash
./scripts/generate-ssl-keystores.sh
```

Prérequis : `.env` avec les secrets générés. Les certificats sont lus dans
`certs/fullchain.pem` et `certs/privkey.pem` ; en leur absence, un certificat
auto-signé (10 ans) est généré. Il ne sert qu'au HTTPS interne entre
microservices, Traefik gère le TLS public.

Produit (mode `600`) :

| Fichier | Alias | Usage | Régénéré à chaque exécution |
|---------|-------|-------|-----------------------------|
| `config/<service>/rudi-https-certificate.jks` | `rudi-https` | HTTPS interne | oui |
| `config/acl/rudi-jwt.jks` | `rudi-jwt` | Signature des tokens JWT | non |
| `config/konsent/rudi-consent.jks` | `rudi-consent` | Signature des consentements | non |
| `config/selfdata/rudi-selfdata.jks` | `rudi-selfdata` | Chiffrement des données personnelles | non |
| `config/apigateway/rudi-apigateway.jks` | `defaultkey` | Chiffrement des clés d'accès aux médias | non |

Les keystores applicatifs existants ne sont jamais écrasés : les régénérer
rendrait illisibles les données déjà chiffrées ou signées. Pour forcer leur
régénération, supprimer le fichier concerné.

---

## `prepare-database-init.sh`

Traite avec `envsubst` :
- `config/rudi-init/01-usr.sql.template` → `01-usr.sql` : utilisateurs et schémas PostgreSQL, créés au premier démarrage du conteneur `database`
- `config/acl/03-oauth-secrets.sql.template` → `03-oauth-secrets.sql` : secrets OAuth2 des microservices, appliqués après les migrations Flyway d'ACL

```bash
./scripts/prepare-database-init.sh
```

Doit être exécuté avant le premier démarrage du conteneur `database`.

---

## `prepare-properties.sh`

Traite les fichiers `config/<service>/<service>.properties.template` avec `envsubst` et produit les fichiers `.properties` finaux consommés par les microservices.

```bash
./scripts/prepare-properties.sh
```

Seules les variables de déploiement issues de `.env` sont substituées. Les références internes Spring Boot (ex. `${server.ssl.key-store-password}`) sont préservées.

---

## `init-dataverse.sh`

Initialise Dataverse pour RUDI sur un déploiement vierge. Idempotent.

```bash
./scripts/init-dataverse.sh
./scripts/prepare-properties.sh   # reporte le token dans les propriétés

# Options
./scripts/init-dataverse.sh --email contact@mondomaine.fr   # défaut : LETSENCRYPT_EMAIL
./scripts/init-dataverse.sh --version v3.3.13               # tag rudi-portal pour rudi.tsv
```

Le script, Dataverse étant démarré :
1. Bootstrap via `gdcc/configbaker` : blocs de métadonnées, rôles, utilisateur
   `dataverseAdmin` (mot de passe `DATAVERSE_ADMIN_PASSWORD`), collection racine, licences
2. Écrit le token API de `dataverseAdmin` dans `.env` (`DATAVERSE_API_TOKEN`)
3. Charge le bloc de métadonnées `rudi` (`rudi.tsv` du dépôt rudi-portal)
4. Crée et publie les collections `rudi_data`, `rudi_archive`, `rudi_media_data`

Voir [configuration-dataverse.md](../documentation/cookbook/configuration-dataverse.md).

---

## `init-kos.sh`

Initialise les vocabulaires KOS (thèmes et licences) via l'API REST.

```bash
./scripts/init-kos.sh --login admin@example.com --password MonMotDePasse

# Ou via variables d'environnement
KOS_ADMIN_LOGIN=admin@example.com KOS_ADMIN_PASSWORD=MonMotDePasse \
  ./scripts/init-kos.sh

# Spécifier un tag différent (défaut : rudi_version dans .env)
./scripts/init-kos.sh --login admin@example.com --password MonMotDePasse \
  --version v3.4.1
```

À exécuter **une seule fois** après le premier démarrage des services. KOS ne seed
pas ses données automatiquement — sans cette étape, les tuiles thématiques et les
licences n'apparaissent pas dans le portail.

Le script :
1. Télécharge `scheme-keyword.json` et `scheme-licence.json` depuis GitHub
   (tag correspondant à `rudi_version` dans `.env`)
2. S'authentifie avec le compte fourni pour obtenir un token JWT
3. Importe les deux schèmes via `POST /kos/v1/skosSchemes`
4. Vérifie que les schèmes n'existent pas déjà (idempotent)

---

## `init-projekt.sh`

Synchronise les listes de référence du formulaire de réutilisation (type de
réutilisation, échelle, public cible, accompagnement souhaité) avec l'API projekt.

```bash
# Valeurs lues dans config/projekt/referentiels.json, sinon dans
# config/projekt/referentiels.example.json
./scripts/init-projekt.sh --login admin@example.com --password MonMotDePasse

# Afficher les changements sans les appliquer
./scripts/init-projekt.sh --login admin@example.com --password MonMotDePasse --dry-run

# Autre fichier
./scripts/init-projekt.sh --login admin@example.com --password MonMotDePasse \
  --file /chemin/referentiels.json
```

Les entrées sont comparées par `code` : création si absente, mise à jour du
libellé, de l'ordre ou de l'état (`"closed": true`) sinon. Rien n'est supprimé ;
les valeurs présentes sur le portail mais absentes du fichier sont signalées.
Le script peut être relancé après chaque modification du fichier.

---

## `deploy-producer.sh`

Déclare un nœud producteur dans le portail RUDI via l'API (Strukture + ACL).

```bash
./scripts/deploy-producer.sh \
  --domain producteur.mondomaine.fr \
  --login admin@mondomaine.fr \
  --password MonMotDePasse

# Avec un label personnalisé pour le fournisseur
./scripts/deploy-producer.sh \
  --domain producteur.mondomaine.fr \
  --login admin@mondomaine.fr \
  --password MonMotDePasse \
  --label "Mon Organisation Productrice"
```

Le script effectue via l'API :
1. Authentification avec le compte administrateur
2. Création du fournisseur (`POST /strukture/v1/providers`)
3. Déclaration du nœud (`POST /strukture/v1/providers/{uuid}/nodes`)
4. Création de l'utilisateur ROBOT (`POST /acl/v1/users`) avec le rôle `PROVIDER`
5. Écriture de `PRODUCER_DOMAIN`, `PRODUCER_PROVIDER_UUID`, `PRODUCER_NODE_UUID`, `PRODUCER_PASSWORD`, `PRODUCER_PASSWORD_B64` dans `.env`

Voir [documentation/cookbook/configuration-producer-node.md](../documentation/cookbook/configuration-producer-node.md) pour le détail des API.

Démarrer le nœud après exécution du script :

```bash
docker compose -f docker-compose-producer.yml up -d
```

---

## `update-configs.sh`

Ré-applique les mots de passe depuis `.env` après une rotation, en créant d'abord une sauvegarde horodatée de `config/`.

```bash
./scripts/update-configs.sh
```

---

## Variables d'environnement

### `.env`

Copié depuis `.env.example` par l'utilisateur, puis complété par `generate-passwords.sh`.
**Fichier sensible — ne pas committer.**

```bash
# Renseigné par l'utilisateur (depuis .env.example)
base_dn=mondomaine.fr
rudi_version=v3.3.13
dataverse_version=6.9-noble
LETSENCRYPT_EMAIL=admin@...

# Ajouté automatiquement par generate-passwords.sh
DB_RUDI=...
DB_DATAVERSE=...
DB_MAGNOLIA=...
DB_ACL=...
# ...
MS_ACL=...
MS_KALIM=...
# ...
KEYSTORE_PASSWORD=...
JWT_KEYSTORE_PASSWORD=...
EUREKA_PASSWORD=...
DATAVERSE_ADMIN_PASSWORD=...
DATAVERSE_API_TOKEN=...      # renseigné par init-dataverse.sh
# ...

# Ajouté par deploy-producer.sh
PRODUCER_DOMAIN=...
PRODUCER_PROVIDER_UUID=...
PRODUCER_NODE_UUID=...      # login du compte ROBOT
PRODUCER_PASSWORD=...
PRODUCER_PASSWORD_B64=...
```

### Variables optionnelles pour les certificats SSL

```bash
CERT_DIR=/chemin/vers/certs     # Par défaut : ./certs
CERT_FILE=/chemin/vers/cert.pem # Par défaut : $CERT_DIR/fullchain.pem
KEY_FILE=/chemin/vers/key.pem   # Par défaut : $CERT_DIR/privkey.pem
```

---

## Fichiers produits par les scripts

```
rudi-out-of-the-box/
├── .env                                        # Config utilisateur + secrets générés (SENSIBLE)
├── traefik/
│   └── acme.json                              # Stockage certificats Let's Encrypt (SENSIBLE)
├── certs/
│   ├── fullchain.pem                          # Certificat SSL
│   └── privkey.pem                            # Clé privée SSL (SENSIBLE)
├── config/
│   ├── <service>/
│   │   ├── rudi-https-certificate.jks         # Keystore HTTPS interne (SENSIBLE)
│   │   └── <service>.properties               # Généré depuis le template
│   ├── acl/rudi-jwt.jks                       # Signature JWT (SENSIBLE)
│   ├── acl/03-oauth-secrets.sql               # Généré depuis le template
│   ├── konsent/rudi-consent.jks               # (SENSIBLE)
│   ├── selfdata/rudi-selfdata.jks             # (SENSIBLE)
│   ├── apigateway/rudi-apigateway.jks         # (SENSIBLE)
│   ├── rudi-init/01-usr.sql                   # Généré depuis le template
│   ├── projekt/referentiels.json              # Listes de référence personnalisées (copie de l'exemple)
│   └── magnolia/default/
│       └── magnolia-activation-keypair.properties  # Écrit par Magnolia au premier démarrage (SENSIBLE)
```

Tous les fichiers sensibles sont exclus de git par `.gitignore`.

---

## Dépannage

**Permission refusée sur un script**
```bash
chmod +x scripts/*.sh
```

**Docker introuvable**
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker
```

**`keytool` introuvable**
```bash
sudo apt install openjdk-17-jdk
```

**`.env` introuvable ou sans secrets**
```bash
./scripts/generate-passwords.sh
```

**Services qui ne démarrent pas**
```bash
docker compose -f docker-compose-magnolia.yml -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml -f docker-compose-network.yml \
               --profile "*" logs -f
```

**Traefik ne délivre pas de certificats TLS**
- Vérifier que `traefik/acme.json` a les permissions `600`
- Vérifier que `LETSENCRYPT_EMAIL` est renseigné dans `.env`
- Consulter les logs : `docker compose -f docker-compose-network.yml logs reverse-proxy`

Pour les autres problèmes, voir [TROUBLESHOOTING.md](../TROUBLESHOOTING.md).
