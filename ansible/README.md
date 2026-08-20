# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée :
trois VM Vagrant avec MongoDB, Kafka, PostgreSQL sur `data-01`. `data-01`
utilise EDOT pour les métriques système et conserve Filebeat pour les logs ;
`data-02` et `data-03` restent sur Filebeat/Metricbeat.

## Ordre de lecture

1. `inventory/vagrant.yml` : hôtes ciblés et connexion SSH.
2. `site.yml` : provisionnement idempotent principal.
3. `templates/` : unités Podman Quadlet et configurations Beats générées.
4. `fleet-policies.yml` : policies par VM dans Kibana.
5. `status.yml` et `kafka-raft-pipeline.yml` : diagnostic et correctif ciblé.

Exécuter les playbooks depuis la racine du dépôt, avec l'inventaire Vagrant.

## Documentation externe

- [Guide des playbooks Ansible](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks.html)
- [Inventaires Ansible](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
- [Templates Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)
