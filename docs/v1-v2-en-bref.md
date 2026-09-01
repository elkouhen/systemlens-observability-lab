# V1 et V2 en bref

Cette page aide à choisir rapidement une architecture et renvoie vers les
documents de référence.

## La différence en une phrase

- **V1** utilise les composants Elastic historiques : Elastic APM, APM Server,
  Elastic Agent/Beats et Logstash.
- **V2** utilise OpenTelemetry/EDOT et Kafka comme tampon entre la collecte et
  Elasticsearch.

## Quelle version choisir ?

Choisir **v1** pour reproduire l'architecture historique du POC.

Choisir **v2** pour tester la chaîne OpenTelemetry/EDOT avec Kafka et un
Collector backend avant Elasticsearch.

Dans les deux cas, le code Java reste partagé et l'unique VM `data-01` porte
les services de données. La v1 utilise Filebeat/Metricbeat et Logstash ; la v2
utilise EDOT et Kafka comme buffer de télémétrie.

## Architectures de référence

- [Architecture v1](../v1/README.md)
- [Architecture v2](../v2/README.md)
- [Comparatif détaillé v1/v2](architecture-v1-v2-differences.md)
- [Schémas des flux d'observabilité](observability-flows-v1-v2.md)

## Documents utiles

- [APM des applications Java sur Kubernetes](apm-application-kubernetes.md)
- [Métriques Kafka, MongoDB et Prometheus](metrics-clients-kafka-mongodb.md)
- [Dashboards v1](../v1/platform/elk/dashboards/README.md)
- [Dashboards v2](../v2/platform/elk/dashboards/README.md)
- [Provisionnement VM v1](../v1/ansible/README.md)
- [Provisionnement VM v2](../v2/ansible/README.md)

## Références officielles Elastic

- [OpenTelemetry avec Elastic (EDOT)](https://www.elastic.co/docs/reference/opentelemetry)
- [Architecture Kafka avec OpenTelemetry](https://www.elastic.co/docs/reference/opentelemetry/architecture/kafka)
- [Intégration Kafka OTLP](https://www.elastic.co/docs/reference/integrations/kafka_otel)

## Déployer une version

```bash
make architecture-switch VERSION=v1
make kubernetes-validate

make architecture-switch VERSION=v2
make kubernetes-validate
```

Les commandes de déploiement et de diagnostic sont documentées dans les
README des architectures ci-dessus. La cible `make deploy` provisionne d'abord
la VM puis déploie la chaîne Kubernetes, afin que Kafka soit disponible avant
la création des topics OTLP v2.
