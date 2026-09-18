# Observabilité Kubernetes : base

Les manifests de ce dossier constituent la base de la couche d'observabilité Kubernetes.
Ils routent les URL publiques vers le stack Elastic de `elk-01` via `edge-01` et déploient
les collecteurs OTel dans Kubernetes.

## Lire les manifests dans cet ordre

1. `../../ansible/templates/` : unités Quadlet Elasticsearch, Kibana et Fleet
   Server déployées sur `elk-01`.
2. `elastic-vm-services.yaml` et `elastic-ingress.yaml` : services externes et
   exposition TLS via Traefik vers la VM.
3. `otel-kafka.yaml` : collecte OTel, buffer Kafka et export OTLP vers
   Elasticsearch.

En v3, les applications utilisent l'agent Java OpenTelemetry injecté par leur
manifest Kubernetes pour les traces et les envoient via HAProxy au Gateway
EDOT exécuté sur `otel-backend-01`. Le Deployment EDOT `otel-prometheus-scraper` scrape leurs
métriques Actuator/Prometheus sur le port des Services applicatifs.
Les logs stdout et les métriques hôte/Kubernetes sont collectés par le
Collector EDOT DaemonSet. Les trois flux sont mis en tampon dans Kafka puis
consommés par l'exporteur EDOT exécuté sur `otel-backend-01`. Les VM ne passent pas par
ce chemin pour leur télémétrie système : leur Elastic Agent Fleet exporte
directement vers Elasticsearch.

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
vagrant ssh otel-backend-01 -c 'sudo systemctl is-active observability-otel-gateway'
kubectl -n elastic-stack get deployment otel-prometheus-scraper
make otel-kafka-exporter-vm-status
```

Le résultat attendu est un exporteur EDOT actif sur `otel-backend-01`, sans erreur de
consommation Kafka ni d'indexation.

Les traces conservent l'environnement défini par les variables `OTEL_*`. Les
métriques applicatives exposées par `/actuator/prometheus`, notamment les
métriques Kafka client, sont scrappées toutes les 15 secondes par le receiver
Prometheus du scraper Kubernetes. Elles suivent ensuite Kafka et le Collector OTel
Elasticsearch. L'export métrique de l'agent Java est désactivé en v3 pour
éviter un double envoi.
Ce data stream est séparé des métriques APM natives pour éviter un conflit de
mapping entre les événements Prometheus et les événements APM ECS. Les logs
stdout et les métriques Kubernetes suivent leurs propres data streams.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
