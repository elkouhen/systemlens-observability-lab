# Documentation système

Ce répertoire contient les procédures et les références communes au dépôt.
Les README des composants restent propriétaires de leur configuration et de
leurs commandes détaillées.

## Parcours recommandé

1. Lire l’[architecture](architecture.md) pour comprendre les flux de
   télémétrie et les responsabilités des VM et du cluster.
2. Consulter le [README de l’architecture](../architecture/README.md), les
   [applications](../apps/README.md) ou le
   [provisionnement](../architecture/ansible/README.md)
   avant de modifier un composant.

## Opérer l’environnement

- [Architecture](architecture.md) : topologie, flux et validations.
- [Spécification fonctionnelle](specification-fonctionnelle.md) :
  capacités attendues et critères d’acceptation.
- [Spécification technique](specification-technique.md) : composants,
  interfaces, contraintes et contrôles techniques.
- [ADR-001 : choisir le chemin de données EDOT avec Kafka](../architecture/docs/ADR-001-choix-chemin-donnees-edot.md) :
  choix du plan de données OTLP et de la gateway.
- [ADR-002 : choisir la gestion EDOT standalone avec supervision Fleet](../architecture/docs/ADR-002-edot-standalone-ou-managed-by-fleet.md) :
  choix du mode de gestion des agents EDOT.
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie.md) :
  sources, transport, destinations et fichiers IaC associés.
- [Gestion du débit de télémétrie](gestion-du-debit-observabilite.md) :
  limitation, échantillonnage, files et quotas.

## Références techniques


## Validation reproductible

Depuis la racine du dépôt :

```bash
make ci
```

Le résultat attendu est un rendu Kustomize valide, une syntaxe Ansible valide
et le succès des tests Maven. Cette commande ne déploie aucune ressource.
