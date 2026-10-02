# Comment générer une clé privée persistée pour les certificats des JWT ?

_Cas d'usage_ : je souhaite utiliser un certificat persisté pour signer les tokens JWT, plutôt qu'une clé aléatoire générée à chaque démarrage du service.

## Contexte et intérêt

Le microservice ACL est l'émetteur des tokens JWT du portail. Sans keystore configuré, il génère une clé RSA aléatoire à chaque démarrage, ce qui pose plusieurs problèmes :

* Les tokens deviennent invalides à chaque redémarrage d'ACL
* Manque de transparence et de contrôle sur la signature des tokens

La solution est de générer une clé privée persistée dans un keystore dédié et de configurer ACL pour qu'il l'utilise.

## Génération automatique

Avec le déploiement scripté ([roob-to-prod.md](./roob-to-prod.md)), rien n'est à faire :

* `scripts/generate-passwords.sh` génère `JWT_KEYSTORE_PASSWORD` dans `.env`
* `scripts/generate-ssl-keystores.sh` crée `config/acl/rudi-jwt.jks` (PKCS12, alias `rudi-jwt`). Un keystore existant n'est jamais écrasé.
* `config/acl/acl.properties.template` contient la configuration ci-dessous

## Génération manuelle

### Prérequis

* `keytool` (fourni avec le JDK) disponible dans le PATH
* Un mot de passe pour sécuriser le keystore

### Générer le keystore

Depuis le répertoire racine du projet `rudi-out-of-the-box` :

```bash
keytool -genkeypair \
  -alias rudi-jwt \
  -keyalg RSA \
  -keysize 2048 \
  -validity 3650 \
  -storetype PKCS12 \
  -keystore ./config/acl/rudi-jwt.jks \
  -storepass <mot_de_passe_keystore> \
  -keypass <mot_de_passe_keystore> \
  -dname "CN=RUDI JWT,O=RUDI Platform,C=FR"
chmod 600 ./config/acl/rudi-jwt.jks
```

ACL charge le keystore au format **PKCS12** et utilise le même mot de passe pour le keystore et pour la clé.

**Note :** ce fichier contient la clé privée de signature. Il doit être sauvegardé de manière sécurisée.

### Configurer le service ACL

Dans `config/acl/acl.properties` (le répertoire `config/acl/` est monté sur `/etc/rudi/config/` dans le conteneur) :

```properties
# Keystore JWT
security.jwt.keystore=/etc/rudi/config/rudi-jwt.jks
security.jwt.keystore.password=<mot_de_passe_keystore>
security.jwt.keystore.alias=rudi-jwt
```

## Redémarrer le service

```bash
docker compose -f docker-compose-rudi.yml up -d acl
```

Les tokens JWT signés par ACL utilisent désormais la clé du keystore `rudi-jwt.jks`. Les autres microservices vérifient les tokens auprès d'ACL : aucune clé n'est à leur distribuer.
