# Plateforme

Ce répertoire rassemble les composants transverses, indépendants du code des
applications. Pour ce POC, il contient la plateforme Elastic déployée sur
Kubernetes.

## Parcours conseillé

1. Lire [`kubernetes/README.md`](kubernetes/README.md) pour le point d'entrée
   IaC Kustomize et les overlays d'environnement.
2. Lire [`elk/README.md`](elk/README.md) pour suivre le flux de télémétrie de
   bout en bout, puis `elk/fleet/`.
3. Consulter les scripts et dashboards une fois le déploiement compris.

Pour les impacts et les contrôles APM communs aux applications et à
Kubernetes, consulter le [guide APM applications et Kubernetes](../docs/apm-application-kubernetes.md).

## Documentation externe

- [Panorama des options de déploiement Elastic](https://www.elastic.co/docs/deploy-manage/deploy)
- [Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
