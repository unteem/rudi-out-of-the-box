# Dépannage de la plateforme RUDI

Problèmes courants et solutions pour le déploiement RUDI.

Les conteneurs sont nommés `rudiplatform-<service>-1` (ex. `rudiplatform-acl-1`).
La pile complète se lance avec les quatre fichiers compose :

```bash
docker compose -f docker-compose-magnolia.yml -f docker-compose-rudi.yml \
  -f docker-compose-dataverse.yml -f docker-compose-network.yml --profile "*" up -d
```

Omettre `docker-compose-network.yml` casse le routage Traefik. Pour alléger les
commandes de ce document, on peut définir la fonction suivante :

```bash
rudi_compose() {
  docker compose -f docker-compose-magnolia.yml -f docker-compose-rudi.yml \
    -f docker-compose-dataverse.yml -f docker-compose-network.yml --profile "*" "$@"
}
```

---

## Secrets et configuration

Le fichier `.env.example` est versionné ; `.env` est généré. Le script
`scripts/generate-passwords.sh` ajoute à `.env` un bloc « Generated secrets »
(`DB_*`, `MS_*`, `KEYSTORE_PASSWORD`, `CONSENT_KEYSTORE_PASSWORD`,
`SELFDATA_KEYSTORE_PASSWORD`, `APIGATEWAY_KEYSTORE_PASSWORD`,
`JWT_KEYSTORE_PASSWORD`, `EUREKA_*`, `ADMIN_*`, `DATAVERSE_ADMIN_PASSWORD`,
`DATAVERSE_API_TOKEN`, sels). Les scripts chargent ce fichier avec
`set -a; source .env; set +a`.

`scripts/prepare-properties.sh` génère les fichiers `config/*/*.properties` à partir
des `.properties.template`. `scripts/update-configs.sh` réapplique la configuration
après une rotation des secrets.

### Variable non résolue dans un fichier `.properties`

**Symptôme** : un service ne démarre pas, ses logs mentionnent une valeur du type
`${DB_PASSWORD}`.

**Cause** : les fichiers `.properties` ont été générés sans que `.env` contienne les
secrets, ou n'ont pas été régénérés après modification de `.env`.

**Solution** :
```bash
# Vérifier la présence des secrets générés
grep -c "Generated secrets" .env

# Les générer si absents
./scripts/generate-passwords.sh

# Régénérer les fichiers properties
./scripts/prepare-properties.sh

# Rechercher les variables restées non résolues
grep -nE '\$\{[A-Z_]+\}' config/*/*.properties
```

---

## Keystores

`scripts/generate-ssl-keystores.sh` régénère à chaque exécution les keystores HTTPS
internes `config/<service>/rudi-https-certificate.jks` (mot de passe
`KEYSTORE_PASSWORD`, alias `rudi-https`).

En revanche, il n'écrase **jamais** les keystores applicatifs existants :

| Fichier | Alias | Mot de passe |
|---------|-------|--------------|
| `config/konsent/rudi-consent.jks` | `rudi-consent` | `CONSENT_KEYSTORE_PASSWORD` |
| `config/selfdata/rudi-selfdata.jks` | `rudi-selfdata` | `SELFDATA_KEYSTORE_PASSWORD` |
| `config/apigateway/rudi-apigateway.jks` | `defaultkey` | `APIGATEWAY_KEYSTORE_PASSWORD` |
| `config/acl/rudi-jwt.jks` | `rudi-jwt` | `JWT_KEYSTORE_PASSWORD` |

Pour en régénérer un, il faut le supprimer explicitement. **Attention** : les données
chiffrées ou signées avec l'ancien keystore (consentements, données selfdata, clés
d'accès aux médias, tokens JWT) deviennent illisibles ou invalides.

### Erreur : « keystore password was incorrect »

**Message complet** :
```
keytool error: java.io.IOException: keystore password was incorrect
```

**Cause** : le mot de passe présent dans `.env` ne correspond plus à celui du keystore
existant (secrets régénérés après la création des keystores, ou `.env` non chargé).

