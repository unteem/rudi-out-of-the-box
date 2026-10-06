# Comment fonctionnent les réutilisations sur le portail RUDI ?

_Cas d'usage_ : je veux déclarer et publier une réutilisation (application,
traitement de données…), lui donner accès à des jeux de données restreints et
accéder aux données par API ; ou, en tant qu'animateur ou producteur, traiter
les demandes associées.

---

## Notions et rôles

Une **réutilisation** (appelée *projet* dans l'API `projekt`) décrit un usage
des données : titre, description, type, échelle, public cible, jeux de données
mobilisés. Elle appartient à un utilisateur ou à une organisation.

| Demande | Faite par | Traitée par | Actions |
|---------|-----------|-------------|---------|
| Publication d'une réutilisation | Porteur | Animateur (`MODERATOR`) | `ok` (publier) / `refused` |
| Modification d'une réutilisation publiée | Porteur | Animateur | `ok` / `refused` |
| Accès à un jeu de données **restreint** | Porteur (réutilisation validée) | Membre de l'organisation productrice | `validated` / `canceled` |
| Nouvelles données (jeu qui n'existe pas encore) | Porteur | Animateur | `done` / `refused`, puis `close` |
| Archivage | Porteur | — (immédiat) | — |

Les demandes à traiter apparaissent dans **« Mes notifications »** du portail.
Chaque parcours a son équivalent dans le dossier `50 Réutilisations` de la
[collection Bruno](./utiliser-bruno.md).

---

## Prérequis

- **Listes de référence** (type de réutilisation, échelle, public cible,
  accompagnement) : `scripts/init-projekt.sh`, étape 16 de
  [roob-to-prod.md](./roob-to-prod.md). Sans elles, les listes déroulantes du
  formulaire sont vides.
- **Un animateur** (rôle `MODERATOR`) : voir
  [Organisations et rattachement](./organisations-et-rattachement.md#étape-1--disposer-dun-animateur).
- **SMTP** configuré pour que porteurs et animateurs soient notifiés
  ([configuration-mail.md](./configuration-mail.md)).

---

## Déclarer et publier une réutilisation

1. Utilisateur connecté : **« Déclarer une réutilisation »**, renseigner le
   formulaire, mobiliser des jeux de données (ouverts ou restreints),
   éventuellement demander de nouvelles données, ajouter une image.
2. Soumettre : la demande part chez les animateurs.
3. Animateur : **« Mes notifications »**, accepter (la réutilisation est publiée
   dans le catalogue) ou refuser avec un message (le porteur peut corriger et
   soumettre de nouveau).

Bruno : `50 Réutilisations/01 Déclarer une réutilisation` (création, logo, jeu
ouvert, soumission, validation). Le jeu mobilisé est `globalId` ou
`DATASET_GLOBAL_ID`.

Confidentialité « Privé » : la réutilisation n'apparaît pas dans le catalogue ;
seuls le porteur, les animateurs et les producteurs des jeux mobilisés la voient.

---

## Accéder à un jeu de données restreint

Un jeu restreint (`restricted_access`) n'est téléchargeable que par les
réutilisations auxquelles son producteur a accordé l'accès.

1. Porteur d'une réutilisation **validée** : mobiliser le jeu restreint,
   préciser l'usage et la date de fin d'accès souhaitée.
2. Membre de l'organisation productrice : **« Mes notifications »**, accepter
   ou refuser la demande d'accès, avec un commentaire.
3. Le porteur consulte la décision dans sa réutilisation.

Bruno : `50 Réutilisations/02 Demander l'accès à un jeu restreint` (compte
`MEMBER_LOGIN` pour l'organisation productrice).

Le fichier d'un jeu restreint est chiffré par le nœud avec la clé publique du
portail ; l'apigateway le déchiffre pour les réutilisations autorisées (voir
[Cycle de vie des données](./cycle-de-vie-donnees.md)).

---

## Demander de nouvelles données

Depuis une réutilisation, le porteur décrit des données qui n'existent pas sur
le portail. Un animateur traite la demande (`done` : prise en charge, ou
`refused`), puis la clôture.

Bruno : `50 Réutilisations/03 Demander de nouvelles données`.

---

## Modifier, archiver

- **Modifier** une réutilisation publiée : **« Mon espace » > « Mes projets »**,
  modifier ; la modification est appliquée après validation par un animateur.
  Bruno : `50 Réutilisations/04 Modifier une réutilisation publiée`.
- **Archiver** : depuis la même page ; la réutilisation n'est plus visible dans
  le catalogue. Bruno : `50 Réutilisations/05 Archiver une réutilisation`.
- Une réutilisation encore en brouillon peut être supprimée ; jeux mobilisés et
  logo se gèrent depuis sa page (Bruno : `06 Consulter et gérer`).

---

## Accéder aux données par API

Une application qui réutilise les données s'authentifie avec une **clé d'API**
de sa réutilisation :

1. Porteur : dans la réutilisation, créer une clé (nom, date d'expiration ; le
   mot de passe du compte est demandé). Le `client_secret` n'est affiché
   qu'une fois.
2. L'application obtient un jeton OAuth2 :

   ```bash
   TOKEN=$(curl -s -u "$CLIENT_ID:$CLIENT_SECRET" \
     -d grant_type=client_credentials \
     https://rudi.mondomaine.fr/oauth2/token | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
   ```

3. Puis télécharge les fichiers (jeux ouverts, ou restreints dont l'accès a
   été accordé) :

   ```bash
   curl -H "Authorization: Bearer $TOKEN" -o donnees.csv \
     https://rudi.mondomaine.fr/medias/<global_id>/<media_id>/dwnl
   ```

Bruno : `60 Accès API/01 Clé d'API d'un projet`. Les API exposées par
l'apigateway (une par média) et les limitations de débit se consultent dans
`60 Accès API/02 API exposées (administration)`.

---

## Dépannage

| Symptôme | Cause | Voir |
|----------|-------|------|
| Listes déroulantes vides dans le formulaire | Listes de référence projekt absentes | [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#listes-déroulantes-vides-dans-le-formulaire-de-réutilisation) |
| Aucune demande dans « Mes notifications » | Rôle `MODERATOR` absent, ou compte non membre de l'organisation productrice (jeu restreint) | [Organisations et rattachement](./organisations-et-rattachement.md) |
| Fenêtre d'action sans bouton de validation | Formulaire manquant en base | [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#portail--la-fenêtre--accepter-la-demande--ne-propose-que--annuler-) (schéma `projekt_data`) |
| Téléchargement refusé (401/403) | Jeton absent ou expiré, ou accès au jeu restreint non accordé | Sections ci-dessus |
