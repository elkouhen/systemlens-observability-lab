# POC Observabilité Elastic

Ce dépôt fournit un environnement de recette pour observer une application
Java, Kafka, MongoDB, PostgreSQL et Kubernetes dans Elastic.

## Architecture

Les deux versions utilisent la même topologie minimale :

```text
data-01 : Kafka mono-broker · MongoDB standalone · PostgreSQL
    │
    ├─ v1 : Filebeat/Metricbeat → Logstash → Elasticsearch
    └─ v2 : EDOT Agent → Kafka OTLP → EDOT Collector → Elasticsearch

Applications Java sur Kubernetes
    ├─ v1 : Agent Elastic APM → APM Server → Logstash
    └─ v2 : Agent OpenTelemetry → Gateway EDOT → Kafka → Elasticsearch
```

Le code Java, Maven et Docker est partagé. Les versions utilisent les mêmes
namespaces Kubernetes et ne doivent pas être déployées simultanément.

## Démarrage rapide

```bash
make architecture-switch VERSION=v1  # ou VERSION=v2
make kubernetes-validate
export POSTGRESQL_PASSWORD='...'
make deploy
```

## Documentation

- [Guide de déploiement et d’exploitation](docs/deploiement-et-exploitation.md)
- [Comparaison fonctionnelle v1/v2](docs/architecture-v1-v2-differences.md)
- [Schémas des flux d’observabilité](docs/observability-flows-v1-v2.md)
- [Revue des différences de code et de la mutualisation](docs/diff-code-v1-v2.md)
- [Résumé v1/v2](docs/v1-v2-en-bref.md)
- [Objectifs et périmètre du POC](docs/prd-observabilite-elk.md)
- [APM des applications Java et Kubernetes](docs/apm-application-kubernetes.md)
- [Métriques Kafka et MongoDB](docs/metrics-clients-kafka-mongodb.md)

Les documentations proches des composants se trouvent dans `v1/`, `v2/`,
`apps/` et `scripts/`. L’index complet est disponible dans
[`docs/README.md`](docs/README.md).

## Organisation

```text
v1/                    # Elastic 8, APM Server, Beats et Logstash
v2/                    # Elastic 9, EDOT et Kafka OTLP
apps/supermarket-demo/ # code Java, Docker et Maven partagé
docs/                  # documentation transversale et procédures
scripts/               # diagnostics partagés
```
