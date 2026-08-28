# Documentation système

Ce répertoire contient les documents transverses du POC. La documentation
opérationnelle la plus proche d'un composant reste sa source de vérité : lire
`platform/README.md`, `apps/README.md` ou `ansible/README.md` avant toute
modification.

- [`prd-poc-observabilite-elk.md`](prd-poc-observabilite-elk.md) : objectifs,
  périmètre et critères d'acceptation du POC d'observabilité Elastic.
- [`apm-application-kubernetes.md`](apm-application-kubernetes.md) : impacts
  de l'APM côté applications Java et Kubernetes, avec points de vérification.
- [`metrics-clients-kafka-mongodb.md`](metrics-clients-kafka-mongodb.md) :
  consignes d'instrumentation des clients Kafka et MongoDB et de collecte via
  Actuator et Elastic Agent.

## Vérification reproductible

Depuis la racine du dépôt, exécuter :

```bash
make ci
```

Le résultat attendu est un rendu Kustomize valide et l'exécution des tests
Maven. Cette commande ne déploie aucune ressource.
