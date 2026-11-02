# ADR-010 : le dataset nomme l'application, le namespace l'environnement

## Statut

Accepted

Remplace la partie « nommage des data streams » de
[ADR-009](ADR-009-namespaces-supermarche-et-k8s.md). Le choix du topic Kafka
par le collecteur Edge (ADR-009) reste en vigueur.

## Date

2026-11-02

## Contexte

ADR-009 utilisait le namespace de data stream pour séparer les flux :
`traces-apm-supermarche`, `metrics-generic.otel-supermarche`,
`logs-filelogreceiver-supermarche`, `metrics-kubeletstatsreceiver.otel-k8s`.
La convention Elastic est inverse : le dataset décrit ce qui est collecté, le
namespace décrit où (environnement, équipe). Le namespace `supermarche`
masquait l'environnement `homologation` et le dataset `generic` ne disait pas
quelle application émettait.

## Décision

Le dataset nomme l'application ou la plateforme ; le namespace nomme
l'environnement. Les topics `otel-<signal>-supermarche` et
`otel-<signal>-k8s` d'ADR-009 sont conservés pour isoler les flux dans Kafka.

- **Dataset** : posé par le collecteur Edge, dans le processor
  `transform/kafka-topic`, sur les logs et métriques d'une route applicative
  (`otel_edge_application_routes[].data_stream_dataset`, ici `supermarche`).
  Les traces ne reçoivent aucun dataset : APM Server garde `apm` et
  `apm.error`, lus par l'UI APM et par SystemLens.
- **Namespace** : posé par le collecteur backend, dans
  `transform/data-stream-namespace`, pour tout topic suffixé. Il vaut
  `deployment.environment.name`, sinon `deployment.environment`, sinon
  `default`, normalisé en `[a-z0-9_]`. Les topics de base (VM, Edge, Fleet)
  ne changent pas.
- **Kubernetes** : les signaux des collecteurs Kubernetes gardent le dataset
  de leur receiver. Les 11 dashboards du package `kubernetes_otel` 2.6.1 et
  les dashboards `[OTel] Host` interrogent
  `metrics-kubeletstatsreceiver.otel-*`, `metrics-k8sclusterreceiver.otel-*`
  et `metrics-hostmetricsreceiver.otel-*`. Un dataset unique `k8s` les
  viderait, et ces dashboards sont gérés par Fleet, pas par ce dépôt.
- Les collecteurs Kubernetes posent `deployment.environment.name` =
  `homologation` (`resource/environment`, sans écraser une valeur de la
  source) : leurs métriques et les logs des pods applicatifs portent ainsi
  l'environnement.
- En mode de mapping OTel, l'exporteur Elasticsearch ajoute `.otel` au
  dataset des métriques ; les templates `metrics-*.otel-*` s'appliquent. Les
  logs sont en mode ECS : pas de suffixe.

| Signal | Data stream |
| --- | --- |
| Logs des services `supermarket-demo` | `logs-supermarche-homologation` |
| Métriques Micrometer et JVM | `metrics-supermarche.otel-homologation` |
| Traces | `traces-apm-homologation` |
| Erreurs APM | `logs-apm.error-homologation` |
| Métriques Kubernetes | `metrics-{kubeletstatsreceiver,k8sclusterreceiver,hostmetricsreceiver,prometheusreceiver}.otel-homologation` |
| Métriques APM agrégées | `metrics-apm.*.1m-default` (inchangé) |
| Signaux des VM | inchangés, namespace `default` |

## Alternatives considérées

- **Dataset unique `k8s` pour les collecteurs Kubernetes** : rejeté, les
  dashboards Fleet `[Kubernetes OTel]` et `[OTel] Host` ne trouveraient plus
  de données.
- **Le backend déduit le dataset du suffixe du topic** : le suffixe `k8s` ne
  doit pas devenir un dataset, et les traces doivent garder `apm`. La règle
  par route, posée par l'Edge à côté du choix du topic, reste plus lisible.

## Conséquences

- Le suffixe du topic n'est plus un namespace : il isole un flux routé dans
  Kafka et indique au backend d'appliquer l'environnement
  ([ADR-007](ADR-007-namespace-data-stream-par-topic.md), note du
  2026-11-02).
- Le dashboard métier, le data view APM et les contrôles
  `dashboards-verify` et `observability-schema-verify` lisent
  `metrics-supermarche.otel-*` et `logs-supermarche-*`.
- APM Server ne reprend pas le namespace des traces pour ses métriques
  agrégées : elles restent dans `default`. Les motifs
  `metrics-apm.<métrique>.<intervalle>-*` les trouvent toujours.
- Une nouvelle application déclare son dataset dans sa route Edge ; son
  namespace suit son `deployment.environment`.

## Vérification

Le 2026-11-02, après `make otel-edge-vm-provision`,
`make otel-backend-vm-provision` et `make kubernetes-observability-deploy`,
les data streams du tableau reçoivent les nouveaux documents. Les data streams
`*-supermarche` et `*.otel-k8s` ne reçoivent plus rien. Les contrôles
`trace-context-verify`, `observability-schema-verify`, `dashboards-verify` et
`kubernetes-otel-dashboards-verify` réussissent.