**Solution 1 : vérifier les secrets**

```bash
# Vérifier que les mots de passe sont présents
grep KEYSTORE_PASSWORD .env

# Les générer si absents
./scripts/generate-passwords.sh

# Relancer la génération
./scripts/generate-ssl-keystores.sh
```

**Solution 2 : supprimer les keystores HTTPS internes**

Seuls les fichiers `rudi-https-certificate.jks` peuvent être supprimés sans risque :

```bash
# Supprimer uniquement les keystores HTTPS internes
find config/ -name "rudi-https-certificate.jks" -delete

# Les régénérer
./scripts/generate-ssl-keystores.sh
```

Ne supprimez pas aveuglément tous les `*.jks` : si l'erreur concerne un keystore
applicatif (tableau ci-dessus), restaurez plutôt l'ancien mot de passe dans `.env`.
Ne le supprimez que si vous acceptez de perdre les données chiffrées associées.

### Konsent ou Selfdata échoue à la première utilisation : alias introuvable

**Symptômes** : la signature PDF des consentements échoue, ou le chiffrement des
données de matching selfdata échoue. Les logs indiquent par exemple
`KeyStore: No key entry found for alias`.

**Cause** : d'anciennes versions des templates déclaraient des alias différents de ceux
générés par `generate-ssl-keystores.sh` :

| Service | Alias généré | Ancienne valeur du template | Valeur correcte |
|---------|--------------|-----------------------------|-----------------|
| Konsent | `rudi-consent` | `rudi-dev` | `rudi-consent` |
| Selfdata | `rudi-selfdata` | `selfdata-matchingdata-key-20230321` | `rudi-selfdata` |

Les templates sont corrigés. Régénérez les properties et redémarrez :

```bash
./scripts/prepare-properties.sh
docker restart rudiplatform-konsent-1 rudiplatform-selfdata-1

# Vérifier l'alias présent dans un keystore
set -a; source .env; set +a
keytool -list -keystore config/konsent/rudi-consent.jks -storepass "$CONSENT_KEYSTORE_PASSWORD"
```

### Apigateway utilise le keystore de développement embarqué

**Symptômes** : les clés d'accès aux jeux de données médias sont chiffrées avec le
keystore de développement inclus dans le jar (mot de passe `rudi12345`). Le service
fonctionne, mais ce n'est pas sûr en production.

**Cause** : `config/apigateway/rudi-apigateway.jks` est absent (déploiement réalisé
avec une ancienne version des scripts). Il est désormais généré par
`generate-ssl-keystores.sh` avec `APIGATEWAY_KEYSTORE_PASSWORD`.

**Solution** :
```bash
ls -l config/apigateway/rudi-apigateway.jks
./scripts/generate-ssl-keystores.sh
./scripts/prepare-properties.sh
docker restart rudiplatform-apigateway-1
```

---

## Authentification JWT

### Avertissement : « Le token n'est pas un token JWT valide » (boutons absents, erreurs 403)

**Symptômes** : les logs des microservices affichent de manière répétée :

```
JwtRequestFilter - Le token n'est pas un token JWT valide.
```

Les fonctionnalités nécessitant une authentification sont absentes ou renvoient 403
(ex. bouton « Créer une organisation » invisible). La page d'accueil s'affiche, mais
les actions authentifiées échouent silencieusement.

**Contexte** : depuis RUDI v3.3.9, la propriété `security.jwt.access.tokenKey` a été
supprimée. ACL signe les JWT avec le keystore PKCS12 `config/acl/rudi-jwt.jks`
(alias `rudi-jwt`), configuré dans `config/acl/acl.properties` :

```properties
security.jwt.keystore=/etc/rudi/config/rudi-jwt.jks
security.jwt.keystore.password=${JWT_KEYSTORE_PASSWORD}
security.jwt.keystore.alias=rudi-jwt
```

Les autres microservices n'ont besoin d'aucune clé.

