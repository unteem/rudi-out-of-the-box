# Comment configurer Magnolia CMS pour RUDI ?

_Cas d'usage_ : je viens de déployer RUDI avec un Magnolia vierge et je veux le
configurer pour qu'il fonctionne avec le portail.

---

## Architecture Magnolia dans RUDI

Magnolia est le CMS headless qui fournit le contenu éditorial du portail RUDI
(actualités, conditions générales, valeurs de projet, termes). Il communique avec
le portail via son API REST de livraison de contenu.

La configuration est injectée via des montages de volumes Docker :

| Répertoire hôte | Chemin dans le container | Contenu |
|----------------|--------------------------|---------|
| `config/magnolia/` | `/usr/local/tomcat/webapps/ROOT/WEB-INF/config/` | Configuration Jackrabbit, JAAS, logging |
| `data/magnolia/modules/` | `/opt/magnolia/modules/` | Modules RUDI (templates FTL, définitions YAML) |
| `data/magnolia/repository/` | `/opt/magnolia/data/repository/` | Données JCR locales (datastore, index Lucene) |
| `database-data/magnolia/` | `/var/lib/postgresql/data` | Base de données PostgreSQL (bundles JCR) |

---

## Étape 1 — Première connexion

Accéder à l'interface d'administration :

```
https://magnolia.<domaine>/.magnolia/admincentral
```

Credentials par défaut au premier démarrage :

| Utilisateur | Mot de passe |
|-------------|--------------|
| `superuser` | `superuser` |

> **Changer ce mot de passe immédiatement** (voir Étape 2).

---

## Étape 2 — Changer le mot de passe superuser

1. Se connecter avec `superuser` / `superuser`
2. Aller dans **Security** → **Users**
3. Double-cliquer sur `superuser`
4. Changer le mot de passe dans le champ **Password**
5. Cliquer **Save**

---

## Étape 3 — Créer un utilisateur éditorial

Pour créer un utilisateur dédié à l'édition de contenu (sans accès superuser) :

1. **Security** → **Users** → **Add user**
2. Renseigner login, nom, mot de passe
3. Dans l'onglet **Roles**, ajouter le rôle `editor` ou `publisher` selon les besoins
4. **Save**

---

## Étape 4 — Configurer l'URL du portail RUDI dans Magnolia

Magnolia doit connaître l'URL publique du portail pour générer les liens corrects.

1. Aller dans **Configuration** (icône engrenage dans la barre latérale)
2. Naviguer vers `/modules/site/config/site/`
3. Trouver la propriété `url` ou `siteUrl`
4. La mettre à jour avec `https://rudi.<domaine>`
5. **Save** puis publier le nœud

Alternative via JCR Browser :
1. **JCR Browser** → workspace `config`
2. Naviguer vers `/modules/site/config/`
3. Modifier la propriété `url`

---

## Étape 5 — Sauvegarder la paire de clés d'activation

Au premier démarrage, Magnolia génère une paire de clés d'activation dans
`WEB-INF/config/default/`. Ce répertoire est monté depuis `config/magnolia/` :
le fichier est donc directement disponible sur l'hôte dans
`config/magnolia/default/magnolia-activation-keypair.properties`.

> Ce fichier contient une clé privée RSA. Il est exclu de git par `.gitignore` :
> le sauvegarder de manière sécurisée.

---

## Étape 6 — Créer le contenu initial

Le portail RUDI attend certains types de contenu dans Magnolia pour fonctionner
correctement. Sans contenu, les sections correspondantes du portail restent vides
(ce n'est pas bloquant).

### Types de contenu utilisés par RUDI

| Type | Application Magnolia | Chemin JCR | Utilisé dans le portail |
|------|---------------------|------------|------------------------|
| Actualités (`news`) | News | `/news` | Section actualités de la page d'accueil |
| CGU / Mentions légales (`term`) | Terms | `/terms` | Pages légales |
| Valeurs de projet (`projectvalue`) | Project Values | `/projectvalues` | Section valeurs de la page d'accueil |

Pour créer du contenu :
1. Aller dans l'application correspondante (ex: **News**)
2. **Add item**
3. Remplir les champs et publier

### Vérifier que le contenu est accessible via l'API

```bash
# Actualités
curl -s https://magnolia.<domaine>/magnolia/.rest/delivery/news/v1 | python3 -m json.tool

# Termes / CGU
curl -s https://magnolia.<domaine>/magnolia/.rest/delivery/terms/v1 | python3 -m json.tool

# Valeurs de projet
curl -s https://magnolia.<domaine>/magnolia/.rest/delivery/projectvalues/v1 | python3 -m json.tool
```

---

## Étape 7 — Vérifier la configuration Magnolia dans le portail

La propriété `magnoliaPublic8080.url` dans la configuration Magnolia doit pointer
vers l'URL interne de Magnolia (accessible depuis les microservices RUDI) :

1. Dans Magnolia : **Configuration** → chercher `magnoliaPublic8080`
2. Vérifier que `url` = `http://magnolia:8080` (URL interne Docker)
3. Si la valeur est incorrecte : modifier et publier

Le microservice **Konsult** contacte Magnolia sur cette URL pour récupérer le
contenu à afficher dans le portail.

---

## Changer le mot de passe d'un utilisateur Magnolia

### Via l'interface d'administration

1. **Security** → **Users**
2. Double-cliquer sur l'utilisateur
3. Modifier le champ **Password**
4. **Save**

### Via l'API REST (superuser uniquement)

```bash
curl -u superuser:<mot_de_passe> \
  -X POST \
  "https://magnolia.<domaine>/.magnolia/admincentral" \
  ...
```

L'interface web est la méthode recommandée pour Magnolia — les mots de passe
sont stockés dans le JCR (Jackrabbit), pas dans la base PostgreSQL directement.

---

## Persistance des données

Les données Magnolia sont stockées à deux endroits :

1. **PostgreSQL** (`database-data/magnolia/`) — les bundles JCR (contenu, config,
   utilisateurs, rôles). C'est la source de vérité.

2. **Système de fichiers** (`data/magnolia/repository/`) — le datastore local
   (binaires) et les index Lucene pour la recherche.

> **Ne pas restaurer uniquement la base PostgreSQL sans le répertoire
> `data/magnolia/repository/`.** Les deux doivent être cohérents. En cas de
> restauration, restaurer les deux simultanément ou repartir de zéro.

---

## Image Docker Magnolia

L'image est construite depuis `image/magnolia/` :
- Base : `tomcat:9-jdk11-temurin`
- Magnolia Community : version `6.2.40` (archive `ROOT-6.2.40.tgz`)
- JDBC : `postgresql-42.2.18.jar`

> Le dépôt `ci/docker/magnolia/` dans `rudi-portal` contient une version plus
> récente (6.2.48) utilisée par la CI du projet upstream. Pour mettre à jour
> Magnolia, remplacer `ROOT-6.2.40.tgz` par la nouvelle archive et mettre à
> jour le Dockerfile.

Pour reconstruire l'image après une modification :

```bash
docker compose -f docker-compose-magnolia.yml build magnolia
docker compose -f docker-compose-magnolia.yml --profile magnolia up -d magnolia
```
