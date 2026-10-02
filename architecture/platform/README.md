# Plateforme d’observabilité

Ce répertoire contient les composants transverses déployés dans Kubernetes et
les objets Elastic associés à l’architecture active.

## Périmètre

- `kubernetes/` : namespace, services Elastic, ingress et collecteurs OTel ;
- `elk/` : dashboards, policies, scripts de bootstrap et contrôles Kibana ;
- `helm/` : valeurs du déploiement ECK lorsqu’elles sont utilisées.

Les agents EDOT des VM ne sont pas configurés ici. Leur collecte est décrite
dans `architecture/ansible/roles/elastic_agent/` et leur supervision est
activée par OpAMP via Fleet. Les package policies Fleet ne pilotent pas la
collecte des agents standalone.

## Validation

Depuis la racine du dépôt :

```bash
make kubernetes-validate
make ansible-validate
```

Le DaemonSet `otel-kubernetes` collecte les métriques du nœud et des pods via
`hostmetrics` et `kubeletstats`. Le receiver `kubeletstats` utilise l'IP du
nœud injectée par la Downward API (`status.hostIP`) : le nom Kubernetes du nœud
n'est pas utilisé comme adresse réseau, car il n'est pas nécessairement
résolvable depuis le pod. Le flux attendu est :

```text
kubelet / hostmetrics → otel-kubernetes → OTLP gRPC → otel-edge-01
  → Kafka otel-metrics → exporteur backend → metrics-* dans Elasticsearch
```

Après une modification de cette chaîne, vérifier le rendu avec
`make kubernetes-validate`, puis contrôler les logs des collecteurs et la
présence récente de documents `metrics-*` dans Elasticsearch. Le déploiement
reste volontairement séparé de cette validation : appliquer l'overlay seulement
après revue du rendu.

Les secrets restent hors Git. Les mots de passe et clés utilisés par le lab
peuvent être chargés depuis `.observability-credentials.env`, généré par
`source ./platform/elk/scripts/generate-otel-edge-keys.sh`. Les modifications
durables doivent être faites dans les manifests, templates et scripts
versionnés avant tout déploiement.

La vérification ILM exclut le data stream système
`metrics-endpoint.metadata_current_default`, géré par l'intégration Endpoint
de Fleet. Les flux `logs-*`, `metrics-*` et `traces-*` de la télémétrie du lab
restent couverts par la policy déclarée dans
`platform/elk/ilm/retention.json`.

Les collecteurs Kubernetes s'authentifient auprès d'Edge avec deux clés Bearer
distinctes, une pour `otel-kubernetes` et une pour
`otel-kubernetes-cluster`. Les fournir hors Git avec
`OTEL_EDGE_KEY_KUBERNETES` et `OTEL_EDGE_KEY_KUBERNETES_CLUSTER`, puis exécuter
`make otel-edge-client-keys-apply` avant `make kubernetes-observability-deploy`.
Les clés sont stockées dans le Secret Kubernetes `otel-edge-client-keys`.