**Causes** :
- ACL démarre sans keystore persistant : il génère alors une clé aléatoire à chaque
  démarrage, et tous les tokens deviennent invalides après un redémarrage d'ACL ;
- le navigateur présente un token émis avant un redémarrage d'ACL ou un changement
  de keystore.

**Solution** :
```bash
# Vérifier la présence du keystore
ls -l config/acl/rudi-jwt.jks

# Vérifier la configuration
grep "security.jwt" config/acl/acl.properties

# Si le keystore est absent, le générer
./scripts/generate-ssl-keystores.sh

# Régénérer les properties et redémarrer ACL
./scripts/prepare-properties.sh
docker restart rudiplatform-acl-1
```

Les utilisateurs doivent ensuite se déconnecter puis se reconnecter pour obtenir un
nouveau token.

Voir [configuration-acl-jwt.md](documentation/cookbook/configuration-acl-jwt.md).

---

## Certificats TLS publics

Les certificats publics sont obtenus par Traefik via Let's Encrypt et stockés dans
`traefik/acme.json`.

### Le navigateur affiche un certificat invalide ou auto-signé

**Causes** : le domaine ne pointe pas vers le serveur, les ports 80/443 ne sont pas
joignables depuis Internet, ou `acme.json` a de mauvaises permissions.

**Solution** :
```bash
# Permissions requises par Traefik
ls -l traefik/acme.json
chmod 600 traefik/acme.json

# Erreurs ACME dans les logs Traefik
docker logs rudiplatform-reverse-proxy-1 2>&1 | grep -i acme

# Vérifier la résolution DNS
source .env
dig +short rudi.$base_dn
```

Voir [treafik-certificat-ssl.md](documentation/cookbook/treafik-certificat-ssl.md) et
[ssl-certificates-explained.md](documentation/cookbook/ssl-certificates-explained.md).

---

## Docker

### Erreur : « Cannot connect to the Docker daemon »

**Solution** :
```bash
# Démarrer le service Docker
sudo systemctl start docker
sudo systemctl enable docker

# Ajouter l'utilisateur au groupe docker
sudo usermod -aG docker $USER
newgrp docker

# Vérifier
docker ps
```

### Erreur : « port is already allocated »

**Cause** : un autre service utilise déjà un port (80, 443, etc.).

**Solution** :
```bash
# Identifier le processus qui occupe le port
sudo ss -tulpn | grep -E ':80 |:443 '

# Arrêter les services en conflit
sudo systemctl stop apache2
sudo systemctl stop nginx

# Ou modifier les ports exposés dans docker-compose-network.yml
```

### Erreur : « no space left on device »

**Solution** :
```bash
# Vérifier l'espace disque
df -h

# Supprimer les images inutilisées
docker image prune -a

# Nettoyage plus large (ne supprime pas les répertoires data/ et database-data/)
docker system prune -a
```

---

## Base de données

### Erreur : « database connection refused »

**Cause** : le conteneur de base de données n'est pas démarré ou pas encore prêt.

**Solution** :
```bash
# État et logs de la base
docker ps --filter name=rudiplatform-database-1
docker logs --tail=100 rudiplatform-database-1

# Vérifier qu'elle accepte les connexions
docker exec rudiplatform-database-1 pg_isready -U rudi

# Redémarrer si nécessaire
docker restart rudiplatform-database-1
```

### Erreur : « password authentication failed »

**Cause** : les mots de passe de `.env` ne correspondent plus à ceux utilisés lors de
l'initialisation de la base (la base n'est initialisée qu'une seule fois, à la
création de `database-data/rudi`).

**Solution** :
```bash
# Comparer .env et les properties générées
grep "^DB_" .env
grep spring.datasource.password config/acl/acl.properties

# Régénérer les properties à partir de .env
./scripts/prepare-properties.sh
```

Si les secrets de `.env` ont été régénérés après l'initialisation, restaurez les
anciens mots de passe ou mettez à jour les rôles PostgreSQL (`ALTER ROLE ... PASSWORD`).

### Erreur : « relation does not exist »

