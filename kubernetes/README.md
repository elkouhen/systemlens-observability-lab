# Manifests Kubernetes communs

Cette arborescence contient les manifests applicatifs mutualisés et l'overlay
v3. La base décrit les Deployments, Services, probes, ressources et namespace
de `supermarket-demo`.

L'overlay conservé ajoute le raccordement à l'architecture v3 :

- `apps/supermarket-demo/v3` : endpoint OTLP et instrumentation Java OTel.

Les manifests de la plateforme d'observabilité sont dans `v3/platform`.

Validation depuis la racine :

```bash
kubectl kustomize kubernetes/apps/supermarket-demo/v3 >/dev/null
```

La cible `make apps-deploy` utilise directement l'overlay v3.
