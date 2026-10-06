# Comment configurer Magnolia CMS pour RUDI ?

_Cas d'usage_ : je viens de déployer RUDI et je veux préparer Magnolia pour que
les équipes éditoriales puissent publier des actualités, des conditions
d'utilisation et des valeurs du projet sur le portail.

---

## Architecture Magnolia dans RUDI

Magnolia est le CMS headless qui fournit le contenu éditorial du portail
(actualités, conditions d'utilisation, valeurs du projet). Le microservice
konsult le lit sans authentification :

- via les endpoints de livraison `/.rest/delivery/{categories,news,terms,projectvalues}/v1` ;
- via les pages de rendu `rudi/<template>.html` (titres, listes, plan du site) ;
- via les images du DAM (`/dam/…`, `/.imaging/…`).

| Emplacement | Contenu |
|-------------|---------|
| Image `rudiplatform/magnolia` (`image/magnolia/`) | Magnolia 6.2.40, module RUDI (`modules-rudi/` : types de contenu, templates, endpoints), contenu de structure (`content/structure/`) |
| `config/magnolia/` → `WEB-INF/config/` | Configuration Jackrabbit, JAAS, logs, `magnolia.properties` |
| `data/magnolia/repository/` | Datastore Jackrabbit (binaires : images du DAM) |
| `database-data/magnolia/` | Base PostgreSQL (nœuds et propriétés de tous les workspaces) |

### Contenu de structure installé automatiquement

Au premier démarrage, le module Content Importer de Magnolia importe les
fichiers de `image/magnolia/content/structure/` (paramètres
`magnolia.content.bootstrap.*` de `config/magnolia/default/magnolia.properties`) :

| Workspace | Contenu |
|-----------|---------|
| `category` | Catégories `/rudi/terms/{cgu,legal-mention,privacy-policy,copyrights}`, `/rudi/news/a-la-une`, `/rudi/projectvalues/main`, utilisées par konsult pour filtrer le contenu |
| `website` | Pages de rendu `/rudi/rudi-terms`, `/rudi/rudi-news`, `/rudi/rudi-project-values` |
| `news`, `terms`, `projectvalues` | Dossier racine `/rudi`, vide |
| `userroles` | Rôles `news_editor`, `terms_editor`, `projectvalues_editor`, `Imaging-editor`, `back_office_connexion` ; permissions de lecture anonyme ajoutées aux rôles `anonymous` et `rest-anonymous` |
| `usergroups` | Groupe `editor` (tous les rôles d'édition RUDI), groupe `super-users` (rôle `superuser`) |

Aucun compte utilisateur ni contenu éditorial n'est installé.

Un chemin déjà présent n'est jamais écrasé : si un fichier de structure change
dans une nouvelle version de l'image, Magnolia propose une tâche d'import au
superuser (application **Tasks**) au lieu de remplacer les modifications faites
dans l'interface.

---

## Étape 1 — Première connexion et mot de passe superuser

Interface d'administration : `https://magnolia.<domaine>/.magnolia/admincentral`

Identifiants au premier démarrage : `superuser` / `superuser`. **Changer ce mot
de passe immédiatement** :

1. **Security** → **Users** → `system` → `superuser`
2. Saisir le nouveau mot de passe dans **Password**
3. **Save**

> Magnolia 6.2.40 ne permet pas de définir ce mot de passe avant le premier
> démarrage. Les versions 6.2.72 et suivantes le permettent
> (`magnolia.superuser.bootstrap.password_file`) : voir le TODO de
> `image/magnolia/README.md`.

---

## Étape 2 — Vérifier le contenu de structure

```bash
# Catégories RUDI (accès anonyme, comme konsult)
curl -s https://magnolia.<domaine>/.rest/delivery/categories/v1 | python3 -m json.tool | grep '"@path"'

# Une page de rendu
curl -s -o /dev/null -w '%{http_code}\n' https://magnolia.<domaine>/rudi/rudi-terms/one-term-title.html
```

Les catégories `/rudi/...` doivent apparaître et la page doit répondre `200`.
Sinon, consulter les tâches d'import dans l'application **Tasks** et les logs :

```bash
docker logs rudiplatform-magnolia-1 2>&1 | grep -i -E "content-importer|bootstrap|import" | tail -20
```

---

## Étape 3 — Créer les comptes éditoriaux

Les comptes ne sont pas livrés avec l'installation : chaque équipe crée les siens.

1. **Security** → **Users** → **Add user**
2. Renseigner login, nom, adresse e-mail et mot de passe
3. Onglet **Groups** : ajouter `editor` (actualités, conditions d'utilisation,
   valeurs du projet et images). Pour un accès plus restreint, ne pas mettre de
   groupe et ajouter, dans l'onglet **Roles**, `back_office_connexion` et le ou
   les rôles voulus (`news_editor`, `terms_editor`, `projectvalues_editor`,
   `Imaging-editor`)
4. **Save**

---

## Étape 4 — Publier le contenu éditorial

Le contenu se crée dans les dossiers `/rudi` des applications **News**,
**Terms** et **Project Values**, en lui affectant une catégorie RUDI :

| Contenu | Application | Catégorie | Affichage sur le portail |
|---------|-------------|-----------|--------------------------|
| Actualités | News | `/rudi/news/a-la-une` | Section actualités de l'accueil |
| Conditions d'utilisation, mentions légales, politique de confidentialité | Terms | `/rudi/terms/cgu`, `legal-mention`, `privacy-policy`, `copyrights` | Pages légales et liens du pied de page |
| Valeurs du projet | Project Values | `/rudi/projectvalues/main` | Section valeurs de l'accueil |

Les images se déposent dans le dossier `/rudi` de l'application **Assets**.

Vérifier que le contenu est servi :

```bash
curl -s https://magnolia.<domaine>/.rest/delivery/news/v1 | python3 -m json.tool | head -30
curl -s https://magnolia.<domaine>/.rest/delivery/terms/v1 | python3 -m json.tool | head -30
curl -s https://magnolia.<domaine>/.rest/delivery/projectvalues/v1 | python3 -m json.tool | head -30
```

### Contenu de démonstration (optionnel)

Le contenu de l'instance de démonstration (12 actualités, conditions
d'utilisation, 4 valeurs du projet et les 14 images utilisées) n'est pas
versionné. Il se génère depuis la sauvegarde de la branche `main` :

```bash
./scripts/magnolia-export.sh --password '<mot de passe superuser de la sauvegarde>' --set demo
```

Puis, pour chaque fichier de `magnolia-export/<date>/demo/<workspace>/` :
**JCR Tools** → **Importer** → choisir le workspace, le chemin parent `/`, le
fichier, puis **Import**. Importer le DAM (`dam`) en premier.

> Les textes de démonstration (conditions d'utilisation notamment) sont ceux
> de Rennes Métropole : les remplacer avant toute ouverture au public.

---

## Étape 5 — Sauvegarder la paire de clés d'activation

Au premier démarrage, Magnolia génère une paire de clés d'activation dans
`WEB-INF/config/default/`, monté depuis `config/magnolia/` : le fichier est
disponible sur l'hôte dans
`config/magnolia/default/magnolia-activation-keypair.properties`.

> Ce fichier contient une clé privée RSA. Il est exclu de git par `.gitignore` :
> le sauvegarder de manière sécurisée.

---

## Persistance des données

Les données Magnolia sont stockées à deux endroits :

1. **PostgreSQL** (`database-data/magnolia/`) : nœuds et propriétés de tous les
   workspaces (contenu, configuration, utilisateurs, rôles).
2. **Système de fichiers** (`data/magnolia/repository/`) : le datastore
   (binaires de plus de 1 Ko, essentiellement les images), désigné dans la base
   par l'empreinte SHA-256 de chaque fichier.

> **Toujours sauvegarder et restaurer les deux ensemble.** Une base sans son
> datastore donne des images cassées ; un datastore sans sa base est
> inexploitable.

---

## Mettre à jour le contenu de structure

Les fichiers de `image/magnolia/content/structure/` sont produits par
`scripts/magnolia-export.sh` (voir [scripts/README.md](../../scripts/README.md)) :

```bash
# Référence : ce qu'une installation Magnolia neuve crée elle-même
./scripts/magnolia-export.sh --fresh

# Structure RUDI, à partir de la sauvegarde de main (ou --dump/--repository)
./scripts/magnolia-export.sh --password '<mot de passe superuser>' --set structure

# Remplacer les fichiers versionnés, relire le diff, reconstruire l'image
rm -rf image/magnolia/content/structure
cp -r magnolia-export/<date>/structure image/magnolia/content/structure
rm image/magnolia/content/structure/INVENTAIRE.md
git diff --stat image/magnolia/content/structure
```

Les chemins exportés sont listés dans `scripts/magnolia-export.structure.paths`.
Pour les rôles par défaut de Magnolia (`anonymous`, `rest-anonymous`), seules
les permissions absentes de la référence sont exportées, une par fichier : elles
s'ajoutent aux rôles existants sans les écraser.

---

## Image Docker Magnolia

L'image est construite depuis `image/magnolia/` (voir
[image/magnolia/README.md](../../image/magnolia/README.md)) :

```bash
docker compose -f docker-compose-magnolia.yml build magnolia
docker compose -f docker-compose-magnolia.yml --profile magnolia up -d magnolia
```