**Cause** : les tables n'ont pas été créées (migrations Flyway non exécutées).

**Solution** :
```bash
# Vérifier l'exécution de Flyway
docker logs rudiplatform-acl-1 2>&1 | grep -i flyway

# Redémarrer les services pour relancer les migrations
docker restart rudiplatform-acl-1 rudiplatform-kalim-1 rudiplatform-konsent-1 \
  rudiplatform-kos-1 rudiplatform-projekt-1 rudiplatform-selfdata-1 rudiplatform-strukture-1

# Vérifier le schéma
docker exec -it rudiplatform-database-1 psql -U rudi -d rudi -c "\dt acl_data.*"
```

---

## Démarrage des services

### Des services ne démarrent pas ou redémarrent en boucle

**Diagnostic** :
```bash
# État de tous les services
rudi_compose ps

# Logs d'un service
docker logs --tail=100 rudiplatform-acl-1

# Rechercher les erreurs
rudi_compose logs --tail=200 | grep -i error
```

**Solutions courantes** :

**1. Attendre les dépendances**
```bash
# Les microservices attendent la base et le registry ; vérifier leur santé
docker ps --filter name=rudiplatform-database-1
docker ps --filter name=rudiplatform-registry-1
```

**2. Vérifier la mémoire**
```bash
free -h
docker stats --no-stream
```

**3. Vérifier la configuration**
```bash
# Régénérer les properties
./scripts/prepare-properties.sh

# Rechercher les variables non résolues
grep -nE '\$\{[A-Z_]+\}' config/*/*.properties
```

**4. Redémarrer dans l'ordre**
```bash
# Tout arrêter
rudi_compose down

# Démarrer d'abord les bases
rudi_compose up -d database dataverse-database magnolia-database

# Puis le reste
rudi_compose up -d
```

---

## Registry Eureka

### Erreur : « Registration with Eureka failed »

**Cause** : registry inaccessible ou identifiants incorrects.

**Solution** :
```bash
# Vérifier le registry
docker logs --tail=100 rudiplatform-registry-1

# Comparer les identifiants
grep "^EUREKA_" .env
grep "eureka.client.serviceURL" config/acl/acl.properties
# Attendu : https://<EUREKA_USER>:<EUREKA_PASSWORD>@registry:8761/eureka

# Régénérer si besoin
./scripts/prepare-properties.sh
```

### Erreurs `ReplicationTaskProcessor` dans les logs du registry

**Symptômes** : le registry affiche en boucle l'une de ces erreurs :

```
ReplicationTaskProcessor - Batch update failure with HTTP status code 400; discarding N replication tasks
ReplicationTaskProcessor - Network level connection to peer registry; retrying after delay
  ... PKIX path building failed ...
```

**Cause** : le registry se prend pour un pair distinct de lui-même et tente de se
répliquer vers sa propre URL (`defaultZone`). Cela arrive quand son nom d'hôte ne
correspond pas à celui de `defaultZone`, par exemple avec
`eureka.instance.preferIpAddress=true`.

**Solution** : la plateforme n'a qu'un registry, configuré en mode autonome dans
`config/registry/registry.properties.template` :

```properties
eureka.instance.hostname=registry
eureka.instance.preferIpAddress=false
eureka.client.register-with-eureka=false
eureka.client.fetch-registry=false
eureka.client.serviceURL.defaultZone=https://registry:8761/eureka/
```

Puis :
```bash
./scripts/prepare-properties.sh
docker compose -f docker-compose-rudi.yml restart registry
```

---

## TLS interne

### Erreur : « unable to find valid certification path »

**Cause** : un microservice ne fait pas confiance au certificat d'un autre service
(certificats internes auto-signés).

**Solution** :
```bash
# Vérifier le paramètre de confiance
grep "trust-all-certs" config/*/*.properties

# Il est défini dans les templates ; régénérer si une valeur a été modifiée à la main
./scripts/prepare-properties.sh
```

---

## Dataverse et Solr

