# Comment utiliser la collection Bruno de RUDI ?

_Cas d'usage_ : je veux appeler les API du portail RUDI sans passer par
l'interface (vérifier une installation, dérouler un workflow, automatiser une
opération), ou comprendre quelles requêtes font l'interface et le nœud
producteur.

---

## La collection

Le dossier [`bruno/`](../../bruno) du dépôt est une collection
[Bruno](https://www.usebruno.com/), un client d'API open source dont les
requêtes sont des fichiers texte versionnés.

| Dossier | Contenu | Guide |
|---------|---------|-------|
| `00 Authentification` | Connexion des différents comptes, jeton du nœud | — |
| `10 Comptes` | Inscription, utilisateurs et rôles, mots de passe | [Cycle de vie des données](./cycle-de-vie-donnees.md#rôles-du-portail) |
| `20 Organisations` | Création et archivage (workflows), membres, logo, types d'adresses | [Organisations et rattachement](./organisations-et-rattachement.md) |
| `30 Nœud producteur` | Déclaration du nœud, organisation demandée par le nœud, rattachement, détachement | [Nœud producteur](./configuration-producer-node.md), [Organisations et rattachement](./organisations-et-rattachement.md) |
| `40 Jeux de données` | Publication via kalim, catalogue, téléchargement, jeux restreints | [Cycle de vie des données](./cycle-de-vie-donnees.md) |
| `50 Réutilisations` | Déclaration, accès aux jeux restreints, demandes de données, modification, archivage | [Réutilisations](./reutilisations.md) |
| `60 Accès API` | Clés d'API d'un projet, jeton OAuth2, téléchargement, API de l'apigateway | [Réutilisations](./reutilisations.md#accéder-aux-données-par-api) |
| `70 Exposition` | DCAT-AP, sitemaps, robots.txt, contenus Magnolia | [Cycle de vie des données](./cycle-de-vie-donnees.md#exposition-du-catalogue) |

---

## Installer et configurer

1. Installer Bruno (application de bureau) ou sa ligne de commande :

   ```bash
   npm install -g @usebruno/cli
   ```

2. Renseigner les comptes et l'adresse du portail :

   ```bash
   cp bruno/.env.example bruno/.env     # ignoré par git
   ```

   | Variable | Contenu |
   |----------|---------|
   | `RUDI_HOST`, `PRODUCER_HOST` | `rudi.<base_dn>` et le domaine du nœud (`PRODUCER_DOMAIN`) |
   | `ADMIN_LOGIN` / `ADMIN_PASSWORD` | Administrateur du portail (étape 14 de [roob-to-prod.md](./roob-to-prod.md)) |
   | `ANIMATEUR_LOGIN` / `ANIMATEUR_PASSWORD` | Compte avec le rôle `MODERATOR` (peut être l'administrateur) |
   | `USER_LOGIN` / `USER_PASSWORD` | Utilisateur du portail (porteur de réutilisation, membre d'organisation) |
   | `MEMBER_LOGIN` / `MEMBER_PASSWORD` | Membre de l'organisation productrice (accès aux jeux restreints) |
   | `NODE_LOGIN` / `NODE_PASSWORD` | Compte ROBOT du nœud : `PRODUCER_NODE_UUID` et `PRODUCER_PASSWORD` du `.env` du dépôt |
   | `*_UUID`, `DATASET_*` | Objets existants, facultatifs (voir ci-dessous) |

3. Ouvrir le dossier `bruno/` dans Bruno et choisir l'environnement **`roob`**.

---

## Fonctionnement

- **Connexion automatique** : chaque requête qui exige un compte se connecte
  d'abord avec le bon rôle (script `bru.runRequest` vers
  `00 Authentification`). Le jeton est conservé dans la variable `jwtToken`.
- **Enchaînement** : chaque étape enregistre les identifiants renvoyés
  (`organizationUuid`, `taskId`, `projectUuid`, `globalId`…) que les étapes
  suivantes réutilisent. Dans un workflow, l'étape « Trouver la tâche »
  retrouve la tâche de l'animateur (ce qu'il voit dans « Mes notifications »).
- **Objets existants** : une requête lancée seule, sans l'étape qui crée
  l'objet, reprend l'identifiant dans `.env` (`ORGANIZATION_UUID`,
  `PROJECT_UUID`, `DATASET_GLOBAL_ID`…).
- **Variantes** : les actions alternatives (refuser, relâcher une tâche,
  historique) sont dans des sous-dossiers `Variantes`.
- **Tests** : chaque requête vérifie son code retour ; les workflows vérifient
  en plus le résultat (tâche trouvée, organisation rattachée, intégration OK…).

---

## Exécuter un workflow

Dans Bruno : clic droit sur un dossier, **Run**. En ligne de commande, depuis
`bruno/` :

```bash
cd bruno

# Rattacher une organisation validée au nœud (ORGANIZATION_UUID dans .env)
bru run "30 Nœud producteur/03 Rattachement" --env roob

# Publier un jeu de données de test puis vérifier l'intégration
bru run "40 Jeux de données/01 Publier un jeu de données (nœud)" --env roob

# Plusieurs dossiers à la suite, rapport JUnit
bru run "20 Organisations/01 Créer une organisation (portail)" \
        "50 Réutilisations/01 Déclarer une réutilisation" \
        --env roob --reporter-junit resultats.xml
```

`bru run` sans `-r` ne joue pas les sous-dossiers `Variantes`.

> Les workflows créent de vraies données sur le portail (organisations,
> réutilisations, jeux de données). Sur une plateforme en production, utiliser
> des noms explicites (`ORGANIZATION_NAME`, `PROJECT_TITLE`, `DATASET_TITLE`)
> et nettoyer ensuite (requêtes de suppression ou d'archivage).

---

## Vérifier une installation

Après un déploiement, cet ordre couvre toute la chaîne :

1. `00 Authentification` : tous les comptes se connectent.
2. `30 Nœud producteur/02 Organisation productrice (demande du nœud)`, puis
   `03 Rattachement`.
3. `40 Jeux de données/01 Publier un jeu de données (nœud)` : l'intégration
   doit être `OK` et la métadonnée visible sur le portail.
4. `40 Jeux de données/02 Consulter le catalogue` : les facettes renvoient le
   thème du jeu publié.
5. `50 Réutilisations/01 Déclarer une réutilisation`.
6. `70 Exposition` : DCAT, sitemaps et contenus Magnolia.

---

## Origine

La collection reprend, en les adaptant à RUDI Out-of-the-Box (variables, comptes
de test, enchaînement des identifiants, rôles), les requêtes de la collection
de test des équipes RUDI. Les chemins, corps et rôles ont été vérifiés avec
les spécifications OpenAPI de rudi-portal.
