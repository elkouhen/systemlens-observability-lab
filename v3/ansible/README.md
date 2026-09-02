# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
La v3 crée uniquement `data-01`, avec MongoDB standalone, Kafka mono-broker et
PostgreSQL. La VM reçoit un Elastic Agent enrôlé dans Fleet. Sa policy collecte
les logs, métriques système et intégrations Kafka, MongoDB et PostgreSQL, puis
envoie directement les événements vers Elasticsearch. Kafka reste une source
observée et n’est plus un buffer de télémétrie VM.

Avant toute installation DNF, `site.yml` retire la route par défaut du réseau
privé VirtualBox et configure des résolveurs DNS sur l'interface NAT. Cette
séquence est nécessaire dès le premier provisioning, car les images Rocky
peuvent donner la priorité au réseau privé et empêcher la résolution des
miroirs de paquets.

La cible `make stock-view` affiche le catalogue et le stock depuis PostgreSQL
sur `data-01`.

| VM | Collecteur | Acheminement |
| --- | --- | --- |
| `data-01` | Elastic Agent Fleet | Elasticsearch direct |

## Ordre de lecture

1. `inventory/vagrant.yml` : hôtes ciblés et connexion SSH.
2. `site.yml` : provisionnement idempotent principal.
3. `templates/` : unités Podman Quadlet des services de données.
4. `status.yml` : diagnostic détaillé des services sur les VM.
5. Le déploiement des VM avec `make fleet-vms-provision` ou `make deploy` crée
   un jeton temporaire et enrôle l’Elastic Agent de façon idempotente.

Exécuter les playbooks depuis la racine du dépôt, avec l'inventaire Vagrant.

## Documentation externe

- [Guide des playbooks Ansible](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks.html)
- [Inventaires Ansible](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
- [Templates Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)