Dataverse utilise les images officielles `gdcc/dataverse:${dataverse_version}` (6.9)
et `solr:9.8.0`. Le schéma Solr avec les champs RUDI est versionné dans
`config/solr/collection1/conf/`, monté en lecture seule sur `/template` et copié dans
le core uniquement à sa première création (`solr-precreate collection1 /template`).
Les données du core sont dans `data/solr/solr-data`.

### Solr ne démarre pas (permission denied)

**Cause** : `data/solr` n'appartient pas à l'UID 8983 utilisé par l'image Solr.

**Solution** :
```bash
sudo chown -R 8983:8983 data/solr
docker restart rudiplatform-solr-1
```

### Le schéma Solr modifié n'est pas pris en compte

**Cause** : le template n'est copié qu'à la création du core ; un core existant
conserve son ancien schéma.

**Solution** (le core sera recréé, puis l'index devra être reconstruit) :
```bash
docker stop rudiplatform-solr-1
sudo rm -rf data/solr/solr-data/*
docker start rudiplatform-solr-1

# Reconstruire l'index
docker exec rudiplatform-dataverse-1 curl -s http://localhost:8080/api/admin/index
```

### Appels à l'API d'administration Dataverse refusés

**Cause** : `/api/admin` et `/api/builtin-users` ne sont accessibles que depuis
localhost (`dataverse_api_blocked_policy=localhost-only` dans
`docker-compose-dataverse.yml`).

**Solution** : exécuter les appels depuis le conteneur, ou depuis un conteneur
qui partage sa pile réseau (`--network container:rudiplatform-dataverse-1`) :
```bash
docker exec rudiplatform-dataverse-1 curl -s http://localhost:8080/api/admin/settings
```

### Messages sans gravité dans les logs Dataverse

| Message | Explication |
|---------|-------------|
| `findRootDataverse … getSingleResult() did not retrieve any entities` | La page d'accueil est appelée avant le bootstrap : il n'y a pas encore de collection racine. Disparaît après `init-dataverse.sh`. |
| `Jersey … should not consume any entity` / `contains empty path annotation` | Avertissements internes de Dataverse, sans effet. |
| `Cannot start JMX connector … No subject alternative names present` | Connecteur JMX d'administration de Payara, non utilisé. |
| `Unable to write GOAWAY … Connection reset by peer` | Le client a fermé la connexion HTTP/2. |
| `GRIZZLY0013 … Unknown protocol` suivi de caractères binaires | Une requête HTTPS est arrivée sur le port HTTP 8080. Dataverse ne publie plus de port sur l'hôte : seul Traefik (en HTTP) doit l'appeler. |

### Kalim ne crée pas de jeux de données / un jeu de données n'apparaît pas

**Cause** : l'initialisation de Dataverse est incomplète. `scripts/init-dataverse.sh`
effectue le bootstrap (configbaker `setup-all.sh` avec `DATAVERSE_ADMIN_PASSWORD`),
écrit `DATAVERSE_API_TOKEN` dans `.env`, charge le bloc de métadonnées `rudi`
(`rudi.tsv` issu de rudi-portal au tag `rudi_version`) et crée/publie les collections
`rudi_data`, `rudi_archive` et `rudi_media_data`.

**Vérifications** :
```bash
# Bloc de métadonnées rudi chargé
docker exec rudiplatform-dataverse-1 curl -s http://localhost:8080/api/metadatablocks/rudi | head -c 300

# Collections existantes
for c in rudi_data rudi_archive rudi_media_data; do
  docker exec rudiplatform-dataverse-1 curl -s -o /dev/null -w "$c: %{http_code}\n" \
    http://localhost:8080/api/dataverses/$c
done

# Jeton API renseigné
grep "^DATAVERSE_API_TOKEN=" .env

# Erreurs côté kalim
docker logs --tail=200 rudiplatform-kalim-1 2>&1 | grep -i -E "error|dataverse"
```

**Solution** :
```bash
# Relancer l'initialisation de Dataverse si un élément manque
./scripts/init-dataverse.sh

# Régénérer les properties (prise en compte de DATAVERSE_API_TOKEN) et redémarrer
./scripts/prepare-properties.sh
docker restart rudiplatform-kalim-1 rudiplatform-apigateway-1 rudiplatform-konsult-1

# Charger les vocabulaires KOS (thèmes, mots-clés...) si absents
./scripts/init-kos.sh
```

Voir [cycle-de-vie-donnees.md](documentation/cookbook/cycle-de-vie-donnees.md) et
[configuration-dataverse.md](documentation/cookbook/configuration-dataverse.md).

---

## Réutilisations

### Listes déroulantes vides dans le formulaire de réutilisation

**Symptôme** : « Type de réutilisation », « Échelle » ou « Public cible » ne
proposent aucune valeur ; « Accompagnement souhaité » ne propose que « Aucun ».

**Cause** : les migrations projekt ne remplissent pas ces listes de référence.

**Solution** : définir les valeurs dans `config/projekt/referentiels.json`
(copie de `referentiels.example.json`) puis lancer :
```bash
./scripts/init-projekt.sh --login <admin> --password '<mot de passe>'
```
Voir l'étape 16 de [roob-to-prod.md](documentation/cookbook/roob-to-prod.md).

---

## Nœud producteur

`scripts/deploy-producer.sh` déclare le nœud via l'API (fournisseur, nœud d'URL
`https://<PRODUCER_DOMAIN>/catalog/v1`, utilisateur ROBOT dont le login est l'UUID du nœud,
avec le rôle PROVIDER) et écrit les variables `PRODUCER_*` dans `.env`.
Le nœud utilise `PORTAL_URL=https://rudi.<base_dn>`.

