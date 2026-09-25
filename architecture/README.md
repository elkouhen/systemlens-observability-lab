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
      otel-edge-01  -- OTLP
          |
          v
      otel-backend-01  -- Kafka OTel + exporteur Kafka EDOT
          |
          v
      poc-01  -- Kafka métier + MongoDB + PostgreSQL

      otel-edge-01  ------------------> elk-01
                                  Elasticsearch + Kibana + Fleet Server
```

`otel-edge-01` est le point d’entrée OTLP exposé. Les accès Kibana,
Elasticsearch, Fleet et APM sont directs vers `elk-01`. `otel-backend-01` héberge le
Kafka dédié OTel et traite les signaux OTLP, `poc-01` héberge les middlewares
du scénario et son Kafka métier, et `elk-01` porte
le stockage et la consultation Elastic.

Le code Java et les images sont partagés avec la plateforme. Le déploiement et
la recette sont décrits dans le README Ansible et les cibles du `Makefile`.

Documents propres à l'architecture :

- [diagramme C4 interactif](https://elkouhen.github.io/systemlens-observability-lab/c4.html#/) ;
- [provisionnement des VM `poc-01`, `otel-backend-01`, `otel-edge-01` et `elk-01`](ansible/README.md) ;

La rétention des signaux et des logs est vérifiable avec
`make retention-verify`.
