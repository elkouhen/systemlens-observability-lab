# Kubernetes IaC

Ce répertoire est le point d'entrée déclaratif de la plateforme Kubernetes.

- `base/observability/` contient toutes les ressources Elastic, OpenTelemetry,
  Fleet et la collecte des logs Kubernetes.
- `overlays/local/` décrit l'environnement POC local. Les futurs environnements
  (`recette`, `production`) seront des overlays distincts, sans duplication des
  ressources de base.

Déployer l'environnement local :

```bash
kubectl apply -k platform/kubernetes/overlays/local
```

Les CRD ECK, Traefik et Elasticsearch restent des prérequis de bootstrap du
cluster. Dans l'environnement actuel, Elasticsearch est possédé par la release
Helm `es-kb-quickstart` ; il est donc volontairement exclu de ce bundle pour
éviter deux contrôleurs de cycle de vie sur la même ressource. Les secrets ne
sont pas stockés ici : ils doivent être fournis par un gestionnaire de secrets
(SOPS ou External Secrets) avant un déploiement GitOps autonome.

Pour un Elasticsearch déjà existant, la configuration de stockage ne doit pas
être ajoutée rétrospectivement : ECK interdit ce changement. Prévoir une
migration dédiée par snapshot/restauration vers un nouveau cluster avec ses
`volumeClaimTemplates` déclarés dès la création.
