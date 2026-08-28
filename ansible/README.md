# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
Le profil `minimal` crée uniquement `data-01`, avec MongoDB standalone, Kafka
mono-broker et PostgreSQL. Le profil `distributed` crée les trois VM avec
replica set MongoDB et quorum Kafka KRaft. Aucun collecteur EDOT n'est
provisionné ; les profils de collecte reposent sur Beats et Fleet.

Le profil est transmis automatiquement par Vagrant ; pour un changement de
topologie, utiliser `POC_PROFILE=minimal` ou `POC_PROFILE=distributed` avec la
cible Make correspondante.

La cible `make stock-view` affiche le catalogue et le stock depuis PostgreSQL
sur `data-01`, commun aux deux profils.

| VM | Collecteur | Acheminement |
| --- | --- | --- |
| `data-01`, `data-02` | Elastic Agent enrôlé dans Fleet | Elasticsearch, piloté par Fleet |
| `data-03` | Filebeat et Metricbeat | Elasticsearch avec clé API Beats |

Les profils sont exclusifs afin d'éviter toute duplication de logs ou de
métriques sur une même VM.

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
