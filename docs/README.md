# Documentation système

Ce répertoire contient les procédures et les références communes au dépôt.
Les README des composants restent propriétaires de leur configuration et de
leurs commandes détaillées.

## Parcours recommandé

1. Lire le [guide de déploiement et d’exploitation](deploiement-et-exploitation.md)
   pour préparer l’environnement et choisir la commande adaptée.
2. Lire l’[architecture](architecture.md) pour comprendre les flux de
   télémétrie et les responsabilités des VM et du cluster.
3. Consulter les README de la [plateforme](../architecture/platform/README.md), des
   [applications](../apps/README.md) ou du [provisionnement](../architecture/ansible/README.md)
   avant de modifier un composant.

## Opérer l’environnement

- [Déploiement et exploitation](deploiement-et-exploitation.md) : prérequis,
  déploiement, vérifications et dépannage.
- [Architecture](architecture.md) : topologie, flux et validations.
- [Spécification fonctionnelle](specification-fonctionnelle.md) :
  capacités attendues et critères d’acceptation.
- [Spécification technique](specification-technique.md) : composants,
  interfaces, contraintes et contrôles techniques.
- [ADR-001 : adopter EDOT et OpenTelemetry](ADR-001-choix-elastic-agent-otel.md) :
  choix du plan de données OTLP et de la gateway.
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie.md) :
  sources, transport, destinations et fichiers IaC associés.
- [Gestion du débit de télémétrie](gestion-du-debit-observabilite.md) :
  limitation, échantillonnage, files et quotas.

## Références techniques

- [Métriques des clients Kafka et MongoDB](metrics-clients-kafka-mongodb.md) :
  instrumentation Java et exposition Actuator.
- [Agent Package Manager](agent-package-manager.md) : installation et audit du
  contexte d’agents déclaré par le projet.

## Validation reproductible

Depuis la racine du dépôt :

```bash
make ci
```

Le résultat attendu est un rendu Kustomize valide, une syntaxe Ansible valide
et le succès des tests Maven. Cette commande ne déploie aucune ressource.
