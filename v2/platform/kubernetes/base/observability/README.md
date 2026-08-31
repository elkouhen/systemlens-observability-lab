# Observabilité Kubernetes : base

Les manifests de ce dossier constituent la base de la couche d'observabilité Kubernetes.
Ils utilisent les ressources personnalisées ECK. Exécuter `make eck-deploy`
pour installer ou mettre à jour l'opérateur ECK 3.5.0 avant leur application.

## Lire les manifests dans cet ordre

1. `../../helm/eck-stack-values.yaml` : valeurs déclaratives de la release
   Helm qui crée Elasticsearch et Kibana.
2. `kibana.yaml`, puis `fleet-server.yaml` : gestion Fleet conservée pour les
   VM et préconfiguration des packages Kibana.
3. `otel-kafka.yaml` : collecte OTel, buffer Kafka et export OTLP vers
   Elasticsearch.
4. `elastic-ingress.yaml` : exposition TLS v2 via Traefik.

En v2, les applications utilisent l'agent Java OpenTelemetry injecté par leur
manifest Kubernetes. Les traces et métriques vont au Collector OTel gateway.
Les logs stdout et les métriques hôte/Kubernetes sont collectés par le
Collector OTel DaemonSet. Les trois flux sont mis en tampon dans Kafka puis
consommés par le Collector OTel Elasticsearch ; APM Server, Logstash et
Elastic Agent Kubernetes ne sont pas utilisés pour ces signaux v2.

Pour appliquer le socle initial, utiliser `make elk-deploy`. Les applications
envoient traces et métriques en OTLP au gateway. Le DaemonSet OTel lit les logs
stdout et les métriques hôte, puis les trois signaux sont bufferisés dans
Kafka avant leur export OTLP vers Elasticsearch. Les identités Kubernetes sont
enrichies par `k8sattributes`; les data streams OTel sont contrôlés par
Elasticsearch.

En v1, les deux sorties Elasticsearch activent `data_stream => true`,
`data_stream_auto_routing => true` et `ecs_compatibility => "v8"` : les champs
`data_stream.*` déterminent le data stream cible et les événements restent
compatibles ECS v8.

### Règle de mutualisation des pipelines

Toute mutualisation de filtre entre les pipelines `apm` et
`kubernetes-logs` doit préserver la responsabilité de routage de chaque
signal. Un filtre commun peut enrichir les champs ECS et les labels, mais ne
doit pas modifier globalement `data_stream.type`, `data_stream.dataset` ou
`data_stream.namespace` sans condition explicite sur le type et le dataset.

- Le pipeline APM mutualise le `data_stream.dataset` au niveau plateforme
  (`apm.app.<code_plateforme>`) pour les traces Java et les métriques
  applicatives `apm.app.*` portant les métadonnées Kubernetes nécessaires.
  Le `data_stream.namespace` porte l’environnement.
- Le pipeline des logs Kubernetes est propriétaire du dataset `kube-*` et du
  namespace d’environnement pour les événements `kubernetes.container_logs`.
- Une valeur `service.environment` déjà fournie par l’agent reste prioritaire ;
  la convention du namespace Kubernetes ne sert que de valeur de secours.

Toute nouvelle règle de routage doit donc préciser dans cette documentation sa
source, ses conditions, son dataset cible, son namespace cible et la
compatibilité de mapping attendue. Cette contrainte évite qu’un filtre
réutilisé mélange des familles de métriques ou casse le mapping d’un data
stream existant.

Après le déploiement, vérifier les deux composants et le relais :

```bash
kubectl -n elastic-stack-v2 get deployment apm-server-apm-server apm-logstash
kubectl -n elastic-stack-v2 logs deployment/apm-logstash --tail=50
```

Le résultat attendu est deux Deployments `1/1`, les listeners Logstash sur les
ports `5044` et `5045`, sans erreur d'indexation Elasticsearch.

Les traces conservent l'environnement défini par les variables `ELASTIC_APM_*`.
Les métriques applicatives exposées par `/actuator/prometheus`, notamment les
métriques Kafka client, passent par l’Elastic Agent Kubernetes puis Logstash
vers le data stream dédié `metrics-app.prometheus.<plateforme>-<environnement>`.
Ce data stream est séparé des métriques APM natives pour éviter un conflit de
mapping entre les événements Prometheus et les événements APM ECS. Les logs
stdout et les métriques Kubernetes suivent leurs propres data streams.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
