# Templates de configuration

Ces modèles Jinja sont rendus par `ansible/site.yml` sur chaque VM. Ils forment
le lien entre les variables Ansible et les fichiers réellement consommés par
systemd et Podman. La collecte des VM est assurée par Elastic Agent/Fleet ;
aucune configuration de Beat n'est rendue par Ansible.

## Lire les templates

- `poc-mongodb.container.j2`, `poc-kafka.container.j2` et
  `poc-postgresql.container.j2` : unités Quadlet
  créant les conteneurs de données.

Après une modification, relancer `vagrant provision` puis contrôler les
services avec `systemctl` ou `make vm-status`.

## Documentation externe

- [Templates Ansible/Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)
- [Elastic Agent](https://www.elastic.co/docs/reference/fleet/elastic-agent-overview)
