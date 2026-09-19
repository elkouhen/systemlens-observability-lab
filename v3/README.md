# v3 — Hybride Fleet

Variante hybride de référence avec Elastic Stack `9.4.3`. Les applications et
Kubernetes conservent le chemin OpenTelemetry/EDOT de la v2 avec Kafka comme
tampon. Les VM utilisent l’Elastic Agent enrôlé dans Fleet et envoient
directement leurs logs et métriques vers Elasticsearch.

## Topologie VM

```text
Kubernetes / opérateur
          |
          v
      edge-01  -- OTLP, Kibana, Elasticsearch, Fleet
          |
          v
  otel-backend-01  -- exporteur Kafka EDOT
          |
          v
      poc-01  -- Kafka + MongoDB + PostgreSQL

      edge-01  ------------------> elk-01
                                  Elasticsearch + Kibana + Fleet Server
```

`edge-01` est le seul point d’entrée exposé. `otel-backend-01` traite les
signaux OTLP, `poc-01` héberge les middlewares du scénario et `elk-01` porte
le stockage et la consultation Elastic.

Le code Java et les images restent partagés avec la v1. Le déploiement, la
bascule de version et la recette sont documentés dans le
[guide central](../docs/deploiement-et-exploitation.md). La comparaison des
flux est dans la [documentation des architectures](../docs/architecture-v1-v2-v3.md).

Documents propres à la v3 :

- [plateforme Kubernetes et ELK](platform/README.md) ;
- [provisionnement des VM `poc-01`, `otel-backend-01`, `edge-01` et `elk-01`](ansible/README.md) ;
- [dashboards et vérification](platform/elk/dashboards/README.md).

La [rétention des signaux et des logs](platform/elk/retention/README.md) décrit
les limites du POC et leur vérification avec `make retention-verify`.
