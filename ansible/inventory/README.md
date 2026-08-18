# Inventaire Ansible

`vagrant.yml` décrit les trois VM `data-01` à `data-03`. Vagrant fournit les
ports SSH et les clés ; l'inventaire est donc utilisable après `vagrant up`.

Lire cet inventaire avant `site.yml` pour savoir quels hôtes recevront les
services. Ne pas y ajouter de secret : fournir les valeurs sensibles via
l'environnement ou un coffre-fort.

## Documentation externe

- [Construire un inventaire Ansible](https://docs.ansible.com/projects/ansible/latest/network/getting_started/first_inventory.html)
- [Variables et groupes d'inventaire](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
