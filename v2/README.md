# Architecture v2

Variante de la plateforme du POC utilisant Kibana et le Stack Elastic `9.4.3`,
version publiée par Elastic le 20 août 2026. Elasticsearch, APM Server, Fleet
Server, Elastic Agent, Logstash, le registre de packages et les Beats suivent
la même version afin de préserver la compatibilité du couplage Elastic.

Le code Java, Maven et Docker reste inchangé. Seuls les manifests Kubernetes de
l'application sont propres à cette version. Les signaux suivent le même chemin :
APM/agents → Logstash ou Elasticsearch → data streams → Kibana. Les secrets ne
sont pas copiés dans cette variante.

```bash
make architecture-switch VERSION=v2
make architecture-status
make kubernetes-validate
```

Déployer la plateforme sélectionnée avec `make elk-deploy`.

La v2 est isolée de la v1 avec les namespaces `elastic-stack-v2` et
`h0tl-supermarche-app-v2`, ainsi que les hôtes `elasticsearch-v2.poc.test`,
`kibana-v2.poc.test` et `fleet-v2.poc.test`. Cette isolation permet de valider
la migration avant de retirer la v1.
