# Plateforme RUDI — Référence de déploiement en production

Ce document décrit l'architecture du déploiement : fichiers Compose, services,
routage, secrets, keystores. Pour le reste :

- procédure pas à pas : [documentation/cookbook/roob-to-prod.md](./documentation/cookbook/roob-to-prod.md) ;
- référence des scripts : [scripts/README.md](./scripts/README.md) ;
- guides thématiques : liste des cookbooks dans le [README](./README.md#déploiement-en-production-) ;
- dépannage : [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

Version de la plateforme : `rudi_version=v3.3.13` (dans `.env`).

---

## Architecture

Le portail RUDI ne stocke pas les fichiers de données. Les jeux de données
restent sur les nœuds producteurs. Le portail moissonne leurs métadonnées
(kalim), puis les indexe dans Dataverse et Solr. Les téléchargements passent
par l'apigateway. Le cycle complet est décrit dans
[Comment une donnée est-elle publiée sur le portail RUDI ?](./documentation/cookbook/cycle-de-vie-donnees.md).

### Fichiers Compose

Tous les fichiers partagent le nom de projet `rudiplatform`.

| Fichier | Profil | Contenu |
|---------|--------|---------|
| `docker-compose-rudi.yml` | `portail` | Portail RUDI, microservices et base PostgreSQL/PostGIS |
| `docker-compose-dataverse.yml` | `dataverse` | Dataverse, Solr, base PostgreSQL Dataverse |
| `docker-compose-magnolia.yml` | `magnolia` | Magnolia CMS et sa base PostgreSQL |
| `docker-compose-network.yml` | — | Traefik (reverse proxy, Let's Encrypt) et labels de routage |
| `docker-compose-mailhog.yml` | `portail` | MailHog (capture des e-mails, à remplacer par un SMTP en production) |
| `docker-compose-producer.yml` | — | Nœud producteur (rudinode + MongoDB) |

`docker-compose-network.yml` utilise un réseau externe `traefik`.

### Services du portail (`docker-compose-rudi.yml`)

Les microservices utilisent l'image `rudiplatform/rudi-microservice-<nom>:${rudi_version}`.
Ils écoutent en HTTPS sur le port 8443 (certificat interne).

| Service | Rôle |
|---------|------|
| `database` | PostgreSQL/PostGIS (`postgis/postgis:15-master`), base RUDI partagée |
| `registry` | Annuaire de services Eureka |
| `gateway` | Spring Cloud Gateway |
| `acl` | Authentification, autorisation, émission des JWT |
| `apigateway` | Accès aux données et aux médias des nœuds producteurs |
| `strukture` | Organisations et nœuds producteurs |
| `kalim` | Moissonnage des métadonnées des nœuds |
| `konsult` | Consultation du catalogue |
| `kos` | Vocabulaires SKOS (thèmes, licences) |
| `konsent` | Gestion des consentements |
| `projekt` | Projets et réutilisations |
| `selfdata` | Données personnelles (selfdata) |
| `portail` | Front-office (`rudiplatform/rudi-application-front-office`) |

### Dataverse (`docker-compose-dataverse.yml`)

| Service | Image | Remarques |
|---------|-------|-----------|
| `dataverse` | `gdcc/dataverse:${dataverse_version}` (6.9) | Image officielle |
| `solr` | `solr:9.8.0` | Core `collection1` créé par `solr-precreate` à partir de `config/solr/collection1/` (monté en lecture seule sur `/template`) |
| `dataverse-database` | `postgres:15.12-bookworm` | Sans profil, démarré avec Dataverse |

Le schéma Solr, champs RUDI compris, est versionné dans
`config/solr/collection1/conf/`. Dataverse ne stocke que des métadonnées :
collections `rudi_data`, `rudi_archive` et `rudi_media_data`, bloc de
métadonnées `rudi`. Les fichiers de données restent sur les nœuds
producteurs.

L'initialisation se fait avec `scripts/init-dataverse.sh`. Le script :

- crée l'utilisateur `dataverseAdmin` avec `DATAVERSE_ADMIN_PASSWORD` ;
- écrit `DATAVERSE_API_TOKEN` dans `.env` ;
- charge le bloc `rudi` ;
- crée et publie les collections.

Voir [configuration-dataverse.md](./documentation/cookbook/configuration-dataverse.md).

### Magnolia (`docker-compose-magnolia.yml`)

- L'image `rudiplatform/magnolia` est construite localement depuis `image/magnolia/`. Le WAR Magnolia Community et le pilote JDBC sont téléchargés pendant le build. Le module RUDI vient de `image/magnolia/modules-rudi/`.
- `config/magnolia/` est monté dans `WEB-INF/config` du conteneur. La paire de clés d'activation est générée dans `config/magnolia/default/magnolia-activation-keypair.properties`.
- Base `magnolia-database` : `postgres:15.8`, port non publié.

Voir [configuration-magnolia.md](./documentation/cookbook/configuration-magnolia.md).

### Nœud producteur (`docker-compose-producer.yml`)

L'image `rudinode` (`rudinode_image:rudinode_version`) est lancée en quatre
conteneurs, comme dans `rudi-node-container/docker-compose.yml` :
`producer-db` (MongoDB intégré à l'image), `producer-catalog`,
`producer-storage` et `producer-manager`. Ils partagent le volume
`data/producer` (UID/GID 5001).

Traefik expose sur `https://<PRODUCER_DOMAIN>` :

- `/catalog` (et `/api`, redirigé) vers le catalog (port 3030) ;
- `/storage` vers le storage (port 3031) ;
- `/manager` (et toute autre route) vers le manager (port 3032), interface sous `/manager/`.

`scripts/deploy-producer.sh` déclare le nœud sur le portail via les API
strukture et acl. L'URL du nœud est `https://<PRODUCER_DOMAIN>/catalog/v1`. Voir
[configuration-producer-node.md](./documentation/cookbook/configuration-producer-node.md).

### Routage URL (`docker-compose-network.yml`)

Traefik écoute sur les ports 80 et 443, seuls ports publiés sur l'hôte. Son
tableau de bord n'est pas exposé (`api.insecure: false`). Les certificats publics viennent de Let's Encrypt
(`certresolver=letsencrypt`) et sont stockés dans `traefik/acme.json`.

| URL | Service |
|-----|---------|
| `https://rudi.<base_dn>/` | `portail` (priorité la plus basse) |
| `https://rudi.<base_dn>/gateway` | `gateway` |
| `https://rudi.<base_dn>/acl`, `/anonymous`, `/authenticate`, `/refresh_token`, `/check_credential`, `/oauth` | `acl` |
| `https://rudi.<base_dn>/apigateway`, `/medias/*` (réécrit en `/apigateway/datasets/*`) | `apigateway` |
| `https://rudi.<base_dn>/strukture`, `/node/*` (réécrit en `/strukture/*`) | `strukture` |
| `https://rudi.<base_dn>/kalim` | `kalim` |
| `https://rudi.<base_dn>/konsult`, `/robots.txt` (réécrit en `/konsult/v1/robots/robots`) | `konsult` |
| `https://rudi.<base_dn>/kos` | `kos` |
| `https://rudi.<base_dn>/konsent` | `konsent` |
| `https://rudi.<base_dn>/projekt` | `projekt` |
| `https://rudi.<base_dn>/selfdata` | `selfdata` |
| `https://dataverse.<base_dn>` | `dataverse` |
| `https://magnolia.<base_dn>` | `magnolia` |

Solr n'est pas exposé (`traefik.enable=false`). Il n'est joignable que par
Dataverse sur le réseau interne. Dataverse et sa base ne publient aucun port :
l'API d'administration (`/api/admin`, `/api/builtin-users`) n'est accessible
que depuis le conteneur (`dataverse_api_blocked_policy=localhost-only`).

Aucun autre service ne publie de port sur l'hôte : bases de données, registry,
microservices, MailHog et Solr ne sont joignables que sur les réseaux Docker.
Pour un accès ponctuel à une base, passer par `docker exec`, par exemple
`docker exec -it rudiplatform-database-1 psql -U rudi -d rudi`.

### Secrets et fichiers générés

Les modèles sont versionnés. Les fichiers générés sont exclus par `.gitignore`.

| Modèle (versionné) | Fichier généré (ignoré) | Généré par |
|--------------------|-------------------------|------------|
| `.env.example` | `.env` (configuration + bloc de secrets) | copie manuelle, puis `generate-passwords.sh` |
| `config/<service>/<service>.properties.template` | `config/<service>/<service>.properties` | `prepare-properties.sh` |
| `config/rudi-init/01-usr.sql.template` | `config/rudi-init/01-usr.sql` | `prepare-database-init.sh` |
| `config/acl/03-oauth-secrets.sql.template` | `config/acl/03-oauth-secrets.sql` | `prepare-database-init.sh` |
| — | `config/*/*.jks` (voir [Keystores](#keystores)) | `generate-ssl-keystores.sh` |
| — | `.keystore-info.txt` | `generate-ssl-keystores.sh` |
| — | `traefik/acme.json` (mode `600`) | `deploy.sh` |
| — | `config/magnolia/default/magnolia-activation-keypair.properties` | Magnolia, au premier démarrage |

`generate-passwords.sh` ajoute à la fin de `.env` un bloc délimité
« Generated secrets ». Le script remplace ce bloc s'il est relancé et passe
`.env` en mode `600`.

| Variables | Usage |
|-----------|-------|
| `DB_RUDI`, `DB_DATAVERSE`, `DB_MAGNOLIA`, `DB_ACL`, `DB_APIGATEWAY`, `DB_KALIM`, `DB_KONSENT`, `DB_KOS`, `DB_PROJEKT`, `DB_SELFDATA`, `DB_STRUKTURE`, `DB_TEMPLATE` | Mots de passe PostgreSQL |
| `MS_ACL`, `MS_APIGATEWAY`, `MS_KALIM`, `MS_KONSENT`, `MS_KONSULT`, `MS_KOS`, `MS_PROJEKT`, `MS_SELFDATA`, `MS_STRUKTURE` | Secrets OAuth2 des microservices (voir ci-dessous) |
| `KEYSTORE_PASSWORD`, `CONSENT_KEYSTORE_PASSWORD`, `SELFDATA_KEYSTORE_PASSWORD`, `APIGATEWAY_KEYSTORE_PASSWORD`, `JWT_KEYSTORE_PASSWORD` | Mots de passe des keystores |
| `EUREKA_USER`, `EUREKA_PASSWORD` | Accès au registre Eureka |
| `ADMIN_REGISTRY`, `ADMIN_GATEWAY`, `ADMIN_APIGATEWAY` | Comptes d'administration Spring Security |
| `DATAVERSE_ADMIN_PASSWORD` | Mot de passe de `dataverseAdmin` |
| `DATAVERSE_API_TOKEN` | Vide à la génération, renseigné par `init-dataverse.sh` |
| `CONSENT_VALIDATE_SALT`, `CONSENT_REVOKE_SALT`, `TREATMENTVERSION_PUBLISH_SALT` | Sels de hachage |

Les secrets `MS_*` alimentent le `client-secret` OAuth2 de chaque
microservice. `config/acl/03-oauth-secrets.sql` les applique ensuite à
`acl_data.user_`. Ce script doit être exécuté une fois qu'ACL a démarré et que
Flyway a créé les utilisateurs techniques.

### Keystores

Tous les keystores sont générés par `scripts/generate-ssl-keystores.sh`, au
format PKCS12 et en mode `600`.

| Keystore | Alias | Mot de passe | Usage |
|----------|-------|--------------|-------|
| `config/<service>/rudi-https-certificate.jks` | `rudi-https` | `KEYSTORE_PASSWORD` | HTTPS interne entre services et Eureka |
| `config/acl/rudi-jwt.jks` | `rudi-jwt` | `JWT_KEYSTORE_PASSWORD` | Signature des JWT par ACL |
| `config/konsent/rudi-consent.jks` | `rudi-consent` | `CONSENT_KEYSTORE_PASSWORD` | Signature des documents de consentement |
| `config/selfdata/rudi-selfdata.jks` | `rudi-selfdata` | `SELFDATA_KEYSTORE_PASSWORD` | Chiffrement des données personnelles |
| `config/apigateway/rudi-apigateway.jks` | `defaultkey` | `APIGATEWAY_KEYSTORE_PASSWORD` | Chiffrement des clés d'accès aux médias |

**Keystores HTTPS.** Ils sont créés pour `acl`, `apigateway`, `gateway`,
`kalim`, `konsent`, `kos`, `konsult`, `projekt`, `selfdata`, `strukture` et
`registry`, et régénérés à chaque exécution. La source est le certificat de
`certs/` (`fullchain.pem`, `privkey.pem`). À défaut, le script génère un
certificat auto-signé valable 10 ans. Ce certificat ne sert qu'au réseau
Docker interne ; Traefik gère le TLS public.

**Keystores applicatifs** (JWT, consent, selfdata, apigateway). Ils ne sont
jamais écrasés s'ils existent déjà. Les perdre ou les régénérer rend
illisibles les données chiffrées ou signées avec l'ancienne clé : il faut les
sauvegarder avec `.env`.

**JWT.** Depuis RUDI v3.3.9, ACL est le seul émetteur de JWT. Il les signe
avec `config/acl/rudi-jwt.jks`, configuré dans `acl.properties` :
`security.jwt.keystore`, `security.jwt.keystore.password` et
`security.jwt.keystore.alias`. Les autres microservices n'ont besoin d'aucune
clé. Sans ce keystore, ACL génère une clé aléatoire à chaque démarrage et
invalide tous les jetons. Voir
[configuration-acl-jwt.md](./documentation/cookbook/configuration-acl-jwt.md).

### Persistance

| Donnée | Emplacement |
|--------|-------------|
| Bases PostgreSQL | `database-data/{rudi,dataverse,magnolia}` |
| Index Solr | `data/solr/solr-data` |
| Contenu Magnolia (JCR) | `data/magnolia/repository` |
| Données du nœud producteur | `data/producer` |
| Secrets et clés | `.env`, `config/*/*.jks`, `config/magnolia/default/magnolia-activation-keypair.properties` |

Les procédures de sauvegarde sont dans
[roob-to-prod.md](./documentation/cookbook/roob-to-prod.md#persistance-et-sauvegardes)
et [data-persistence.md](./documentation/cookbook/data-persistence.md).

---

## Checklist sécurité

- [ ] `.env` sauvegardé de façon sécurisée (mode `600`, hors git)
- [ ] `config/*/*.jks` sauvegardés, en particulier les keystores applicatifs
- [ ] `config/acl/rudi-jwt.jks` présent avant le démarrage d'ACL
- [ ] `config/magnolia/default/magnolia-activation-keypair.properties` sauvegardé
- [ ] `config/acl/03-oauth-secrets.sql` appliqué après le premier démarrage d'ACL
- [ ] `traefik/acme.json` en mode `600`
- [ ] Mot de passe de `dataverseAdmin` égal à `DATAVERSE_ADMIN_PASSWORD`
- [ ] Mot de passe `superuser` de Magnolia changé
- [ ] Premier administrateur du portail créé
- [ ] Pare-feu : seuls les ports 80 et 443 ouverts au public
- [ ] Seuls les ports 80 et 443 sont publiés sur l'hôte (`docker ps` pour vérifier)
- [ ] Solr non exposé
- [ ] API d'administration Dataverse (`/api/admin`) bloquée, sauf depuis localhost
- [ ] Tableau de bord Traefik (port 8080) désactivé ou protégé
- [ ] MailHog remplacé par un SMTP réel ([configuration-mail.md](./documentation/cookbook/configuration-mail.md))
- [ ] `trust.trust-all-certs` et `module.oauth2.trust-all-certs` réévalués (à `true` dans les modèles)
- [ ] Sauvegardes automatiques en place et restauration testée
- [ ] Renouvellement automatique des certificats Let's Encrypt vérifié
- [ ] Politique de rétention des logs définie

---

## Maintenance

| Fréquence | Tâches |
|-----------|--------|
| Quotidienne | État des conteneurs, revue des logs, contrôle des sauvegardes |
| Hebdomadaire | Usage CPU/RAM/disque, test des points d'accès critiques |
| Mensuelle | Mise à jour des images, contrôle de l'expiration des certificats, `VACUUM ANALYZE` des bases |
| Trimestrielle | Rotation des mots de passe, audit de sécurité, prévision de capacité |

La rotation des mots de passe se fait avec `scripts/update-configs.sh` (voir
[scripts/README.md](./scripts/README.md)). Ne pas régénérer les keystores
applicatifs pendant une rotation. Pour les montées de version, voir la section
« Mettre à jour votre instance » du [README](./README.md).

---

## Dépannage

Voir [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
