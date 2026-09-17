# Inventaire Ansible

`vagrant.yml` décrit `data-01` pour les services de données et `otel-01` pour
les deux gateways OpenTelemetry. Les commandes Ansible ciblent les deux VM ;
les cibles Make spécialisées indiquent la VM concernée.

Lire cet inventaire avant `site.yml` pour savoir quels hôtes recevront les
services. Ne pas y ajouter de secret : fournir les valeurs sensibles via
l'environnement ou un coffre-fort.

## Documentation externe

- [Construire un inventaire Ansible](https://docs.ansible.com/projects/ansible/latest/network/getting_started/first_inventory.html)
- [Variables et groupes d'inventaire](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
