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

Pour vérifier les logs et métriques de chaque source, consulter
[`platform/elk/verification.md`](platform/elk/verification.md).
