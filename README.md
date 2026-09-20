# POC Observabilité Elastic

Ce dépôt fournit un environnement de recette pour observer une application
Java, Kafka, MongoDB, PostgreSQL et Kubernetes dans Elastic.

## Architecture

Les trois versions utilisent la même topologie minimale :

```text
data-01 : Kafka mono-broker · MongoDB standalone · PostgreSQL
    │
    ├─ v1 — Elastic classique : Filebeat/Metricbeat → Logstash → Elasticsearch
    ├─ v2 — OpenTelemetry + Kafka : EDOT Agent → Kafka OTLP → EDOT Collector → Elasticsearch
    └─ v3 — Hybride Fleet : Elastic Agent Fleet → Elasticsearch pour les VM

Applications Java sur Kubernetes
    ├─ v1 — Elastic classique : Agent Elastic APM → APM Server → Logstash
    ├─ v2 — OpenTelemetry + Kafka : Agent OpenTelemetry → Gateway EDOT → Kafka → Elasticsearch
    └─ v3 — Hybride Fleet : même flux applicatif/Kubernetes ; Fleet → Elasticsearch pour les VM
```

Le code Java, Maven et Docker est partagé. Les versions utilisent les mêmes
namespaces Kubernetes et ne doivent pas être déployées simultanément.

## Démarrage rapide

```bash
make architecture-switch VERSION=v3  # ou VERSION=v1 ou VERSION=v2
make architecture-list
make kubernetes-validate
export POSTGRESQL_PASSWORD='...'
make deploy
```

## Documentation

- [Guide de déploiement et d’exploitation](docs/deploiement-et-exploitation.md)
- [Architecture v1/v2/v3](docs/architecture-v1-v2-v3.md)
- [Métriques Kafka et MongoDB](docs/metrics-clients-kafka-mongodb.md)
- [Agent Package Manager](docs/agent-package-manager.md)

Les documentations proches des composants se trouvent dans `v3/`, `apps/`,
`kubernetes/` et `scripts/`. L’index complet est disponible dans
[`docs/README.md`](docs/README.md).

## Organisation

```text
v1/                    # Elastic 8, APM Server, Beats et Logstash
v2/                    # Elastic 9, EDOT et Kafka OTLP
apps/supermarket-demo/ # code Java, Docker et Maven partagé
docs/                  # documentation transversale et procédures
scripts/               # diagnostics partagés
```
