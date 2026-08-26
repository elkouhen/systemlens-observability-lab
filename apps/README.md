# Applications

Ce répertoire contient le code et les manifests propres aux workloads métier.
Il est volontairement séparé de `platform/` : une application ne doit pas
porter la configuration de la plateforme ELK qui l'observe.

## Parcours conseillé

Lire [`supermarket-demo/README.md`](supermarket-demo/README.md), puis les
manifests Kubernetes dans `supermarket-demo/kubernetes/` et enfin les modules
Maven.

Pour intégrer une nouvelle application Java dans la chaîne APM, logs ECS et
Logstash, suivre [Ajouter une application Java observée](ADDING_APPLICATION.md).

## Documentation externe

- [Déployer des workloads Kubernetes](https://kubernetes.io/docs/concepts/workloads/)
- [Agent Java Elastic APM](https://www.elastic.co/docs/reference/apm/agents/java)
