# Comment configurer l'envoi de mails ?

_Cas d'usage_ : je veux remplacer l'utilisation du simulateur de serveur de mail `mailhog` par un serveur de mail existant.

## Prérequis
Afin de configurer le serveur de mail utilisé par ROOB, vous devez au préalable disposer d'un serveur de mail fonctionnel et connaitre ses informations de connexion :

* Serveur
* Port
* Protocol
* Informations d'authentification (utilisateur, mot de passe)
* Adresse "from" à utiliser
* Utilisation du StartTLS
* Utilisation du debug

## Déploiement scripté : fichier `.env.smtp`

Avec le déploiement scripté ([roob-to-prod.md](./roob-to-prod.md)), les propriétés
mail des microservices sont générées à partir des variables `SMTP_*` :

```bash
cp .env.smtp.example .env.smtp
# Renseigner SMTP_HOST, SMTP_PORT, SMTP_AUTH, SMTP_USERNAME, SMTP_PASSWORD, SMTP_STARTTLS, SMTP_FROM
./scripts/prepare-properties.sh
docker compose -f docker-compose-rudi.yml restart acl kalim projekt selfdata strukture
```

Sans `.env.smtp`, `prepare-properties.sh` configure `mailhog`.

## Modifier les fichiers de propriétés pour chaque microservice concerné

Les microservices suivants utilisent l'envoi de mail :
* ACL
* Kalim
* Projekt
* Selfdata
* Strukture

Pour chaque microservice, modifier le fichier de configuration associé `config/<nomDuMicroservice>/<nomDuMicroservice>.properties`.

> Les fichiers `config/<service>/<service>.properties` sont générés depuis les `.properties.template` par `./scripts/prepare-properties.sh` : modifier le `.template` puis relancer ce script, sinon la modification sera écrasée.

Les propriétés concernés sont :

| Nom de la propriété | Description | Exemple de valeur | Valeur par défaut |
|---------------------|-------------|-------------------|-------------------|
| mail.transport.protocol | Protocol | smtp | smtp |
| mail.smtp.host | Hôte du serveur de mail | mailhog | |
| mail.smtp.port | Port du serveur de mail | 1025 | 25 |
| mail.smtp.auth | Utilisation d'une authentification | true | false |
| mail.smtp.user | Nom d'utilisateur pour l'authentification (utilisé si mail.smtp.auth=true) | user@example.com | |
| mail.smtp.password | Mot de passe pour l'authentification (utilisé si mail.smtp.auth=true) | motdepasse | |
| mail.smtp.starttls.enable | Utilisation du StartTLS | true | false |
| mail.from | Adresse expéditeur des emails | nepasrepondre@rudi.localhost | |
| mail.debug | Activation du mode debug | false | false |

Pour que la configuration soit prise en compte, redémarrer les microservices concernés.

## Désactiver mailhog

Arrêter le container de mailhog :

```bash
docker compose -f .\docker-compose-rudi.yml --profile "*" down mailhog
```

Dans le fichier `docker-compose-rudi.yml`, supprimer la section concernant le service `mailhog`.