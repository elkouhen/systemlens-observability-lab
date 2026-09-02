# Architecture v3

Variante hybride de référence avec Elastic Stack `9.4.3`. Les applications et
Kubernetes conservent le chemin OpenTelemetry/EDOT de la v2 avec Kafka comme
tampon. Les VM utilisent l’Elastic Agent enrôlé dans Fleet et envoient
directement leurs logs et métriques vers Elasticsearch.

Le code Java et les images restent partagés avec la v1. Le déploiement, la
bascule de version et la recette sont documentés dans le
[guide central](../docs/deploiement-et-exploitation.md). La comparaison des
flux est dans la [documentation des architectures](../docs/architecture-v1-v2-v3.md).

Documents propres à la v3 :

- [plateforme Kubernetes et ELK](platform/README.md) ;
- [provisionnement Fleet de `data-01`](ansible/README.md) ;
- [dashboards et vérification](platform/elk/dashboards/README.md).
