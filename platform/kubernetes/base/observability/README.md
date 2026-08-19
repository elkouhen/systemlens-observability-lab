# Observabilité Kubernetes : base

Les manifests de ce dossier constituent la base de la couche d'observabilité Kubernetes.
Ils utilisent les ressources personnalisées ECK ; l'opérateur ECK doit donc être
installé avant leur application.

## Lire les manifests dans cet ordre

1. `elasticsearch-resources.yaml` : stockage et Kibana de base.
2. `kibana.yaml`, puis `fleet-server.yaml` : gestion centralisée des
   Elastic Agents. Le patch contient aussi les outputs, packages et policies
   MongoDB/Kafka préconfigurés dans `xpack.fleet`.
3. `apm-server.yaml` : endpoint d'ingestion APM.
4. `otel-collector-gateway.yaml` : point d'entrée OTLP des applications.
5. `otel-collector-infrastructure.yaml` : métriques nœud, Kubelet et cluster.
6. `kubernetes-logs-agent.yaml` : collecte des logs des pods.
7. `elastic-ingress.yaml` : exposition TLS via Traefik.

`make elk-deploy` applique le socle hors gateway. `make apm-deploy` et
`make platform-deploy` attendent ensuite qu'ECK rende Elasticsearch joignable,
créent le secret d'API key du gateway si nécessaire, appliquent le gateway,
puis déploient les applications. Cette séquence évite qu'un pod gateway soit
créé avec une référence vers le secret encore absent.

Pour appliquer seulement le socle, utiliser `make elk-deploy` ou `kubectl
apply -k platform/kubernetes/overlays/local`; appliquer
`otel-collector-gateway.yaml` directement exige que le secret
`otel-collector-elasticsearch-api-key` existe déjà.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
- [Composants EDOT pour Kubernetes](https://www.elastic.co/docs/solutions/observability/get-started/opentelemetry/use-cases/kubernetes/components)
- [Déploiement EDOT pour Kubernetes](https://www.elastic.co/docs/solutions/observability/get-started/opentelemetry/use-cases/kubernetes/deployment)
