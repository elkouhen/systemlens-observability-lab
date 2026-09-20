# Plateforme

Ce répertoire rassemble les composants transverses, indépendants du code des
applications. Pour ce POC, la plateforme Elastic est déployée sur `elk-01`,
le Gateway OTLP dans Kubernetes, l'exporteur Kafka OTEL sur
`otel-backend-01` et l'exposition sur `otel-edge-01`.
avec des unités Quadlet ; Kubernetes conserve les collecteurs OTel et le
routage TLS Traefik.

## Parcours conseillé

1. Lire [`kubernetes/README.md`](kubernetes/README.md) pour le point d'entrée
   IaC Kustomize et les overlays d'environnement.
2. Lire [`elk/README.md`](elk/README.md) pour suivre le flux de télémétrie de
   bout en bout, puis `elk/fleet/`.
3. Consulter les scripts et dashboards une fois le déploiement compris.

Pour les flux APM et les contrôles communs aux applications et à Kubernetes,
consulter la [référence des architectures](../../docs/architecture-v1-v2-v3.md)
et le [guide de déploiement](../../docs/deploiement-et-exploitation.md).

## Licence Elastic

La licence du stack Elastic est gérée directement par Elasticsearch sur
`elk-01`. Aucun opérateur ECK, Secret de licence ou ressource Elastic
applicative n'est déployé dans Kubernetes v3.

## Documentation externe

- [Panorama des options de déploiement Elastic](https://www.elastic.co/docs/deploy-manage/deploy)
- [Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
