# Architecture : Hybride Fleet

Architecture de référence avec Elastic Stack `9.4.3`. Les applications,
Kubernetes et les VM utilisent OpenTelemetry/EDOT avec Kafka comme tampon. Le
cluster Kubernetes de référence est k3s sur `k3s-01` ; k3d reste disponible
uniquement pour la comparaison pendant la migration.
Les agents VM restent standalone et sont supervisés par Fleet via OpAMP, sans
policy Fleet de collecte concurrente.

## Topologie VM

```text
Kubernetes / opérateur
          |
          v
      otel-edge-01  -- OTLP
          |
          v
      otel-backend-01  -- Kafka OTel + backend OTel
          |
          v
      supermarket-middleware-01  -- Kafka métier + MongoDB + PostgreSQL

      supermarket-middleware-01  -- Kafka métier + MongoDB + PostgreSQL

      otel-backend-01  -- Kafka OTel + exporteur backend --> elk-01
                                                  Elasticsearch + Kibana + Fleet Server
```

`otel-edge-01` est le point d’entrée OTLP exposé. Les accès Kibana,
Elasticsearch, Fleet et APM sont directs vers `elk-01`. `otel-backend-01` héberge
le Kafka dédié OTel et le Collector backend, `supermarket-middleware-01` héberge les middlewares du
scénario et son Kafka métier, et `elk-01` porte le stockage et la consultation
Elastic.

Le code Java et les images sont partagés avec la plateforme. Le déploiement et
la recette sont décrits dans le README Ansible et les cibles du `Makefile`.
Pour migrer le cluster local k3d vers k3s, charger les identifiants puis
exécuter `make k3s-migrate`. Le kubeconfig généré reste local et non versionné.

Documents propres à l'architecture :

- [diagramme C4 interactif](https://elkouhen.github.io/systemlens-observability-lab/c4.html#/) ;
- [provisionnement des VM `supermarket-middleware-01`, `otel-backend-01`, `otel-edge-01` et `elk-01`](ansible/README.md) ;

La rétention des signaux et des logs est vérifiable avec
`make retention-verify`.
