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

Les CRD ECK et Traefik restent des prérequis de bootstrap du cluster. Les
secrets ne sont volontairement pas stockés ici : ils doivent être fournis par
un gestionnaire de secrets (SOPS ou External Secrets) avant un déploiement
GitOps autonome.
