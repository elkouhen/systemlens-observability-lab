# Diagramme C4

Le [site GitHub Pages](https://elkouhen.github.io/systemlens-observability-lab/)
présente une page d’accueil qui renvoie vers le diagramme C4 interactif et les
ADR. Le diagramme est construit à partir de la source [LikeC4](architecture-c4.likec4)
et présente les vues d'architecture, de flux métier et de télémétrie avec leur
navigation native.

Le site est reconstruit par GitHub Actions après chaque modification de la
source LikeC4 sur `main`. La commande locale équivalente est :

```bash
make c4-pages-build C4_PAGES_BASE=./
```

Le résultat est généré dans `dist/c4/`. Ce répertoire est un artefact local et
n'est pas versionné.

## Vues disponibles

- `architecture` : vue C4 des conteneurs et des trois zones réseau ;
- `business-flow` : parcours des requêtes et événements métier ;
- `observability-flow` : collecte, bufferisation et export des signaux ;
- `signals-flow` : chemin séparé des logs, métriques et traces.
