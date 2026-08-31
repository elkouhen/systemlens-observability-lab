# v1 et v2 en bref

Cette page est le point d'entrée rapide pour comprendre les deux
architectures d'observabilité du POC.

## La différence en une phrase

- **v1** utilise les composants Elastic classiques : agent Elastic APM,
  APM Server, Elastic Agent/Beats et Logstash.
- **v2** utilise OpenTelemetry/EDOT et Kafka comme tampon commun pour les
  traces, métriques et logs.

## Comparaison rapide

| Besoin | v1 | v2 |
| --- | --- | --- |
| Traces et métriques APM Java | Agent Elastic APM → APM Server → Logstash → Elasticsearch | Agent Java OpenTelemetry → EDOT Gateway → Kafka → EDOT Collector → Elasticsearch |
| Logs applicatifs Kubernetes | Elastic Agent → Logstash → Elasticsearch | EDOT Collector `filelog` → Kafka → EDOT Collector → Elasticsearch |
| Métriques et logs des VM | Elastic Agent/Fleet ou Filebeat/Metricbeat → Elasticsearch | EDOT Agent sur la VM → Kafka → EDOT Collector → Elasticsearch |
| Métriques Prometheus | Elastic Agent Kubernetes scrape `/actuator/prometheus` | Pas de scraping Prometheus dans le chemin actuel ; les métriques Java exportées par OTel passent par OTLP et Kafka |
| Rôle de Kafka | Transport des événements métier | Événements métier et buffer de télémétrie |
| Profil léger | VM `data-01` uniquement | VM `data-01` uniquement |

## Ce qui ne change pas

- les applications Java et leur code métier restent partagés ;
- Elasticsearch et Kibana restent les outils de stockage et de consultation ;
- les URL fonctionnelles sont les mêmes : `elasticsearch.poc.test`,
  `kibana.poc.test` et `fleet.poc.test` ;
- un seul bundle v1 ou v2 doit être exposé à la fois derrière ces URL ;
- les données Kafka, MongoDB et PostgreSQL de la VM restent observables.

## Quelle version utiliser ?

- Choisir **v1** pour reproduire l'architecture Elastic historique et les
  dashboards classiques associés à APM Server, Fleet et Logstash.
- Choisir **v2** pour tester une chaîne standardisée OpenTelemetry avec Kafka
  comme point de découplage entre la collecte et Elasticsearch.

## Liens utiles

Pour comprendre les flux en détail :

- [Comparatif technique complet v1/v2](architecture-v1-v2-differences.md)
- [Schémas Mermaid des flux](observability-flows-v1-v2.md)

Pour la solution v2 choisie, voir aussi les deux références officielles Elastic :

- [Elastic OpenTelemetry (EDOT)](https://www.elastic.co/docs/reference/opentelemetry) :
  rôle des distributions Elastic d'OpenTelemetry et du Collector ;
- [OpenTelemetry quickstarts Elastic](https://www.elastic.co/docs/reference/opentelemetry/quickstart) :
  collecte des métriques, logs et traces sur Kubernetes et les hôtes/VM.

Pour l'APM et les applications Java :

- [APM des applications Java sur Kubernetes](apm-application-kubernetes.md)
- [Guide d'intégration de l'application Java](../apps/ADDING_APPLICATION.md)
- [README de l'application de démonstration](../apps/supermarket-demo/README.md)

Pour les métriques Kafka/MongoDB et Prometheus :

- [Métriques des clients Kafka et MongoDB](metrics-clients-kafka-mongodb.md)
- [Dashboards v1](../v1/platform/elk/dashboards/README.md)
- [Dashboards v2](../v2/platform/elk/dashboards/README.md)

Pour déployer ou diagnostiquer :

- [README v1](../v1/README.md)
- [README v2](../v2/README.md)
- [Collecte Kubernetes v1](../v1/platform/kubernetes/base/observability/README.md)
- [Collecte Kubernetes v2](../v2/platform/kubernetes/base/observability/README.md)
- [Provisionnement VM v1](../v1/ansible/README.md)
- [Provisionnement VM v2](../v2/ansible/README.md)

## Commandes de base

Depuis la racine du dépôt, sélectionner une version puis vérifier son rendu :

```bash
make architecture-switch VERSION=v1
make kubernetes-validate

make architecture-switch VERSION=v2
make kubernetes-validate
```

La documentation détaillée décrit ensuite les commandes de déploiement et les
contrôles propres à chaque version.