### Les métadonnées du nœud n'arrivent pas sur le portail

**Vérifications** :
```bash
# Identifiants ROBOT
grep -E "^PRODUCER_(DOMAIN|NODE_UUID|PASSWORD_B64)=" .env

# URL du portail vue par le nœud
docker exec rudiplatform-producer-catalog printenv PORTAL_URL

# Erreurs d'intégration côté kalim
docker logs --tail=200 rudiplatform-kalim-1 2>&1 | grep -i -E "error|integration"
```

Consultez également le rapport d'intégration de chaque métadonnée dans l'interface
d'administration du nœud (node manager). Si les identifiants ROBOT sont incorrects,
relancez `./scripts/deploy-producer.sh` puis redémarrez les conteneurs du nœud.

Voir [configuration-producer-node.md](documentation/cookbook/configuration-producer-node.md).

### Strukture : « Node introuvable » à la validation d'une demande du nœud (500)

**Cause** : le login du compte ROBOT du nœud n'est pas l'UUID du nœud. strukture
(et kalim) retrouvent le nœud à partir de ce login ; un login égal à l'UUID du
fournisseur, comme le suggère la collection Bruno, ne fonctionne pas.

**Solution** : renommer le compte ROBOT avec l'UUID du nœud, mettre à jour les
demandes déjà émises, puis `.env` :
```bash
# UUID du fournisseur (ancien login) et du nœud
PROVIDER_UUID=<uuid-du-fournisseur>
NODE_UUID=<uuid-du-nœud>

docker exec rudiplatform-database-1 psql -U rudi -d rudi -c "
UPDATE acl_data.user_ SET login = '$NODE_UUID' WHERE login = '$PROVIDER_UUID';
UPDATE strukture_data.organization SET initiator = '$NODE_UUID' WHERE initiator = '$PROVIDER_UUID';
UPDATE strukture_data.linked_producer SET initiator = '$NODE_UUID' WHERE initiator = '$PROVIDER_UUID';"

# Dans .env : PRODUCER_NODE_UUID=<uuid-du-nœud>, puis
docker compose -f docker-compose-producer.yml up -d producer-catalog
```

### Catalog : « incorrect signature for this JWT » (403)

