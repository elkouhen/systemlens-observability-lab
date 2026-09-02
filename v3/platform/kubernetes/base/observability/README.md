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
4. `elastic-ingress.yaml` : exposition TLS v3 via Traefik.

En v3, les applications utilisent l'agent Java OpenTelemetry injecté par leur
manifest Kubernetes pour les traces. Le Collector EDOT Gateway scrape leurs
métriques Actuator/Prometheus sur le port des Services applicatifs.
Les logs stdout et les métriques hôte/Kubernetes sont collectés par le
Collector EDOT DaemonSet. Les trois flux sont mis en tampon dans Kafka puis
consommés par le Collector EDOT Elasticsearch. Les VM ne passent pas par ce
chemin : leur Elastic Agent Fleet exporte directement vers Elasticsearch.

Le pipeline de traces du Gateway applique aussi le processeur et le connector
`elasticapm` avant Kafka. Ils enrichissent les traces OTLP et produisent les
métriques APM agrégées nécessaires à la vue Applications (services,
transactions, dépendances et service map). Ces métriques suivent ensuite le
même chemin Kafka que les autres métriques.

Pour appliquer le socle initial, utiliser `make elk-deploy`. Les applications
envoient traces et métriques en OTLP au Gateway. Le DaemonSet EDOT lit les logs
et métriques Kubernetes, puis les signaux applicatifs et Kubernetes sont
bufferisés dans Kafka avant leur export OTLP vers Elasticsearch. Les Elastic Agents
des VM publient quant à eux directement dans Elasticsearch via Fleet. Les identités Kubernetes sont
enrichies par `k8sattributes`; le Collector backend utilise le mapping ECS
pour conserver la compatibilité avec les vues APM et les dashboards
classiques.

Le flux VM utilise l'Elastic Agent Fleet sur chaque VM. Les intégrations Fleet
alimentent directement les data streams `logs-*` et `metrics-*`, sans topic OTLP
VM ni Collector backend intermédiaire.

Après le déploiement, vérifier les composants et les relais :

```bash
kubectl -n elastic-stack get deployment otel-gateway otel-kafka-exporter
kubectl -n elastic-stack logs deployment/otel-kafka-exporter --tail=50
```

Le résultat attendu est un Deployment EDOT Elasticsearch `1/1`, sans erreur de
consommation Kafka ni d'indexation.

Les traces conservent l'environnement défini par les variables `OTEL_*`. Les
métriques applicatives exposées par `/actuator/prometheus`, notamment les
métriques Kafka client, sont scrappées toutes les 15 secondes par le receiver
Prometheus du Gateway. Elles suivent ensuite Kafka et le Collector OTel
Elasticsearch. L'export métrique de l'agent Java est désactivé en v3 pour
éviter un double envoi.
Ce data stream est séparé des métriques APM natives pour éviter un conflit de
mapping entre les événements Prometheus et les événements APM ECS. Les logs
stdout et les métriques Kubernetes suivent leurs propres data streams.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
