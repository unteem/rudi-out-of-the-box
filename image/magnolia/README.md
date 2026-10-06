# Magnolia CMS — Image RUDI

Image Docker basée sur `tomcat:9-jdk11-temurin` intégrant :

- **Magnolia Community Webapp** `6.2.40` — téléchargé au build depuis le Nexus public Magnolia
- **Module RUDI** (`modules-rudi/`) — templates FTL, définitions YAML, endpoints REST delivery
- **Contenu de structure RUDI** (`content/structure/`) — catégories, pages de rendu, rôles et groupes,
  importés au premier démarrage par le module Content Importer ; produit par `scripts/magnolia-export.sh`
  (voir `documentation/cookbook/configuration-magnolia.md`)
- **PostgreSQL JDBC driver** `42.2.18` — téléchargé au build depuis Maven Central

## Construire l'image

```bash
docker compose -f docker-compose-magnolia.yml build magnolia
```

## Montée de version Magnolia

Modifier `ARG MAGNOLIA_VERSION` dans le Dockerfile :

```dockerfile
ARG MAGNOLIA_VERSION=6.2.40
```

Vérifier la disponibilité de la version sur le Nexus Magnolia :
https://nexus.magnolia-cms.com/service/rest/repository/browse/magnolia.public.releases/info/magnolia/bundle/magnolia-community-webapp/

## TODO

- Passer en 6.2.72 ou plus : cette version introduit
  `magnolia.superuser.bootstrap.password_file`, qui permettrait de définir le
  mot de passe `superuser` dès le premier démarrage (secret généré par
  `deploy.sh`) au lieu de le changer à la main.

## Liens utiles

- https://docs.magnolia-cms.com/headless/index.html
- https://git.magnolia-cms.com/repos?visibility=public
