# Architecture : Hybride Fleet

Architecture de référence avec Elastic Stack `9.4.3`. Les applications et
Kubernetes utilisent OpenTelemetry/EDOT avec Kafka comme
tampon. Les VM utilisent l’Elastic Agent enrôlé dans Fleet et envoient
directement leurs logs et métriques vers Elasticsearch.

## Topologie VM

```text
Kubernetes / opérateur
          |
          v
      otel-edge-01  -- OTLP, Kibana, Elasticsearch, Fleet
          |
          v
  otel-backend-01  -- exporteur Kafka EDOT
          |
          v
      poc-01  -- Kafka + MongoDB + PostgreSQL

      otel-edge-01  ------------------> elk-01
                                  Elasticsearch + Kibana + Fleet Server
```

`otel-edge-01` est le seul point d’entrée exposé. `otel-backend-01` traite les
signaux OTLP, `poc-01` héberge les middlewares du scénario et `elk-01` porte
le stockage et la consultation Elastic.

Le code Java et les images sont partagés avec la plateforme. Le déploiement et
la recette sont documentés dans le [guide central](../docs/deploiement-et-exploitation.md).

Documents propres à l'architecture :

- [plateforme Kubernetes et ELK](platform/README.md) ;
- [provisionnement des VM `poc-01`, `otel-backend-01`, `otel-edge-01` et `elk-01`](ansible/README.md) ;
- [dashboards et vérification](platform/elk/dashboards/README.md).

La [rétention des signaux et des logs](platform/elk/retention/README.md) décrit
les limites du POC et leur vérification avec `make retention-verify`.
