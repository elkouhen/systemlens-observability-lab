# Manifests Kubernetes communs

Cette arborescence contient les manifests applicatifs mutualisés et l'overlay
par défaut. La base décrit les Deployments, Services, probes, ressources et namespace
de `supermarket-demo`.

L'overlay par défaut ajoute le raccordement à l'architecture active :

- `apps/supermarket-demo/default` : endpoint OTLP et instrumentation Java OTel.

Les manifests de la plateforme d'observabilité sont dans `architecture/platform`.

Validation depuis la racine :

```bash
kubectl kustomize kubernetes/apps/supermarket-demo/default >/dev/null
```

La cible `make apps-deploy` utilise directement l'overlay par défaut.
