# Observabilité Kubernetes : base

Les manifests de ce dossier constituent la base de la couche d'observabilité Kubernetes.
Ils utilisent les ressources personnalisées ECK. Exécuter `make eck-deploy`
pour installer ou mettre à jour l'opérateur ECK 3.5.0 avant leur application.

## Lire les manifests dans cet ordre

1. `elasticsearch-resources.yaml` : stockage et Kibana de base.
2. `kibana.yaml`, puis `fleet-server.yaml` : gestion centralisée des
   Elastic Agents et la policy Fleet Server préconfigurée dans `xpack.fleet`.
3. `apm-server.yaml` : endpoint d'ingestion APM.
4. `kubernetes-logs-agent.yaml` : collecte des logs des pods.
5. `elastic-ingress.yaml` : exposition TLS via Traefik.

Les applications envoient leurs signaux OTLP directement à APM Server : aucun
collecteur EDOT n'est déployé avec cette plateforme Elastic 8.5.1.

Pour appliquer seulement le socle, utiliser `make elk-deploy` ou `kubectl
apply -k platform/kubernetes/overlays/local`.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
