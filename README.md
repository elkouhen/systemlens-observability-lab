# POC Observabilité Elastic

Ce dépôt fournit un environnement de recette pour observer une application
Java, Kafka, MongoDB, PostgreSQL et Kubernetes dans Elastic.

## Architecture

L'architecture conservée utilise la topologie suivante :

```text
data-01 : Kafka mono-broker · MongoDB standalone · PostgreSQL
    │
    └─ v3 — Hybride Fleet : Elastic Agent Fleet → Elasticsearch pour les VM

Applications Java sur Kubernetes
    └─ v3 — Hybride Fleet : OpenTelemetry/EDOT pour les applications et Kubernetes ; Fleet pour les VM
```

Le code Java, Maven et Docker est partagé. L'architecture utilise les namespaces
Kubernetes `elastic-stack` et `h0tl-supermarche-app`.

## Démarrage rapide

```bash
make architecture-switch VERSION=v3
make architecture-list
make kubernetes-validate
export POSTGRESQL_PASSWORD='...'
make deploy
```

## Documentation

- [Guide de déploiement et d’exploitation](docs/deploiement-et-exploitation.md)
- [Architecture v3](v3/README.md)
- [Métriques Kafka et MongoDB](docs/metrics-clients-kafka-mongodb.md)
- [Agent Package Manager](docs/agent-package-manager.md)

Les documentations proches des composants se trouvent dans `v3/`, `apps/`,
`kubernetes/` et `scripts/`. L’index complet est disponible dans
[`docs/README.md`](docs/README.md).

## Organisation

```text
v3/                    # Hybride Fleet, EDOT et Kafka OTLP
apps/supermarket-demo/ # code Java, Docker et Maven partagé
docs/                  # documentation transversale et procédures
scripts/               # diagnostics partagés
```
