# Comment une donnée est-elle publiée sur le portail RUDI ?

_Cas d'usage_ : je veux comprendre comment les différents composants (nœud
producteur, portail, Dataverse) interagissent, et publier un premier jeu de
données de test pour valider la chaîne complète.

---

## Vue d'ensemble

```
┌──────────────── Nœud producteur (rudinode) ──────────────────┐
│  manager (interface web) ──► catalog (métadonnées, MongoDB)   │
│                          └─► storage (fichiers de données)    │
└─────────────┬──────────────────────────────▲──────────────────┘
              │ ① envoi des métadonnées      │ ④ les fichiers sont
              │   POST/PUT kalim/v1/resources│   téléchargés depuis le nœud
              │   (OAuth2, compte ROBOT)     │
┌─────────────▼──────────────────────────────┴──────────────────┐
│  Portail RUDI                                                  │
│  kalim ──② écrit──► Dataverse (métadonnées uniquement) ◄── konsult
│     └──③ crée les routes de téléchargement dans apigateway     │
│  apigateway : contrôle d'accès, proxy vers le nœud, déchiffrement
└────────────────────────────────────────────────────────────────┘
```

En résumé : **les données sont saisies et stockées sur le nœud producteur**, le
**portail ne reçoit que les métadonnées** (stockées dans Dataverse) et sert de
point d'accès unique pour la recherche et le téléchargement.

---

## Rôle de chaque composant

| Composant | Où | Rôle |
|-----------|----|------|
| `manager` | nœud | Interface web de saisie : organisations, contacts, métadonnées, fichiers |
| `catalog` | nœud | Stocke les métadonnées (MongoDB), les expose (`/catalog/v1/resources`) et les envoie au portail |
| `storage` | nœud | Stocke les fichiers de données et les sert au téléchargement |
| `acl` | portail | Authentification : délivre le token OAuth2 au compte ROBOT du nœud |
| `strukture` | portail | Référentiel des fournisseurs et des nœuds |
| `kalim` | portail | Reçoit et valide les métadonnées, les écrit dans Dataverse, crée les routes de téléchargement |
| `kos` | portail | Vocabulaires contrôlés (thèmes, licences) utilisés pour valider les métadonnées |
| Dataverse + Solr | portail | Base de métadonnées et moteur de recherche du catalogue |
| `konsult` | portail | Lit Dataverse pour afficher le catalogue et la recherche |
| `apigateway` | portail | Point de téléchargement : contrôle d'accès puis proxy vers le `storage` du nœud |
| `selfdata` / `konsent` | portail | Données personnelles et consentements (jeux de données « selfdata ») |

---

## Le parcours d'une donnée

### 1. Saisie sur le nœud producteur

Tout se fait dans le **manager** du nœud (`https://producteur.<domaine>/manager/`) :

1. Disposer d'une **organisation** productrice validée sur le portail et
   rattachée au nœud (voir
   [Organisations et rattachement](./organisations-et-rattachement.md)), et
   créer un **contact**.
2. Créer une **métadonnée** : titre, description, thème, licence, dates, etc.
   Le thème et la licence doivent faire partie des vocabulaires KOS du portail.
3. Joindre un ou plusieurs **fichiers** (CSV, GeoJSON, PDF…) ou référencer une
   URL externe. Les fichiers restent stockés **sur le nœud**.

### 2. Envoi des métadonnées au portail

À la publication, le `catalog` du nœud :

1. Obtient un token OAuth2 auprès de `<portail>/oauth2/token` avec le compte
   ROBOT (login = UUID du nœud, voir
   [Comment déployer et déclarer un nœud producteur ?](./configuration-producer-node.md)).
2. Envoie la métadonnée sur `<portail>/kalim/v1/resources` : `POST` pour une
   création, `PUT` pour une mise à jour.

Le portail peut aussi **moissonner** le nœud : si le nœud est déclaré avec
`harvestable: true` dans strukture, kalim interroge périodiquement
`<url_du_nœud>/resources?updated_after=...`. Les deux mécanismes coexistent.

### 3. Intégration côté portail (kalim)

Pour chaque demande d'intégration, kalim :

1. **Valide** la métadonnée : organisation productrice connue du portail
   (sinon `ERR_113`), thème et licence présents dans KOS, champs obligatoires,
   version de format (`metadata_info.api_version` 1.2.0 à 1.4.2). En cas
   d'erreur, un **rapport d'intégration** est renvoyé au nœud et visible dans
   le manager.
2. **Crée un jeu de données Dataverse** contenant la métadonnée.
3. **Crée les routes** de téléchargement dans l'apigateway.

À la suppression, le jeu de données est déplacé dans la collection d'archive.

### 4. Consultation et téléchargement

- **Recherche / affichage** : `konsult` lit Dataverse et Solr.
- **Téléchargement** : le portail appelle l'`apigateway`, qui vérifie les droits
  (donnée ouverte, restreinte ou selfdata), relaie la requête vers le `storage`
  du nœud et déchiffre le fichier si nécessaire. Le fichier ne transite que
  le temps du téléchargement, il n'est pas stocké sur le portail.

### Jeux de données restreints

