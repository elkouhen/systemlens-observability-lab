# Architecture v1

Snapshot de l'architecture existante du POC, conservé pour les déploiements
Elastic Stack `8.11.3`. La plateforme Kubernetes, le provisionnement Ansible et
les manifests Kubernetes de l'application sont isolés dans ce répertoire ; le
code Java, Maven et Docker reste partagé.

```bash
make architecture-switch VERSION=v1
make architecture-status
make kubernetes-validate
```

Installation complète de la v1, dans l'ordre :

    source ./v1/platform/elk/scripts/load-credentials.sh
    export POSTGRESQL_PASSWORD  # valeur fournie hors du dépôt
    make -C v1 deploy

`deploy` crée ou répare d'abord le certificat TLS POC `elastic-public-tls`,
déploie Elasticsearch/Kibana/Logstash et leurs secrets, attend les services
Elastic, puis provisionne l'unique VM `data-01`. Cette dernière installe
Filebeat et Metricbeat avec `logstash.poc.test:443` et la même autorité de
confiance. Les certificats et secrets sont générés ou injectés à l'exécution ;
ils ne sont pas versionnés.

Pour vérifier les logs et métriques de chaque source, consulter
[`platform/elk/verification.md`](platform/elk/verification.md).
