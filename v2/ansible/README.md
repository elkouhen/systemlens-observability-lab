# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
Le profil `minimal` crée uniquement `data-01`, avec MongoDB standalone, Kafka
mono-broker et PostgreSQL. Le profil `distributed` crée les trois VM avec
replica set MongoDB et quorum Kafka KRaft. Chaque VM active reçoit un EDOT
Collector en mode agent, qui transmet ses logs et métriques dans Kafka au
format OTLP. Le Collector EDOT Kubernetes consomme ensuite ces topics et
exporte vers Elasticsearch.

Le profil est transmis automatiquement par Vagrant ; pour un changement de
topologie, utiliser `POC_PROFILE=minimal` ou `POC_PROFILE=distributed` avec la
cible Make correspondante.

Avant toute installation DNF, `site.yml` retire la route par défaut du réseau
privé VirtualBox et configure des résolveurs DNS sur l'interface NAT. Cette
séquence est nécessaire dès le premier provisioning, car les images Rocky
peuvent donner la priorité au réseau privé et empêcher la résolution des
miroirs de paquets.

La cible `make stock-view` affiche le catalogue et le stock depuis PostgreSQL
sur `data-01`, commun aux deux profils.

| VM | Collecteur | Acheminement |
| --- | --- | --- |
| VM active du profil | EDOT Collector agent | Kafka OTLP, puis EDOT Collector Kubernetes et Elasticsearch |

Les profils sont exclusifs afin d'éviter toute duplication de logs ou de
métriques sur une même VM.

## Ordre de lecture

1. `inventory/vagrant.yml` : hôtes ciblés et connexion SSH.
2. `site.yml` : provisionnement idempotent principal.
3. `templates/` : unités Podman Quadlet et configuration EDOT générées.
4. `status.yml` : diagnostic détaillé des services sur les VM.
5. Le déploiement des VM avec `make vm-provision` ou `make deploy` installe et
   démarre l'agent EDOT de façon idempotente.

Exécuter les playbooks depuis la racine du dépôt, avec l'inventaire Vagrant.

## Documentation externe

- [Guide des playbooks Ansible](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks.html)
- [Inventaires Ansible](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
- [Templates Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)
