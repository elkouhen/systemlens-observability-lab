# Observabilité Kubernetes : base

Les manifests de ce dossier constituent la base de la couche d'observabilité Kubernetes.
Ils utilisent les ressources personnalisées ECK. Exécuter `make eck-deploy`
pour installer ou mettre à jour l'opérateur ECK 3.5.0 avant leur application.

## Lire les manifests dans cet ordre

1. `elasticsearch-resources.yaml` : stockage et Kibana de base.
2. `kibana.yaml`, puis `fleet-server.yaml` : gestion centralisée des
   Elastic Agents et la policy Fleet Server préconfigurée dans `xpack.fleet`.
3. `apm-server.yaml` : endpoint d'ingestion APM.
4. `apm-logstash.yaml` : relais Logstash des événements APM et Elastic Agent
   vers les data streams Elasticsearch.
5. `kubernetes-logs-agent.yaml` : collecte des logs des pods et métriques kubelet.
6. `kube-state-metrics.yaml` : métriques d'état des workloads Kubernetes.
7. `elastic-ingress.yaml` : exposition TLS via Traefik.

Les applications envoient leurs signaux directement à APM Server avec l'agent
Java Elastic APM ; aucun autre collecteur de traces n'est déployé.

Pour appliquer le socle initial, utiliser `make elk-deploy`. Pour créer la clé
API de moindre privilège, déployer Logstash puis basculer la sortie APM, utiliser
`make apm-logstash-deploy`. Les flux sont alors : agent Java Elastic APM → APM
Server → Logstash (port 5044) → Elasticsearch (HTTPS), et pods → Elastic Agent
Kubernetes → Logstash (port 5045) → Elasticsearch. Le service Logstash est
interne au cluster ; les liaisons entrantes ne sont pas exposées ni chiffrées
dans ce POC. Pour un environnement de production, activer TLS sur les inputs et
monter un certificat géré par cert-manager ou la PKI de l'organisation.

Le routage des données applicatives est exclusivement défini dans
`apm-logstash.yaml` : lorsque `service.environment` respecte
`<code_sur_4_caractères>-<namespace>` (par exemple `h0p1-supermarket`),
Logstash extrait `h0p1`. Il route les logs de pods vers
`logs-kubernetes.container_logs-h0p1` et les métriques APM de conteneurs vers
`metrics-apm.app.kubernetes-h0p1`. Les traces, erreurs, métriques APM Server et
métriques Kubernetes non applicatives conservent leur data stream d'origine.

Après le déploiement, vérifier les deux composants et le relais :

```bash
kubectl -n elastic-stack get deployment apm-server-apm-server apm-logstash
kubectl -n elastic-stack logs deployment/apm-logstash --tail=50
```

Le résultat attendu est deux Deployments `1/1`, les listeners Logstash sur les
ports `5044` et `5045`, sans erreur d'indexation Elasticsearch.

Les traces et métriques conservent l'environnement défini par les variables
`ELASTIC_APM_*` ; les logs stdout et les métriques Kubernetes passent par
l'Elastic Agent Kubernetes puis Logstash.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
