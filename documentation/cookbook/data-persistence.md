# Comment faire persister mes données (RUDI, Dataverse, Magnolia) ?

_Cas d'usage_ : lorsque je fais des opérations sur mon environnement ROOB, je veux qu'elles persistent même si je supprime les containers de ROOB.

La persistance est activée par défaut : les données sont stockées dans des répertoires de l'hôte montés dans les conteneurs.

| Donnée | Répertoire hôte |
|--------|-----------------|
| Base RUDI (`database`) | `./database-data/rudi` |
| Base Dataverse (`dataverse-database`) | `./database-data/dataverse` |
| Base Magnolia (`magnolia-database`) | `./database-data/magnolia` |
| Index Solr | `./data/solr/solr-data` |
| Contenu Magnolia (JCR) | `./data/magnolia/repository` |
| Fichiers Dataverse | `./data/dataverse/dataverse-files` |

Les données survivent aux `docker compose down` et aux redémarrages de conteneurs.

> **Note** : les scripts d'initialisation de `config/rudi-init/` ne sont exécutés par PostgreSQL que sur un répertoire de données vide (premier démarrage). Ensuite, ils sont ignorés.

> **Montée de version** : une montée de version majeure de PostgreSQL nécessite une migration des données. Faire une sauvegarde avant toute mise à jour (voir [roob-to-prod.md](./roob-to-prod.md#persistance-et-sauvegardes)).

## Réinitialiser les données

Pour repartir d'un état vierge (**supprime toutes les données**) :

```bash
docker compose -f docker-compose-magnolia.yml -f docker-compose-rudi.yml \
               -f docker-compose-dataverse.yml -f docker-compose-network.yml \
               --profile "*" down

sudo rm -rf database-data/* data/solr/solr-data/* data/magnolia/repository/* data/dataverse/dataverse-files/*
```

Les secrets (`.env`) et keystores (`config/*/*.jks`) sont conservés. Reprendre ensuite le déploiement à l'étape 8 de [roob-to-prod.md](./roob-to-prod.md#étape-8--démarrer-les-bases-de-données).
