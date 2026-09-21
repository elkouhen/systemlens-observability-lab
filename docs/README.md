# Documentation système

Ce répertoire contient les procédures et les références communes au dépôt.
Les README des composants restent propriétaires de leur configuration et de
leurs commandes détaillées.

## Parcours recommandé

1. Lire le [guide de déploiement et d’exploitation](deploiement-et-exploitation.md)
   pour préparer l’environnement et choisir la commande adaptée.
2. Lire l’[architecture v3](architecture-v3.md) pour comprendre les flux de
   télémétrie et les responsabilités des VM et du cluster.
3. Consulter les README de la [plateforme v3](../v3/platform/README.md), des
   [applications](../apps/README.md) ou du [provisionnement](../v3/ansible/README.md)
   avant de modifier un composant.

## Opérer l’environnement

- [Déploiement et exploitation](deploiement-et-exploitation.md) : prérequis,
  déploiement, vérifications et dépannage.
- [Architecture v3](architecture-v3.md) : topologie, flux et validations.
- [Spécification fonctionnelle v3](specification-fonctionnelle-v3.md) :
  capacités attendues et critères d’acceptation.
- [Spécification technique v3](specification-technique-v3.md) : composants,
  interfaces, contraintes et contrôles techniques.
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie-v3.md) :
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
