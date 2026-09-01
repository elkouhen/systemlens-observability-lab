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
  source de vérité pour les différences fonctionnelles et les flux.
- [`observability-flows-v1-v2.md`](observability-flows-v1-v2.md) : schémas
  détaillés des flux APM, VM, Kubernetes et logs.

## Référence spécialisée

- [`apm-application-kubernetes.md`](apm-application-kubernetes.md) : APM de la
  v1 côté applications Java et Kubernetes.
- [`metrics-clients-kafka-mongodb.md`](metrics-clients-kafka-mongodb.md) :
  instrumentation des clients Kafka/MongoDB et métriques Actuator.
- [`prd-poc-observabilite-elk.md`](prd-poc-observabilite-elk.md) : objectifs,
  périmètre et critères d'acceptation du POC.

## Revue du dépôt

- [`diff-code-v1-v2.md`](diff-code-v1-v2.md) : différences de code et
  priorités de mutualisation. Ce document ne remplace pas le comparatif
  fonctionnel.

Les procédures propres à un composant restent dans son README local ; elles
ne sont pas recopiées ici.

## Vérification reproductible

Depuis la racine du dépôt, exécuter :

```bash
make ci
```

Le résultat attendu est un rendu Kustomize valide et l'exécution des tests
Maven. Cette commande ne déploie aucune ressource.
