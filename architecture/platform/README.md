# Plateforme

Ce répertoire rassemble les composants transverses, indépendants du code des
applications. Pour ce POC, la plateforme Elastic est déployée sur `elk-01`,
le Collecteur EDOT Edge sur `otel-edge-01`, l'exporteur Kafka OTEL sur
`otel-backend-01` et l'exposition OTLP sur `otel-edge-01`. Les services Elastic
sont accessibles directement sur `elk-01`, avec des unités Quadlet ; Kubernetes
conserve les collecteurs OTel et le routage TLS Traefik optionnel.

## Parcours conseillé

1. Lire [`kubernetes/README.md`](kubernetes/README.md) pour le point d'entrée
   IaC Kustomize et les overlays d'environnement.
2. Lire [`elk/README.md`](elk/README.md) pour suivre le flux de télémétrie de
   bout en bout, puis `elk/fleet/`.
3. Consulter les scripts et dashboards une fois le déploiement compris.

Pour les flux APM et les contrôles communs aux applications et à Kubernetes,
consulter le [guide de déploiement](../../docs/deploiement-et-exploitation.md).

## Accès directs aux services Elastic

Les services Elastic sont publiés par `elk-01`, à l’adresse `192.168.33.40`.
`otel-edge-01` ne relaie pas les accès d’administration ; il expose uniquement
les endpoints OTLP `4317` et `4318`.

| Nom DNS | Port | Service |
| --- | ---: | --- |
| `elasticsearch.observability.test` | `9200` | Elasticsearch |
| `kibana.observability.test` | `5601` | Kibana |
| `fleet.observability.test` | `8220` | Fleet Server |
| `apm.observability.test` | `8200` | APM Server |

Depuis une machine qui ne possède pas encore cette résolution, ajouter la
ligne suivante à `/etc/hosts` :

```text
192.168.33.40 kibana.observability.test elasticsearch.observability.test fleet.observability.test apm.observability.test
```

## Licence Elastic

La licence du stack Elastic est gérée directement par Elasticsearch sur
`elk-01`. Aucun opérateur ECK, Secret de licence ou ressource Elastic
applicative n'est déployé dans Kubernetes architecture.

## Documentation externe

- [Panorama des options de déploiement Elastic](https://www.elastic.co/docs/deploy-manage/deploy)
- [Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
