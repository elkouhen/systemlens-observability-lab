# Architecture v2

Variante de la plateforme du POC utilisant Kibana et le Stack Elastic `9.4.3`.
La collecte des VM repose sur EDOT Collector `9.4.3` en mode agent. Les agents
collectent les logs et métriques locaux, les transmettent en OTLP au EDOT
Gateway Kubernetes, puis le Gateway utilise Kafka comme tampon avant
l'exportation vers Elasticsearch.

Le code Java, Maven et Docker reste inchangé. Seuls les manifests Kubernetes de
l'application sont propres à cette version. Le chemin v2 est :
`EDOT agent VM → EDOT Gateway → Kafka → EDOT Kafka exporter → Elasticsearch → Kibana`.
Les applications Kubernetes envoient également leurs signaux OTLP au Gateway.
Les secrets ne sont pas copiés dans cette variante.

```bash
make architecture-switch VERSION=v2
make architecture-status
make kubernetes-validate
```

Déployer la plateforme sélectionnée avec `make elk-deploy`.

La v2 est isolée de la v1 avec les namespaces `elastic-stack-v2` et
`h0tl-supermarche-app-v2`. Elle réutilise les hôtes fonctionnels
`elasticsearch.poc.test`, `kibana.poc.test` et `fleet.poc.test` ; un seul bundle
doit être exposé à la fois derrière ces URL.
