# Manifests Kubernetes communs

Cette arborescence contient les manifests applicatifs mutualisés entre v1 et
v2. La base décrit les Deployments, Services, probes, ressources et namespace
de `supermarket-demo`.

Les overlays ajoutent uniquement les différences de chaque architecture :

- `apps/supermarket-demo/v1` : endpoint Kafka du chemin Beats/Logstash ;
- `apps/supermarket-demo/v2` : endpoint Kafka et instrumentation Java OTel.

Les manifests de la plateforme d'observabilité restent dans `v1/platform` et
`v2/platform`, car les chaînes de collecte sont différentes.

Validation depuis la racine :

```bash
kubectl kustomize kubernetes/apps/supermarket-demo/v1 >/dev/null
kubectl kustomize kubernetes/apps/supermarket-demo/v2 >/dev/null
```

Les cibles `make apps-deploy` de chaque bundle utilisent directement l'overlay
de la version active.
