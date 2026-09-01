# Architecture v2

Variante de la plateforme du POC utilisant Kibana et le Stack Elastic `9.4.3`.
La collecte des VM repose sur EDOT Collector `9.4.3` en mode agent. Les agents
collectent les logs et métriques locaux et les publient directement dans Kafka
en OTLP ; le Collector EDOT Kubernetes consomme ensuite ces topics avant
l'exportation vers Elasticsearch.

Le code Java, Maven et Docker reste inchangé. Seuls les manifests Kubernetes de
l'application sont propres à cette version. Le chemin VM v2 est :
`EDOT Agent VM → Kafka → EDOT Kafka exporter → Elasticsearch → Kibana`.
Kafka expose son listener interne sur `192.168.33.10:9092` et un listener
redirigé par Vagrant sur `192.168.5.2:19092`, passerelle Docker utilisée par les pods k3d.
Le chemin APM Java est distinct :
`OpenTelemetry Java Agent → EDOT Gateway → Kafka → EDOT Kafka exporter`.
Les applications Kubernetes envoient également leurs signaux OTLP au Gateway.
Les producteurs edge publient les trois signaux dans des topics OTLP séparés par
signal (`otel-traces`, `otel-metrics` et `otel-logs`), consommés par le backend EDOT avant
l'indexation Elasticsearch.
Les secrets ne sont pas copiés dans cette variante.

Les logs stdout des applications Java sont collectés par le DaemonSet EDOT
Kubernetes. Les lignes ECS JSON sont décodées avant leur envoi dans Kafka : le
message, le service, le niveau et le contexte `trace_id`/`span_id` restent
recherchables dans `logs-generic.otel-*` et permettent de retrouver la trace
associée dans la vue APM. Les logs ne sont donc pas exportés directement par
l’agent Java (`OTEL_LOGS_EXPORTER=none`) : ils suivent le chemin Kubernetes
`stdout → EDOT Collector → Kafka → Elasticsearch`.

```bash
make architecture-switch VERSION=v2
make architecture-status
make kubernetes-validate
```

Avant le premier déploiement, fournir le mot de passe PostgreSQL hors du
dépôt, puis lancer :

    export POSTGRESQL_PASSWORD
    make -C v2 deploy

Le déploiement crée ou répare d'abord le certificat TLS POC
`elastic-public-tls`, prépare la clé API du Collector EDOT, puis applique les
manifests Kubernetes et provisionne les VM EDOT.

La v2 est isolée de la v1 avec les namespaces `elastic-stack-v2` et
`h0tl-supermarche-app-v2`. Elle réutilise les hôtes fonctionnels
`elasticsearch.poc.test`, `kibana.poc.test` et `fleet.poc.test` ; un seul bundle
doit être exposé à la fois derrière ces URL.
