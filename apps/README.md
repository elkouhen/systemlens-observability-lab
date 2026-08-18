# Applications

Ce répertoire contient le code et les manifests propres aux workloads métier.
Il est volontairement séparé de `platform/` : une application ne doit pas
porter la configuration de la plateforme ELK qui l'observe.

## Parcours conseillé

Lire [`apm-demo/README.md`](apm-demo/README.md), puis les manifests Kubernetes
dans `apm-demo/kubernetes/` et enfin les modules Maven.

## Documentation externe

- [Déployer des workloads Kubernetes](https://kubernetes.io/docs/concepts/workloads/)
- [OpenTelemetry Java](https://opentelemetry.io/docs/languages/java/)
