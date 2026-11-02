# ADR-007 : choisir le namespace des data streams par topic Kafka

## Statut

Accepted

Amendé le 2026-11-02 par
[ADR-009](ADR-009-namespaces-supermarche-et-k8s.md) : le collecteur Edge
publie aussi dans des topics suffixés, et les topics `otel-<signal>-supermarche`
et `otel-<signal>-k8s` sont créés avec la rétention des topics de base.

## Date

2026-11-02

## Contexte

Les signaux transitent par le Kafka OTel avant d'être écrits par le collecteur
backend. L'exporteur Elasticsearch route chaque document vers
`<type>-<data_stream.dataset>-<data_stream.namespace>` ; sans attribut, le
dataset vient du receiver d'origine (ou `generic`) et le namespace vaut
`default`. Les traces passent par APM Server, qui écrit dans
`traces-apm-<namespace>`.

Le besoin est de contrôler le data stream cible des logs, métriques et traces
sans modifier chaque source, en s'appuyant sur la souscription par regex du
backend ([ADR-006](ADR-006-collecteurs-opentelemetry-contrib.md)).

## Décision

Le suffixe du topic détermine le namespace : `otel-<signal>-<namespace>`.

- Le receiver Kafka expose le topic d'origine dans le contexte (`kafka.topic`).
  Le processor `resource/kafka-topic` le copie en attribut de ressource avant
  le batch ; `transform/data-stream-namespace` en déduit
  `data_stream.namespace`, normalisé en `[a-z0-9_]` minuscules, puis supprime
  l'attribut technique.
- Les topics de base (`otel-logs`, `otel-metrics`, `otel-traces`) ne posent
  aucun namespace : le comportement existant est conservé.
- Le topic ne choisit que le namespace. Le dataset reste choisi par la source,
  car il peut contenir des points (`hostmetricsreceiver.otel`) et rendrait le
  nom de topic ambigu.
- APM Server respecte l'attribut de ressource `data_stream.namespace` : les
  traces conservent l'UI APM complète.

## Alternatives considérées

- **Table de règles dans le backend** (par `service.name`, namespace
  Kubernetes…) : centralisée mais ne sépare pas les flux dans Kafka.
- **Attributs posés à la source** : déjà supportés par l'exporteur, mais la
  règle est dispersée dans chaque application ou collecteur.

## Conséquences

- Un flux dédié est isolé dans Kafka (topic propre) et dans Elasticsearch
  (data stream propre, mêmes templates et politiques que le namespace
  `default`).
- Le collecteur Edge publie uniquement dans les topics de base. Un producteur
  qui cible un namespace publie directement dans le Kafka OTel. *Amendé par
  ADR-009 : l'Edge choisit lui-même un topic suffixé pour les signaux
  applicatifs et Kubernetes.*
- Les topics suffixés sont créés automatiquement par le broker et ne reçoivent
  pas la rétention appliquée par le job `otel-telemetry-topics` aux topics de
  base.

## Vérification

Un log, une métrique et une trace publiés dans `otel-*-recette` ont été écrits
dans `logs-generic-recette`, `metrics-generic.otel-recette` et
`traces-apm-recette`, tandis que le trafic des topics de base restait dans le
namespace `default`.
