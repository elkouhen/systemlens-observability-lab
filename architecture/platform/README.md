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
kubelet / hostmetrics → otel-kubernetes → OTLP HTTP → otel-edge-01
  → Kafka otel-metrics → exporteur backend → metrics-* dans Elasticsearch
```

Après une modification de cette chaîne, vérifier le rendu avec
`make kubernetes-validate`, puis contrôler les logs des collecteurs et la
présence récente de documents `metrics-*` dans Elasticsearch. Le déploiement
reste volontairement séparé de cette validation : appliquer l'overlay seulement
après revue du rendu.

Les secrets restent hors Git. Les modifications durables doivent être faites
dans les manifests, templates et scripts versionnés avant tout déploiement.
