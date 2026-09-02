# v2 — OpenTelemetry + Kafka

Variante OpenTelemetry/EDOT avec Elastic Stack `9.4.3`. La collecte de
`data-01` et des workloads Kubernetes publie les logs et métriques dans Kafka
(`otel-logs`, `otel-metrics`) ; les traces suivent également le chemin OTLP
(`otel-traces`) avant l'indexation Elasticsearch.

Le code Java et les images restent partagés avec la v1. Le déploiement, la
bascule de version et la recette sont documentés dans le
[guide central](../docs/deploiement-et-exploitation.md). La comparaison des
flux est dans la [documentation v1/v2/v3](../docs/architecture-v1-v2-v3.md).

Documents propres à la v2 :

- [plateforme Kubernetes et ELK](platform/README.md) ;
- [provisionnement EDOT de `data-01`](ansible/README.md) ;
- [dashboards et vérification](platform/elk/dashboards/README.md).

La v3 reprend cette structure et remplace uniquement la collecte VM par
Elastic Agent Fleet ; voir la [référence v1/v2/v3](../docs/architecture-v1-v2-v3.md).
