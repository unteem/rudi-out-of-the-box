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

1. Créer une **organisation** (le producteur de la donnée) et un **contact**.
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

1. **Valide** la métadonnée : fournisseur connu, thème et licence présents dans
   KOS, champs obligatoires. En cas d'erreur, un **rapport d'intégration** est
   renvoyé au nœud et visible dans le manager.
2. **Crée un jeu de données Dataverse** contenant la métadonnée.
3. **Crée les routes** de téléchargement dans l'apigateway.

À la suppression, le jeu de données est déplacé dans la collection d'archive.

### 4. Consultation et téléchargement

- **Recherche / affichage** : `konsult` lit Dataverse et Solr.
- **Téléchargement** : le portail appelle l'`apigateway`, qui vérifie les droits
  (donnée ouverte, restreinte ou selfdata), relaie la requête vers le `storage`
  du nœud et déchiffre le fichier si nécessaire. Le fichier ne transite que
  le temps du téléchargement, il n'est pas stocké sur le portail.

### Rattacher une organisation du portail à un nœud (optionnel)

Une organisation existante sur le portail peut être rattachée à un nœud
(« linked producer ») : le nœud émet une demande de rattachement
(`node/v1/linked-producers/request/{uuid}`), puis un animateur la valide dans le
portail (espace « Mes notifications »). Ce workflow est décrit dans la
collection Bruno « Workflow - Demande de rattachement ».

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
| Index Solr à jour | Jeu de données absent de la recherche | [Dataverse](./configuration-dataverse.md) |

---

## Publier un premier jeu de données de test

1. Se connecter au manager du nœud : `https://producteur.<domaine>/manager/` (identifiants : voir [Définir les identifiants du manager](./configuration-producer-node.md#étape-3--définir-les-identifiants-du-manager)).
2. Créer une organisation et un contact.
3. Créer une métadonnée avec un thème et une licence issus de KOS, puis joindre
   un petit fichier CSV.
4. Publier la métadonnée et consulter son **rapport d'intégration** dans le
   manager : il doit être `OK`.
5. Vérifier côté portail :

   ```bash
   # Logs de kalim pendant l'intégration
   docker logs -f rudiplatform-kalim-1

   # Métadonnée visible via konsult (remplacer <global_id> par l'identifiant de la métadonnée)
   curl -s https://rudi.<domaine>/konsult/v1/datasets/<global_id>/metadatas
   ```

6. Rechercher le jeu de données sur le portail puis télécharger le fichier.

En cas d'échec, voir [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md).
