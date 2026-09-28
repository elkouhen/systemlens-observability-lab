# ADR-005 : acheminer tous les signaux du backend vers le Kafka local

## Statut

Accepted, supersedes ADR-004

## Date

2026-09-28

## Contexte

`otel-backend-01` ne doit pas dépendre de la connectivité OTLP vers
`otel-edge-01`. Le broker Kafka OTel local et le backend OTel consomment
déjà les topics `otel-traces`, `otel-metrics` et `otel-logs`.

## Décision

L'agent EDOT de `otel-backend-01` publie directement ses métriques, logs,
traces et sa télémétrie interne dans le broker Kafka OTel local
(`127.0.0.1:9092`), avec l'encodage `otlp_proto`. Aucun pipeline de l'agent
backend n'utilise l'exporteur `otlphttp/edge`.

Le backend OTel consomme les trois topics et envoie les métriques et
logs vers Elasticsearch ainsi que les traces vers APM Server.

```text
EDOT backend → Kafka OTel local → backend OTel
                              ├── métriques + logs → Elasticsearch
                              └── traces → APM Server
```

La configuration reste standalone et versionnée dans Ansible. Fleet conserve
uniquement la supervision OpAMP.

## Alternatives considérées

### Conserver l'envoi des logs et traces vers Edge

Cette option est écartée car elle conserve une dépendance réseau inutile pour
le backend et contredit l'objectif d'un chemin local complet.

### Ajouter un collecteur local distinct

Cette option est écartée car l'agent EDOT sait publier les trois types de
signaux dans Kafka et l'exporteur existant sait déjà les consommer.

## Conséquences

- aucun signal produit par l'agent backend ne dépend d'Edge ;
- les topics `otel-traces`, `otel-metrics` et `otel-logs` deviennent le contrat
  local de production et d'export ;
- le broker Kafka local devient une dépendance directe de l'agent backend pour
  tous ses signaux ;
- la recette doit vérifier les trois topics et la présence des données
  correspondantes dans Elasticsearch et APM Server.

## Références

- [`ansible/roles/elastic_agent/templates/elastic-agent.yml.j2`](../ansible/roles/elastic_agent/templates/elastic-agent.yml.j2)
- [`ansible/roles/otel_backend/templates/otel-backend.yaml.j2`](../ansible/roles/otel_backend/templates/otel-backend.yaml.j2)
- [`ansible/README.md`](../ansible/README.md)
- [`docs/ADR-004-metrics-backend-vers-kafka-local.md`](ADR-004-metrics-backend-vers-kafka-local.md)
