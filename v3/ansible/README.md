# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
La v3 crée quatre VM séparées : `poc-01` pour MongoDB, Kafka et PostgreSQL,
`otel-backend-01` pour les collecteurs EDOT, `edge-01` pour HAProxy et
`elk-01` pour Elasticsearch, Kibana et Fleet Server.
Chaque VM reçoit un Elastic Agent enrôlé dans Fleet. La policy collecte
les logs, métriques système et intégrations Kafka, MongoDB et PostgreSQL, puis
envoie directement les événements vers Elasticsearch. Kafka reste une source
observée et n’est plus un buffer de télémétrie VM.

Avant toute installation DNF, `site.yml` retire la route par défaut du réseau
privé VirtualBox et configure des résolveurs DNS sur l'interface NAT. Cette
séquence est nécessaire dès le premier provisioning, car les images Rocky
peuvent donner la priorité au réseau privé et empêcher la résolution des
miroirs de paquets.

La cible `make stock-view` affiche le catalogue et le stock depuis PostgreSQL
sur `poc-01`.

La cible `make deploy` reprovisionne les VM existantes avant de déployer la
plateforme. Les données Kafka sont conservées dans le volume Podman
`kafka-data`, monté sur le répertoire déclaré par `KAFKA_LOG_DIRS`.

| VM | Collecteur | Acheminement |
| --- | --- | --- |
| `poc-01` | MongoDB, Kafka, PostgreSQL | Middlewares du scénario applicatif |
| `otel-backend-01` | Gateway EDOT ; exporteur Kafka EDOT | OTLP edge → Kafka `poc-01` → Elasticsearch |
| `edge-01` | HAProxy | Point d’entrée OTLP, Kibana, Elasticsearch et Fleet |
| `elk-01` | Elasticsearch, Kibana, Fleet Server | Stockage, consultation et enrôlement |

## Ordre de lecture

1. `inventory/vagrant.yml` : hôtes ciblés et connexion SSH.
2. `site.yml` : orchestration des rôles idempotents.
3. `roles/` : responsabilités séparées par type de VM et composants communs.
4. `roles/*/templates/` : unités Podman Quadlet et configurations propres à chaque rôle.
5. `status.yml` : diagnostic détaillé des services sur les VM.
6. Le déploiement des VM avec `make fleet-vms-provision` ou `make deploy` crée
  un jeton temporaire et enrôle l’Elastic Agent de façon idempotente.

## Rôles

Le playbook `site.yml` applique les rôles dans cet ordre :

1. `common` : prérequis système, réseau, pare-feu, SELinux, répertoires et
   résolution des noms des VM ;
2. `elastic_agent` : téléchargement et enrôlement Fleet de l'agent local ;
3. un rôle de service selon `node_role` : `poc`, `otel_backend`, `edge` ou
   `elk`.

`site-restructured.yml` est conservé comme alias de compatibilité et importe
`site.yml`. Chaque rôle possède ses propres templates afin que la tâche et la
configuration déployée restent au même endroit.

Exécuter les playbooks depuis la racine du dépôt, avec l'inventaire Vagrant.

## Documentation externe

- [Guide des playbooks Ansible](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks.html)
- [Inventaires Ansible](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
- [Templates Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)
