# Templates de configuration

Ces modèles Jinja sont rendus par `ansible/site.yml` sur chaque VM. Ils forment
le lien entre les variables Ansible et les fichiers réellement consommés par
systemd, Podman, Filebeat et Metricbeat. PostgreSQL n'est rendu que sur
`data-01`.

## Lire les templates

- `poc-mongodb.container.j2`, `poc-kafka.container.j2` et
  `poc-postgresql.container.j2` : unités Quadlet
  créant les conteneurs de données.
- `beat.service.j2` : unité systemd commune aux Beats.
- `filebeat.yml.j2` et `metricbeat.yml.j2` : collecte de logs et métriques.

Après une modification, relancer `vagrant provision` puis contrôler les
services avec `systemctl` ou `make vm-status`.

## Documentation externe

- [Templates Ansible/Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)
- [Filebeat](https://www.elastic.co/docs/reference/beats/filebeat)
- [Metricbeat](https://www.elastic.co/docs/reference/beats/metricbeat)
