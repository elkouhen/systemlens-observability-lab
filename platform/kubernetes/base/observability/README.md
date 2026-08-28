# Observabilité Kubernetes : base

Les manifests de ce dossier constituent la base de la couche d'observabilité Kubernetes.
Ils utilisent les ressources personnalisées ECK. Exécuter `make eck-deploy`
pour installer ou mettre à jour l'opérateur ECK 3.5.0 avant leur application.

## Lire les manifests dans cet ordre

1. `../../helm/eck-stack-values.yaml` : valeurs déclaratives de la release
   Helm qui crée Elasticsearch et Kibana.
2. `kibana.yaml`, puis `fleet-server.yaml` : gestion centralisée des
   Elastic Agents et la policy Fleet Server préconfigurée dans `xpack.fleet`.
3. `apm-server.yaml` : endpoint d'ingestion APM.
4. `apm-logstash.yaml` : deux pipelines Logstash vers les data streams
   Elasticsearch : `apm` pour APM Server et `kubernetes-logs` pour Elastic
   Agent Kubernetes.
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
`apm-logstash.yaml`. Le pipeline `apm` est réutilisable seul : il reçoit APM
sur le port 5044 et décode `kubernetes.namespace`. Le pipeline
`kubernetes-logs` est spécifique au POC : il reçoit les logs Kubernetes sur le
port 5045 et les décode depuis `kubernetes.namespace`. Les identités utilisent
`<type><plateforme_sur_3_caractères>-<namespace>` (par exemple
`h0tl-supermarche-app`). Logstash la décode, ajoute `labels.ptf: 0tl` et
`labels.namespace: supermarche-app`, puis normalise `service.environment` avec
le dictionnaire `translate` versionné dans `apm-logstash.yaml`. Les règles sont :
`r` → `recette`, `p` → `production`, `h` → `homologation`, `i` →
`integration` et `d` → `developpement`. Les traces Java et les métriques APM
applicatives détaillées (`apm.app.*`) sont reroutées vers un dataset mutualisé
par plateforme (`apm.app.0tl`) et vers le namespace du data stream correspondant
à l'environnement lorsque `kubernetes.namespace` est présent. Les métriques
agrégées APM qui ne portent pas cette métadonnée restent dans leur namespace et
dataset d'origine. Les événements non Java
conservent leur data stream d'origine, mais bénéficient de
la normalisation et des labels lorsque leur environnement respecte ce format.
Les logs applicatifs Kubernetes respectant cette convention sont également
routés vers un data stream par plateforme et environnement, par exemple
`logs-kube-0tl-homologation`.

Les deux sorties Elasticsearch activent `data_stream => true`,
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
