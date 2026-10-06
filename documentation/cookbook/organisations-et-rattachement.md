# Comment déclarer une organisation productrice et la rattacher à un nœud ?

_Cas d'usage_ : mon nœud producteur est déployé ; je veux que ses jeux de
données soient publiés au nom d'une organisation, ce que le portail exige
(kalim refuse une métadonnée dont l'organisation productrice lui est inconnue).

---

## Notions

| Notion | Où | Rôle |
|--------|----|------|
| **Organisation** | strukture | Producteur de données ou porteur de réutilisations, avec ses membres. Visible sur le portail une fois validée |
| **Fournisseur / nœud** | strukture | Le nœud producteur déclaré dans le portail, avec son compte ROBOT (voir [Nœud producteur](./configuration-producer-node.md)) |
| **Rattachement** (*linked producer*) | strukture | Lien qui autorise un nœud à publier pour une organisation |

Chaque étape passe par un **workflow** : une demande est créée, puis validée par
un **animateur** (rôle `MODERATOR`) dans **« Mes notifications »** du portail.

| Workflow | Demandé par | Validé par | Actions |
|----------|-------------|------------|---------|
| Création d'organisation | Nœud (manager) ou utilisateur du portail | Animateur | Accepter / Refuser |
| Archivage d'organisation | Administrateur de l'organisation | Animateur | Accepter / Refuser |
| Rattachement | Nœud (manager) | Animateur | Accepter / Refuser |
| Détachement | Nœud (manager) | Animateur | Accepter / Refuser |

Chaque workflow a son équivalent dans la [collection Bruno](./utiliser-bruno.md)
(dossiers `20 Organisations` et `30 Nœud producteur`).

---

## Étape 1 — Disposer d'un animateur

Les demandes ne sont proposées qu'aux comptes ayant le rôle `MODERATOR`
(« Animateur »). Le plus simple est de le donner à l'administrateur créé à
l'étape 14 de [roob-to-prod.md](./roob-to-prod.md) :

**Option A — Bruno** : `10 Comptes/02 Utilisateurs`, requêtes « Rechercher un
utilisateur par login » (avec `USER_LOGIN` = le compte), « Consulter un
utilisateur », « Lister les rôles », puis « Ajouter un rôle à un utilisateur »
(`ROLE_TO_ADD=MODERATOR`).

**Option B — SQL** :

```bash
docker exec rudiplatform-database-1 psql -U rudi -d rudi -c "
INSERT INTO acl_data.user_role (user_fk, role_fk)
SELECT u.id, r.id FROM acl_data.user_ u, acl_data.role r
WHERE u.login = 'admin@mondomaine.fr' AND r.code = 'MODERATOR'
  AND NOT EXISTS (SELECT 1 FROM acl_data.user_role ur WHERE ur.user_fk = u.id AND ur.role_fk = r.id);"
```

Se reconnecter au portail pour que le rôle soit pris en compte.

---

## Étape 2 — Déclarer l'organisation

### Option A — Depuis le nœud producteur (recommandé)

1. Dans le manager du nœud (`https://<PRODUCER_DOMAIN>/manager/`), créer
   l'organisation et demander sa publication sur le portail.
2. Sur le portail, en animateur : **« Mes notifications »**, ouvrir la demande
   « Traitement de la demande de déclaration d'organisation », puis
   **« Accepter la demande »**.
3. Dans le manager, le statut de l'organisation passe à « validée ».

Bruno : `30 Nœud producteur/02 Organisation productrice (demande du nœud)`.

### Option B — Depuis le portail

Pour une organisation qui n'a pas de nœud (porteur de réutilisations) ou qui
sera rattachée ensuite :

1. Utilisateur connecté : **« Mon espace » > « Mes organisations »**, déclarer
   l'organisation (nom, description, image facultative).
2. Animateur : **« Mes notifications »**, accepter la demande. Le demandeur
   devient administrateur de l'organisation.

Bruno : `20 Organisations/01 Créer une organisation (portail)`.

> Si la fenêtre « Accepter la demande » ne propose que « Annuler », voir
> [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#portail--la-fenêtre--accepter-la-demande--ne-propose-que--annuler-).

---

## Étape 3 — Rattacher l'organisation au nœud

Indispensable pour qu'une organisation créée depuis le portail (option B)
puisse publier via le nœud. Une organisation demandée par le nœud (option A)
peut aussi être rattachée pour en confirmer le lien.

1. Dans le manager du nœud : rattacher un producteur de données, rechercher
   l'organisation publiée sur le portail (par identifiant ou par nom) et la
   sélectionner.
2. Animateur : **« Mes notifications »**, accepter la demande de rattachement.

Bruno : `30 Nœud producteur/03 Rattachement` (`ORGANIZATION_UUID` dans
`bruno/.env` pour une organisation existante). La dernière requête vérifie que
l'organisation est bien rattachée.

Le nœud peut ensuite publier des jeux de données dont le producteur est cette
organisation (voir [Cycle de vie des données](./cycle-de-vie-donnees.md)).

---

## Gérer les organisations

| Opération | Interface | Bruno |
|-----------|-----------|-------|
| Ajouter ou retirer un membre, changer son rôle (`ADMINISTRATOR` ou `EDITOR`) | Page de l'organisation, onglet administration (administrateur de l'organisation) | `20 Organisations/04 Membres` |
| Modifier la description | Page de l'organisation | `20 Organisations/03 Gérer les organisations` |
| Logo | Page de l'organisation | `20 Organisations/05 Logo et types d'adresses` |
| Archiver | « Mes organisations », archiver : les membres sont retirés ; les réutilisations restent visibles (`ARCHIVED`) ou sont archivées (`DISENGAGED`) | `20 Organisations/02 Archiver une organisation` |
| Détacher du nœud | Manager du nœud, puis validation par un animateur | `30 Nœud producteur/04 Détachement` |
| Supprimer définitivement | — (administrateur, API) | `20 Organisations/03 Gérer les organisations` |

Les **types d'adresses** (`/strukture/v1/addressRoles`) qualifient les adresses
des fournisseurs et organisations (contact, siège…). Le référentiel est vide sur
une installation neuve ; le compléter au besoin avec Bruno.

---

## Dépannage

| Symptôme | Cause | Voir |
|----------|-------|------|
| Aucune demande dans « Mes notifications » | Le compte n'a pas le rôle `MODERATOR` | Étape 1 |
| « Accepter la demande » ne propose que « Annuler » | Formulaire manquant en base (anomalie strukture) | [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#portail--la-fenêtre--accepter-la-demande--ne-propose-que--annuler-) |
| Erreur 500 « Node introuvable » à la validation | Login du compte ROBOT différent de l'UUID du nœud | [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#strukture---node-introuvable--à-la-validation-dune-demande-du-nœud-500) |
| Recherche d'organisation en erreur 401 dans le manager | `PORTAL_USER` du catalog vide ou erroné | [Nœud producteur](./configuration-producer-node.md) |
| Rapport d'intégration en erreur ERR_113 | Organisation productrice inconnue du portail | Étapes 2 et 3 |