**Cause** : le manager signe ses requêtes vers le catalog et le storage avec une clé
(`catalog_mngr`, `store_mngr`) dont la partie publique est copiée dans
`data/producer/keys`. Le catalog garde cette clé publique en mémoire : si le
manager a changé de clé depuis, ses requêtes sont rejetées. Cela arrive si les clés
du manager ne sont pas persistées (`SAFE_DIR`) et que son conteneur est recréé.

**Solution** : vérifier que `producer-manager` a `SAFE_DIR: /data/safe/manager`
dans `docker-compose-producer.yml`, puis redémarrer catalog et storage pour
qu'ils relisent la clé :
```bash
docker compose -f docker-compose-producer.yml up -d producer-manager
docker compose -f docker-compose-producer.yml restart producer-catalog producer-storage
```

---

## Magnolia

### Paire de clés d'activation Magnolia

La paire de clés d'activation se trouve dans
`config/magnolia/default/magnolia-activation-keypair.properties`. Le répertoire
`config/magnolia` étant monté dans le conteneur, aucune étape d'extraction n'est
nécessaire. Conservez ce fichier lors des sauvegardes et ne le versionnez pas.

```bash
ls -l config/magnolia/default/magnolia-activation-keypair.properties
```

Voir [configuration-magnolia.md](documentation/cookbook/configuration-magnolia.md).

---

## Performances

### Les services sont très lents

**Solution** :
```bash
# Ressources système
top
free -h
df -h

# Consommation par conteneur
docker stats --no-stream

# Si nécessaire, ajouter des limites mémoire dans docker-compose-rudi.yml :
#   deploy:
#     resources:
#       limits:
#         memory: 2G
```

---

## Déploiement vierge

### Aucun utilisateur administrateur n'existe

**Cause** : comportement attendu sur un déploiement sans données.

**Solution** : créer le premier administrateur (l'extension `pgcrypto` est installée
par `config/rudi-init/02-extension.sql`) :

```bash
docker exec -it rudiplatform-database-1 psql -U rudi -d rudi
```

```sql
-- Créer l'utilisateur
INSERT INTO acl_data.user_ (uuid, company, firstname, lastname, login, password, type)
VALUES (gen_random_uuid(), 'monorganisation', 'Prénom', 'Nom', 'admin@mondomaine.fr',
        crypt('MotDePasse', gen_salt('bf')), 'PERSON');

-- Attribuer le rôle administrateur
INSERT INTO acl_data.user_role (user_fk, role_fk)
SELECT u.id, r.id
FROM acl_data.user_ u, acl_data.role r
WHERE u.login = 'admin@mondomaine.fr' AND r.code = 'ADMINISTRATOR';
```

---

## Réseau

### Le portail renvoie 405 sur POST /anonymous, toutes les pages redirigent vers /not-authorized

**Symptômes** : la page d'accueil redirige immédiatement vers `/not-authorized`. Les
outils de développement du navigateur montrent `POST /anonymous` en HTTP 405, avec
l'en-tête `server: nginx` (nginx du conteneur portail) au lieu du microservice ACL.

**Cause** : la pile a été démarrée sans `-f docker-compose-network.yml`. Traefik ne
reçoit alors aucun label de routage et toutes les requêtes vers
`https://rudi.<domaine>` aboutissent au nginx du portail, qui refuse les `POST`.

**Solution** : toujours démarrer la pile avec les quatre fichiers compose :

```bash
docker compose \
  -f docker-compose-magnolia.yml \
  -f docker-compose-rudi.yml \
  -f docker-compose-dataverse.yml \
  -f docker-compose-network.yml \
  --profile "*" up -d
```

Vérifier que `POST /anonymous` atteint bien ACL :

```bash
curl -sk -o /dev/null -w "%{http_code} %{content_type}\n" \
  -X POST https://rudi.<domaine>/anonymous
# Attendu : 200 application/json
# 405 avec server: nginx : docker-compose-network.yml n'a pas été inclus
```

### Impossible d'accéder à https://rudi.localhost

**Solution 1** : ajouter les noms d'hôtes dans `/etc/hosts`

