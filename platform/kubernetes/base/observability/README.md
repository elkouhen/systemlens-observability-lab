# Observabilité Kubernetes : base

Les manifests de ce dossier constituent la base de la couche d'observabilité Kubernetes.
Ils utilisent les ressources personnalisées ECK. Exécuter `make eck-deploy`
pour installer ou mettre à jour l'opérateur ECK 3.5.0 avant leur application.

## Lire les manifests dans cet ordre

1. `elasticsearch-resources.yaml` : stockage et Kibana de base.
2. `kibana.yaml`, puis `fleet-server.yaml` : gestion centralisée des
   Elastic Agents et la policy Fleet Server préconfigurée dans `xpack.fleet`.
3. `apm-server.yaml` : endpoint d'ingestion APM.
4. `apm-logstash.yaml` : relais Logstash des événements APM vers les data streams Elasticsearch.
5. `kubernetes-logs-agent.yaml` : collecte des logs des pods.
6. `elastic-ingress.yaml` : exposition TLS via Traefik.

Les applications envoient leurs signaux directement à APM Server avec l'agent
Java Elastic APM ; aucun autre collecteur de traces n'est déployé.

Pour appliquer le socle initial, utiliser `make elk-deploy`. Pour créer la clé
API de moindre privilège, déployer Logstash puis basculer la sortie APM, utiliser
`make apm-logstash-deploy`. Le trafic est alors : agents APM → APM Server →
Logstash (Lumberjack) → Elasticsearch (HTTPS). Le service Logstash est interne
au cluster ; la liaison APM Server–Logstash n'est pas exposée. Dans ce POC,
elle n'est pas chiffrée à l'intérieur du cluster. Pour un environnement de
production, activer TLS sur l'input `elastic_agent` et monter un certificat
géré par cert-manager ou la PKI de l'organisation.

Après le déploiement, vérifier les deux composants et le relais :

```bash
kubectl -n elastic-stack get deployment apm-server-apm-server apm-logstash
kubectl -n elastic-stack logs deployment/apm-logstash --tail=50
```

Le résultat attendu est deux Deployments `1/1` et un listener Logstash sur le
port `5044` sans erreur d'indexation Elasticsearch.

Les traces et métriques conservent l'environnement défini par les variables
`ELASTIC_APM_*` ; les logs restent collectés séparément sur stdout par l'Elastic
Agent Kubernetes.

## Documentation externe

- [Concepts Kubernetes](https://kubernetes.io/docs/concepts/)
- [Applications Elastic orchestrées par ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/orchestrate-other-elastic-applications)
