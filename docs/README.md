# Documentation système

Ce répertoire contient les documents transverses du POC. La documentation
opérationnelle la plus proche d'un composant reste sa source de vérité : lire
`platform/README.md`, `apps/README.md` ou `ansible/README.md` avant toute
modification.

Pour commencer, suivre le [guide de déploiement et d'exploitation](deploiement-et-exploitation.md).

## Comprendre les variantes

- [`v1-v2-en-bref.md`](v1-v2-en-bref.md) : orientation rapide et choix d'une
  version.
- [`architecture-v1-v2-differences.md`](architecture-v1-v2-differences.md) :
  comparaison historique des différences v1/v2.
- [`architecture-v1-v2-v3.md`](architecture-v1-v2-v3.md) : architecture v3
  hybride avec Fleet pour les VM.
- [`observability-flows-v1-v2.md`](observability-flows-v1-v2.md) : schémas
  historiques détaillés des flux v1/v2.

## Référence spécialisée

- [`apm-application-kubernetes.md`](apm-application-kubernetes.md) : APM de la
  v1 côté applications Java et Kubernetes.
- [`metrics-clients-kafka-mongodb.md`](metrics-clients-kafka-mongodb.md) :
  instrumentation des clients Kafka/MongoDB et métriques Actuator.
- [`prd-observabilite-elk.md`](prd-observabilite-elk.md) : objectifs,
  périmètre et critères d'acceptation du POC.

## Revue du dépôt

- [`diff-code-v1-v2.md`](diff-code-v1-v2.md) : différences de code et
  priorités de mutualisation. Ce document ne remplace pas le comparatif
  fonctionnel.
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