```bash
sudo nano /etc/hosts

# Ajouter ces lignes
127.0.0.1 rudi.localhost
127.0.0.1 dataverse.localhost
127.0.0.1 magnolia.localhost
```

**Solution 2** : utiliser un vrai domaine

```bash
# Modifier base_dn dans .env
nano .env
# base_dn=mondomaine.fr

# Redéployer
./scripts/deploy.sh
```

---

## Retour arrière

### Annuler une modification de configuration

`scripts/update-configs.sh` crée une sauvegarde `config-backup-<date>` avant toute
modification.

```bash
# Dernière sauvegarde
BACKUP_DIR=$(ls -dt config-backup-* | head -1)
echo "Restauration depuis : $BACKUP_DIR"
rm -rf config
cp -r "$BACKUP_DIR" config

# Redémarrer les services
rudi_compose restart
```

### Repartir de zéro

**Attention : toutes les données sont supprimées.**

```bash
# Arrêter et supprimer les conteneurs
rudi_compose down -v

# Supprimer les données persistées
sudo rm -rf database-data data/solr/solr-data

# Redéployer
./scripts/deploy.sh
```

Les keystores applicatifs (`config/acl/rudi-jwt.jks`, etc.) sont conservés ; supprimez-les
explicitement si vous souhaitez aussi les régénérer.

---

## Commandes de diagnostic

### Vérification complète

```bash
# Prérequis
./scripts/check-prerequisites.sh

# Docker
docker --version
docker compose version
docker stats --no-stream

# Espace disque
df -h

# État des services
rudi_compose ps

# Erreurs récentes
rudi_compose logs --tail=50 | grep -i error

# Base de données
docker exec rudiplatform-database-1 pg_isready -U rudi

# Registry Eureka : microservices enregistrés
docker logs rudiplatform-registry-1 2>&1 | grep "Registered instance" | tail -n 15

# Accès publics
curl -k -s -o /dev/null -w "Portail : %{http_code}\n" "https://rudi.$base_dn"
curl -k -s -o /dev/null -w "Dataverse : %{http_code}\n" "https://dataverse.$base_dn"
curl -k -s -o /dev/null -w "Magnolia : %{http_code}\n" "https://magnolia.$base_dn"
```

### Rapport de diagnostic

```bash
REPORT_FILE="rudi-diagnostic-$(date +%Y%m%d-%H%M%S).txt"
set -a; source .env; set +a

{
  echo "## Système"
  uname -a
  docker --version
  docker compose version
  df -h
  free -h

  echo "## Conteneurs"
  docker ps -a --filter name=rudiplatform

  echo "## Erreurs récentes"
  docker compose -f docker-compose-magnolia.yml -f docker-compose-rudi.yml \
    -f docker-compose-dataverse.yml -f docker-compose-network.yml --profile "*" \
    logs --tail=100 | grep -i error

  echo "## Accès publics"
  curl -k -s -o /dev/null -w "Portail : %{http_code}\n" "https://rudi.$base_dn"
  curl -k -s -o /dev/null -w "Dataverse : %{http_code}\n" "https://dataverse.$base_dn"
  curl -k -s -o /dev/null -w "Magnolia : %{http_code}\n" "https://magnolia.$base_dn"
} > "$REPORT_FILE" 2>&1

echo "Rapport enregistré dans : $REPORT_FILE"
```

Le rapport ne contient pas de secrets, mais relisez-le avant de le partager.

---

## Obtenir de l'aide

1. Consulter les logs :
   ```bash
   rudi_compose logs -f
   ```
2. Générer un rapport de diagnostic (voir ci-dessus).
3. Consulter la documentation :
   - [README.md](README.md)
   - [PRODUCTION-DEPLOYMENT.md](PRODUCTION-DEPLOYMENT.md)
   - [documentation/cookbook/](documentation/cookbook/)
4. Rechercher dans les tickets existants :
   https://github.com/rudi-platform/rudi-out-of-the-box/issues
5. Ouvrir un ticket avec le message d'erreur, le rapport de diagnostic, les étapes de
   reproduction et les informations système.
