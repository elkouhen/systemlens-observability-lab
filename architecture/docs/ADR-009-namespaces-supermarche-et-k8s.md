# ADR-009 : séparer les namespaces de data stream `supermarche` et `k8s`

## Statut

Accepted

## Date

2026-11-02

## Contexte

Tous les signaux reçus par le collecteur Edge partaient dans les topics de
base et étaient écrits dans le namespace `default`. Les signaux des
applications `supermarket-demo`, ceux des collecteurs Kubernetes et ceux des
VM se mélangeaient donc dans les mêmes data streams.

[ADR-007](ADR-007-namespace-data-stream-par-topic.md) fournit le mécanisme :
le backend dérive `data_stream.namespace` du suffixe du topic
`otel-<signal>-<namespace>`. Il restait à choisir qui publie dans ces topics.

Le jeton OTLP ne distingue pas les émetteurs : les agents Java des
applications utilisent la même clé Edge que `otel-kubernetes-cluster`.

## Décision

Le collecteur Edge choisit le topic de chaque ressource. Cette décision amende
ADR-007, selon lequel l'Edge publiait uniquement dans les topics de base.

- Namespace `supermarche` : signaux dont la ressource porte
  `k8s.namespace.name` = `h0tl-supermarche-app`. Cela couvre les traces, les
  erreurs APM, les métriques Micrometer et JVM et les logs stdout des trois
  services.
- Namespace `k8s` : signaux des collecteurs `otel-kubernetes` et
  `otel-kubernetes-cluster`. Ils posent l'attribut de ressource
  `otel.edge.source=kubernetes` : `kubeletstats`, `k8s_cluster`,
  `hostmetrics` de `k3s-01` et leur propre télémétrie Prometheus.
- Namespace `default` : tout le reste (agents EDOT des VM, télémétrie des
  collecteurs Edge et backend, Fleet).
- Un log suit le namespace Kubernetes de son pod : la règle applicative passe
  avant le marqueur. Une métrique ou une trace suit son émetteur : le marqueur
  passe avant. Les métriques `kubeletstats` d'un pod applicatif vont donc dans
  `k8s`, ses logs stdout dans `supermarche`.
- Le processor `transform/kafka-topic` de l'Edge pose `otel.kafka.topic` ;
  l'exporteur Kafka le lit par `topic_from_attribute` et publie chaque
  ressource dans son topic. Une valeur envoyée par un client est d'abord
  supprimée. Le marqueur est supprimé par l'Edge, `otel.kafka.topic` par le
  backend : aucun des deux n'est indexé.
- Les règles sont des variables Ansible
  (`inventory/group_vars/otel_edge_nodes.yml`). Le job
  `otel-telemetry-topics` crée les six topics suffixés avec trois partitions
  et la rétention des topics de base.

## Alternatives considérées

- **Connector `routing` et un exporteur Kafka par topic** : aucun attribut
  technique transitoire, mais neuf pipelines au lieu de trois.
- **Distinguer les clients par leur jeton** : impossible tant que les
  applications partagent la clé de `otel-kubernetes-cluster`.
- **Poser `data_stream.namespace` dans chaque source** : rejeté par ADR-007,
  car la règle serait dispersée et Kafka ne séparerait pas les flux.

## Conséquences

- Les données antérieures au 2026-11-02 restent dans les data streams
  `*-default` jusqu'à leur expiration ILM. Une requête sur une période qui
  couvre la bascule doit viser `*-default` et le nouveau namespace.
- Les métriques APM agrégées par APM Server (`metrics-apm.*`) restent dans
  `default` : APM Server les calcule sans reprendre le namespace des traces
  sources. Les motifs `metrics-apm.<métrique>.<intervalle>-*` les trouvent
  toujours.
- Une nouvelle application obtient son namespace par une entrée de
  `otel_edge_application_routes` et trois topics dans le job
  `otel-telemetry-topics`.
- Les dashboards et data views fondés sur `metrics-*`, `logs-*` ou
  `traces-apm*` ne changent pas.

## Vérification

Après `make otel-edge-vm-provision` et `make kubernetes-observability-deploy`,
les traces et erreurs APM, les métriques `generic.otel` et les logs
`filelogreceiver` des trois services arrivent dans `*-supermarche`. Les
métriques `kubeletstatsreceiver`, `k8sclusterreceiver`,
`prometheusreceiver` et `hostmetricsreceiver` de `k3s-01` arrivent dans
`*-k8s`. Les signaux des VM restent dans `default`. Les contrôles
`trace-context-verify`, `observability-schema-verify`, `dashboards-verify` et
`kubernetes-otel-dashboards-verify` réussissent.
