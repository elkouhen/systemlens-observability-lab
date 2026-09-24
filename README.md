# POC d’observabilité Elastic

Ce dépôt fournit un environnement Kubernetes et Vagrant pour observer une
application Java avec Elastic, OpenTelemetry, Kafka, MongoDB et PostgreSQL.
L’architecture active est l’architecture « Hybride Fleet ».

## Commencer ici

Pour déployer l’environnement local :

```bash
make architecture-status
make kubernetes-validate
export POSTGRESQL_PASSWORD='...'
make vms-start
make vm-status
make architecture-deploy
```

`make vms-start` démarre les quatre VM en parallèle, puis provisionne leurs rôles
avec un seul playbook Ansible parallèle. Après le contrôle `make vm-status`,
`make architecture-deploy` déploie la plateforme Elastic, Fleet,
Kubernetes et l'application.

Le [guide de déploiement et d’exploitation](docs/deploiement-et-exploitation.md)
décrit les prérequis, l’ordre des opérations et la recette fonctionnelle.

## Architecture active

```text
Applications Java et pods Kubernetes
    -> EDOT Kubernetes -> Kafka -> Collector backend -> Elasticsearch -> Kibana

VM de données
    -> Elastic Agent EDOT -> Collecteur Edge -> Kafka -> Collector backend -> Elasticsearch -> Kibana
```

La plateforme conserve les namespaces Kubernetes `elastic-stack` et
`h0tl-supermarche-app`. La description complète des flux se trouve dans
[`docs/architecture.md`](docs/architecture.md).

## Parcours documentaire

- [Documentation système](docs/README.md) : index des procédures et références
  transverses.
- [Architecture](architecture/README.md) : topologie et points d’entrée de la
  plateforme active.
- [Applications](apps/README.md) : code, images et manifests des workloads.
- [Plateforme](architecture/platform/README.md) : Kubernetes, Elastic et Fleet.
- [Provisionnement des VM](architecture/ansible/README.md) : Ansible, rôles et services.

Chaque sous-système conserve les procédures détaillées dans son README local.
Ces documents sont la source de vérité pour les commandes et les fichiers du
composant concerné.

## Organisation du dépôt

```text
architecture/          # plateforme et provisionnement de l’architecture active
apps/supermarket-demo/ # code Java, Docker et tests Maven
kubernetes/            # manifests applicatifs partagés
docs/                  # procédures et références transverses
scripts/               # diagnostics partagés
certs/                 # certificats locaux et prérequis TLS
```

## Validation sans déploiement

```bash
make ci-run
```

Cette cible valide le rendu Kustomize, la syntaxe Ansible et les tests Maven.
