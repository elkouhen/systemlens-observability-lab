# Architecture v1

Bundle historique du POC avec Elastic Stack `8.11.3`. La collecte repose sur
Elastic APM, Elastic Agent/Beats et Logstash. Le code Java et les images restent
partagés avec la v2.

Le déploiement, la bascule de version et la recette sont documentés dans le
[guide central](../docs/deploiement-et-exploitation.md). Ce README ne répète
pas ces procédures ; il indique uniquement les documents propres à la v1 :

- [plateforme Kubernetes et ELK](platform/README.md) ;
- [provisionnement de `data-01`](ansible/README.md) ;
- [vérification dans Kibana Discover](platform/elk/verification.md).
