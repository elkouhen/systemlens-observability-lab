# Documentation système

Ce répertoire contient les documents transverses du POC. La documentation
opérationnelle la plus proche d'un composant reste sa source de vérité : lire
`platform/README.md`, `apps/README.md` ou `ansible/README.md` avant toute
modification.

Pour commencer, suivre le [guide de déploiement et d'exploitation](deploiement-et-exploitation.md).

## Comprendre l'architecture

- [`architecture-v1-v2-v3.md`](architecture-v1-v2-v3.md) : architectures
  disponibles et flux de la v3 hybride avec Fleet pour les VM.
- [`gestion-du-debit-observabilite.md`](gestion-du-debit-observabilite.md) :
  rate limiting, sampling, backpressure et quotas par type de flux.
- [`briques-remontee-telemetrie.md`](briques-remontee-telemetrie.md) : briques,
  entrées, sorties et gestion de la pression pour les logs, traces et métriques.

## Référence spécialisée

- [`metrics-clients-kafka-mongodb.md`](metrics-clients-kafka-mongodb.md) :
  instrumentation des clients Kafka/MongoDB et métriques Actuator.

## Outils du dépôt

- [`agent-package-manager.md`](agent-package-manager.md) : installation et
  contrôle du contexte d'agents avec Microsoft APM.

Les procédures propres à un composant restent dans son README local ; elles
ne sont pas recopiées ici.

Pour la v3, la procédure de référence est : `make elk-deploy`, puis
`make fleet-vms-provision`, puis `make apps-deploy`. Le flux VM est visible dans
Fleet et dans les data streams Elasticsearch ; les flux applicatifs et
Kubernetes restent vérifiables via les topics OTLP et `otel-kafka-exporter`.

## Vérification reproductible

Depuis la racine du dépôt, exécuter :

```bash
make ci
```

Le résultat attendu est un rendu Kustomize valide et l'exécution des tests
Maven. Cette commande ne déploie aucune ressource.
