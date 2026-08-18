# Kubernetes ELK

Les manifests de ce dossier constituent la couche d'observabilité Kubernetes.
Ils utilisent les ressources personnalisées ECK ; l'opérateur ECK doit donc être
installé avant leur application.

## Lire les manifests dans cet ordre

1. `elasticsearch-resources.yaml` : stockage et Kibana de base.
2. `kibana-fleet-patch.yaml`, puis `fleet-server.yaml` : gestion centralisée des
   Elastic Agents.
3. `apm-server.yaml` : endpoint d'ingestion APM.
4. `otel-collector-gateway.yaml` : point d'entrée OTLP des applications.
5. `otel-collector-infrastructure.yaml` : métriques nœud, Kubelet et cluster.
6. `kubernetes-logs-agent.yaml` : collecte des logs des pods.
7. `elastic-ingress.yaml` : exposition TLS via Traefik.

Utiliser `make elk-deploy` pour les éléments liés aux applications. Les
ressources de base et l'Ingress restent applicables explicitement, comme décrit
dans le README racine.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
- [Composants EDOT pour Kubernetes](https://www.elastic.co/docs/solutions/observability/get-started/opentelemetry/use-cases/kubernetes/components)
- [Déploiement EDOT pour Kubernetes](https://www.elastic.co/docs/solutions/observability/get-started/opentelemetry/use-cases/kubernetes/deployment)
