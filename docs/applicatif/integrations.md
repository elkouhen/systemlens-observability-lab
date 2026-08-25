# Modes d'intégration applicative testés

Cette page s'adresse aux développeurs qui doivent comprendre où part la
télémétrie de leur service et ce que chaque mode implique dans Kibana. Le POC
teste volontairement deux chemins actifs pour comparer une intégration Elastic
native à une intégration OpenTelemetry.

Elle traite l'instrumentation applicative et ses signaux. La configuration des
collecteurs, de Fleet et des data streams est décrite dans la
[documentation système](../systeme/README.md).

## Les deux chemins actifs

| Service | Instrumentation | Chemin des traces | Ce que le POC permet d'observer |
| --- | --- | --- | --- |
| `order-service` | agent Java Elastic | agent → APM Server en HTTPS → Elasticsearch | expérience APM Elastic native, traces HTTP et corrélation avec les logs |
| `inventory-service` | agent Java OpenTelemetry | agent → OTLP/HTTP → gateway EDOT → Kafka → backend EDOT → Elasticsearch | pipeline OTLP explicite, enrichissement Kubernetes et effet du tampon Kafka |

Les deux services participent au même scénario métier : une commande HTTP de
`order-service` appelle `inventory-service`, tandis que les commandes en ligne
passent aussi par Kafka. Les vues APM peuvent donc afficher les deux services,
mais l'origine et le délai d'arrivée de leurs traces ne sont pas identiques.

## `order-service` : agent Java Elastic et APM Server

`order-service` charge l'agent Java Elastic. Sa configuration
`ELASTIC_APM_*` définit l'identité du service et l'URL HTTPS d'APM Server. Ce
mode envoie directement les traces à APM Server : il est le chemin le plus court
vers Elasticsearch dans ce POC.

Ce que cela signifie pour le développeur :

- l'instrumentation automatique crée des transactions et spans pour les appels
  HTTP et les dépendances prises en charge ;
- les identifiants de trace sont ajoutés au MDC Logback, puis conservés dans les
  logs JSON ECS pour la navigation log-vers-trace ;
- une erreur contrôlée peut être générée avec `GET /api/error` afin de vérifier
  son apparition dans APM.

Le déploiement de l'application synchronise le token et le certificat d'APM
Server nécessaires au service. Les détails des variables et des Secrets sont
dans le [README Kubernetes applicatif](../../apps/supermarket-demo/kubernetes/README.md).

## `inventory-service` : agent Java OpenTelemetry, EDOT et Kafka

`inventory-service` charge l'agent Java OpenTelemetry. Ses variables `OTEL_*`
envoient les traces en OTLP/HTTP vers le gateway EDOT. Le gateway enrichit les
ressources Kubernetes et publie les traces dans le topic Kafka `otel-traces`.
Des collectors backend relisent ensuite ce topic, produisent les métriques APM
dérivées et indexent les données dans Elasticsearch.

Ce chemin apporte un tampon entre l'application et Elasticsearch : une courte
indisponibilité du backend peut être absorbée par Kafka. En contrepartie, une
trace peut apparaître plus tard dans Kibana. Lorsqu'une trace manque, vérifier
le gateway, le topic et le consumer lag avant de modifier l'instrumentation.

Les métriques applicatives OTLP ne passent pas par Kafka : elles sont envoyées
du gateway à Elasticsearch afin de limiter leur latence. L'export OTLP des logs
applicatifs est désactivé ; les logs restent écrits sur stdout puis collectés
une seule fois par l'Elastic Agent Kubernetes.

## Data stream partagé des métriques applicatives

Les métriques applicatives APM des services exécutés dans le cluster Kubernetes
sont routées par le pipeline Elasticsearch `metrics-apm.app@custom` vers un
data stream commun par environnement APM :
`metrics-apm.app.kubernetes-<service.environment>`. `service.environment` est
fourni par `ELASTIC_APM_ENVIRONMENT` ; avec `local`, les deux services écrivent
donc dans `metrics-apm.app.kubernetes-local`. Le pipeline reconnaît les
métriques de conteneur par `container.id`. La data view `metrics-*` les couvre
déjà ; `service.name` reste la dimension permettant de distinguer les
applications d'un même environnement.

Le routage s'applique seulement aux nouvelles métriques ayant un environnement
non vide. Les traces, erreurs et métriques internes APM restent dans les data
streams APM standards. APM Server ne fournit pas de `container.id` dans ses
métriques : il reste donc hors de ce routage.

## Éléments communs et choix de lecture

Les deux modes utilisent la propagation W3C `traceparent` pour relier les
opérations distribuées. Les applications produisent des logs JSON ECS sur
stdout ; l'Elastic Agent Kubernetes ajoute les métadonnées de pod et normalise
`trace.id` et `span.id`. Ainsi, un développeur peut partir d'un log pour ouvrir
la trace correspondante sans que le même événement soit collecté deux fois.

Pour tester les deux modes, suivre le tutoriel
[Première démonstration](tutorials/premiere-demonstration.md). Pour comparer
les collecteurs, les alternatives non actives et les formats de données au-delà
des services applicatifs, consulter le
[comparatif système des intégrations](../systeme/integrations.md).

## Alternatives non actives dans ce parcours

Le POC documente aussi l'envoi OTLP vers APM Server et l'envoi OpenTelemetry
direct vers Elasticsearch. Ces options ne sont pas les chemins actifs des
services décrits ici. Elles servent de points de comparaison dans la
[documentation système](../systeme/integrations.md) et ne doivent pas être
activées en parallèle sur le même signal sans prévenir les doublons.
