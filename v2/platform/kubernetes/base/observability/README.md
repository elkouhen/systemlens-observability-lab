# Observabilité Kubernetes : base

Les manifests de ce dossier constituent la base de la couche d'observabilité Kubernetes.
Ils utilisent les ressources personnalisées ECK. Exécuter `make eck-deploy`
pour installer ou mettre à jour l'opérateur ECK 3.5.0 avant leur application.

## Lire les manifests dans cet ordre

1. `../../helm/eck-stack-values.yaml` : valeurs déclaratives de la release
   Helm qui crée Elasticsearch et Kibana.
2. `kibana.yaml`, puis `fleet-server.yaml` : préconfiguration Kibana et
   composants Elastic conservés pour les intégrations de plateforme.
3. `otel-kafka.yaml` : collecte OTel, buffer Kafka et export OTLP vers
   Elasticsearch.
4. `elastic-ingress.yaml` : exposition TLS v2 via Traefik.

En v2, les applications utilisent l'agent Java OpenTelemetry injecté par leur
manifest Kubernetes. Les traces et métriques vont au Collector EDOT Gateway.
Les logs stdout et les métriques hôte/Kubernetes sont collectés par le
Collector EDOT DaemonSet. Les trois flux sont mis en tampon dans Kafka puis
consommés par le Collector EDOT Elasticsearch ; APM Server, Logstash et
Elastic Agent Kubernetes ne sont pas utilisés pour ces signaux v2.

Le pipeline de traces du Gateway applique aussi le processeur et le connector
`elasticapm` avant Kafka. Ils enrichissent les traces OTLP et produisent les
métriques APM agrégées nécessaires à la vue Applications (services,
transactions, dépendances et service map). Ces métriques suivent ensuite le
même chemin Kafka que les autres métriques.

Pour appliquer le socle initial, utiliser `make elk-deploy`. Les applications
envoient traces et métriques en OTLP au Gateway. Le DaemonSet EDOT lit les logs
et métriques Kubernetes, puis les signaux applicatifs et Kubernetes sont
bufferisés dans Kafka avant leur export OTLP vers Elasticsearch. Les EDOT Agents
des VM publient quant à eux directement dans les topics OTLP par signal
(`otel-logs`, `otel-metrics`), consommés par le Collector backend. Les identités Kubernetes sont
enrichies par `k8sattributes`; les data streams OTel sont contrôlés par
Elasticsearch.

Le flux VM utilise EDOT Agent sur chaque VM et les topics OTLP par signal
`otel-logs` et `otel-metrics`. Le Collector backend les consomme et les exporte
vers Elasticsearch. Le topic historique `otel-otlp`, créé lors d'une version
intermédiaire, n'est plus consommé et n'est pas supprimé automatiquement.
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

Après le déploiement, vérifier les composants et les relais :

```bash
kubectl -n elastic-stack-v2 get deployment otel-gateway otel-kafka-exporter
kubectl -n elastic-stack-v2 logs deployment/otel-kafka-exporter --tail=50
```

Le résultat attendu est un Deployment EDOT Elasticsearch `1/1`, sans erreur de
consommation Kafka ni d'indexation.

Les traces conservent l'environnement défini par les variables `ELASTIC_APM_*`.
Les métriques applicatives exposées par `/actuator/prometheus`, notamment les
métriques Kafka client, passent par l'agent Java OpenTelemetry vers le gateway
OTLP, puis Kafka et le Collector OTel Elasticsearch.
Ce data stream est séparé des métriques APM natives pour éviter un conflit de
mapping entre les événements Prometheus et les événements APM ECS. Les logs
stdout et les métriques Kubernetes suivent leurs propres data streams.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
