# Inventaire Ansible

`vagrant.yml` décrit l'unique VM `data-01`. Les commandes Ansible et les
cibles Make ciblent directement cette VM.

Lire cet inventaire avant `site.yml` pour savoir quels hôtes recevront les
services. Ne pas y ajouter de secret : fournir les valeurs sensibles via
l'environnement ou un coffre-fort.

## Documentation externe

- [Construire un inventaire Ansible](https://docs.ansible.com/projects/ansible/latest/network/getting_started/first_inventory.html)
- [Variables et groupes d'inventaire](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