Un jeu de données à accès restreint (`restricted_access: true`) est chiffré
par le nœud avec la clé publique du portail
(`/apigateway/v1/encryption-key`). Seules les réutilisations auxquelles
l'organisation productrice a accordé l'accès peuvent le télécharger ;
l'apigateway déchiffre alors le fichier. Voir
[Réutilisations](./reutilisations.md#accéder-à-un-jeu-de-données-restreint).

---

## Rôles du portail

| Rôle | Attribué à | Permet |
|------|------------|--------|
| `ADMINISTRATOR` | Administrateur de la plateforme | Administration : comptes, fournisseurs et nœuds, organisations, référentiels |
| `MODERATOR` (Animateur) | Équipe d'animation (souvent l'administrateur aussi) | Valider les organisations, rattachements, détachements, réutilisations, demandes de nouvelles données |
| `USER` | Tout compte créé par inscription | Déclarer des organisations et des réutilisations, demander l'accès à des jeux restreints |
| `PROVIDER` | Compte ROBOT d'un nœud (login = UUID du nœud) | Publier des métadonnées (kalim), demander création, rattachement et détachement d'organisations |
| `MODULE_*` | Comptes techniques des microservices | Appels entre microservices (créés à l'installation) |

Dans une **organisation**, un membre est `ADMINISTRATOR` (gère l'organisation
et ses membres) ou `EDITOR`. Les membres de l'organisation productrice d'un
jeu restreint traitent les demandes d'accès.

Gestion des comptes et des rôles : dossier `10 Comptes` de la
[collection Bruno](./utiliser-bruno.md).

---

## Ce que contient Dataverse

Dataverse ne stocke **que des métadonnées**, aucun fichier des producteurs.

| Collection | Propriété | Contenu |
|------------|-----------|---------|
| `rudi_data` | `dataverse.api.rudi.data.alias` | Jeux de données publiés |
| `rudi_archive` | `dataverse.api.rudi.archive.alias` | Jeux de données supprimés / archivés |
| `rudi_media_data` | `dataverse.api.rudi.media.data.alias` | Médias propres au portail (logos d'organisation, images de projets) |

Voir [Comment configurer Dataverse et Solr pour RUDI ?](./configuration-dataverse.md).

---

## Conditions pour qu'une donnée apparaisse sur le portail

| Condition | Symptôme si absente | Voir |
|-----------|---------------------|------|
| Le nœud connaît l'URL du portail et les bons identifiants ROBOT | Aucune demande d'intégration reçue par kalim | [Nœud producteur](./configuration-producer-node.md) |
| Fournisseur, nœud et compte ROBOT déclarés dans le portail | Erreur 401/403 côté nœud | [Nœud producteur](./configuration-producer-node.md) |
| Vocabulaires KOS chargés | Rapport d'intégration en erreur (thème ou licence inconnu) | [KOS](./configuration-kos.md) |
| Collections Dataverse et token API configurés | Erreur kalim lors de la création du jeu de données | [Dataverse](./configuration-dataverse.md) |
| Organisation productrice validée et rattachée au nœud | Rapport d'intégration en erreur `ERR_113` | [Organisations et rattachement](./organisations-et-rattachement.md) |
| Index Solr à jour | Jeu de données absent de la recherche | [Dataverse](./configuration-dataverse.md) |
| Facettes de `rudi_data` configurées | Accueil en chargement, thèmes affichés `[code]` | [Dataverse](./configuration-dataverse.md) |

---

## Exposition du catalogue

| Point d'accès | Usage |
|---------------|-------|
| `/konsult/v1/datasets/metadatas` | Recherche (texte, thèmes, mots-clés, producteurs) |
| `/konsult/v1/datasets/metadatas/dcat` | Catalogue au format DCAT-AP (JSON-LD), pour data.gouv.fr ou les catalogues européens |
| `/konsult/v1/sitemap/…`, `/konsult/v1/robots/robots.txt` | Référencement (voir [configuration-sitemap.md](./configuration-sitemap.md)) |
| `/medias/<global_id>/<media_id>/dwnl` | Téléchargement d'un fichier via l'apigateway |

Bruno : dossiers `40 Jeux de données/02 Consulter le catalogue` et
`70 Exposition`.

---

## Publier un premier jeu de données de test

Prérequis : vocabulaires KOS chargés, organisation productrice validée et
rattachée au nœud ([Organisations et rattachement](./organisations-et-rattachement.md)).

### Option A — Depuis le manager du nœud

1. Se connecter au manager : `https://<PRODUCER_DOMAIN>/manager/` (identifiants :
   voir [Définir les identifiants du manager](./configuration-producer-node.md#étape-3--définir-les-identifiants-du-manager)).
2. Créer un **contact**.
3. Créer une **métadonnée** : producteur = l'organisation rattachée, contact,
   thème et licence proposés par le formulaire (issus de KOS), dates et
   description ; joindre un petit fichier CSV.
4. Publier, puis consulter le **rapport d'intégration** de la métadonnée dans
   le manager : il doit être `OK`. La métadonnée n'est envoyée au portail
   qu'une fois son fichier déposé dans le stockage du nœud.
5. Pendant l'intégration :

   ```bash
   docker logs -f --since 1m rudiplatform-kalim-1 2>&1 | grep -v -i hibernate
   docker logs -f --since 1m rudiplatform-producer-catalog 2>&1 | grep -i -E "portal|error"
   ```

6. Sur le portail : rechercher le jeu de données, vérifier son thème (libellé
   et pictogramme) et télécharger le fichier.

### Option B — Bruno

`40 Jeux de données/01 Publier un jeu de données (nœud)` envoie à kalim une
métadonnée comme le ferait le catalog du nœud, vérifie l'intégration et la
présence sur le portail (sans fichier réellement déposé sur le nœud : le
téléchargement échouera). Voir [Utiliser Bruno](./utiliser-bruno.md).

En cas d'échec, voir [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md).
