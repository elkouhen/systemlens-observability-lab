# Plateforme d’observabilité

Ce répertoire contient les composants transverses déployés dans Kubernetes et
les objets Elastic associés à l’architecture active.

## Périmètre

- `kubernetes/` : namespace, services Elastic, ingress et collecteurs OTel ;
- `elk/` : dashboards, policies, scripts de bootstrap et contrôles Kibana ;
- `helm/` : valeurs du déploiement ECK lorsqu’elles sont utilisées.

Les agents EDOT des VM ne sont pas configurés ici. Leur collecte est décrite
dans `architecture/ansible/roles/elastic_agent/` et leur supervision est
activée par OpAMP via Fleet. Les package policies Fleet ne pilotent pas la
collecte des agents standalone.

## Validation

Depuis la racine du dépôt :

```bash
make kubernetes-validate
make ansible-validate
```

Les secrets restent hors Git. Les modifications durables doivent être faites
dans les manifests, templates et scripts versionnés avant tout déploiement.
