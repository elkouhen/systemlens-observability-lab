# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
L’architecture crée quatre VM séparées : `poc-01` pour MongoDB, Kafka et PostgreSQL,
`otel-backend-01` pour les collecteurs EDOT, `otel-edge-01` pour HAProxy et
`elk-01` pour Elasticsearch, Kibana et Fleet Server.
Chaque VM reçoit un Elastic Agent enrôlé dans Fleet. La policy collecte
les logs, métriques système et intégrations Kafka, MongoDB et PostgreSQL, puis
envoie directement les événements vers Elasticsearch. Kafka reste une source
observée et n’est plus un buffer de télémétrie VM.

Le rôle `common` configure chrony avec `makestep 1.0 3` afin de corriger
automatiquement l’horloge après un redémarrage ou une reprise de VM. Cette
synchronisation est nécessaire aux fenêtres temporelles des dashboards et au
chemin OTLP → Kafka → Elasticsearch.

L’enrôlement Fleet est idempotent : la présence de
`/opt/Elastic/Agent/elastic-agent` conserve l’identité locale après un
redémarrage ou un reprovisionnement. Une réinstallation doit être demandée
explicitement avec la variable Ansible `fleet_agent_reinstall=true` ; elle ne
fait pas partie du chemin normal de démarrage.

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
| `otel-backend-01` | Gateway EDOT ; exporteur Kafka EDOT | OTLP Kubernetes → Kafka `poc-01` → APM Server / Elasticsearch |
| `otel-edge-01` | HAProxy | Point d’entrée OTLP, Kibana, Elasticsearch et Fleet |
| `elk-01` | Elasticsearch, APM Server, Kibana, Fleet Server | Stockage, ingestion des traces, consultation et enrôlement |

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
3. un rôle de service selon `node_role` : `poc`, `otel_backend`, `otel_edge` ou
   `elk`.

`site-restructured.yml` est conservé comme alias de compatibilité et importe
`site.yml`. Chaque rôle possède ses propres templates afin que la tâche et la
configuration déployée restent au même endroit.

Le playbook `fleet-agent.yml` est réservé à l'enrôlement après l'initialisation
de Kibana. Il n'exécute que le rôle `elastic_agent`, afin que `make deploy` ne
reprovisionne pas les middlewares et les services de chaque VM pour créer un
nouveau jeton Fleet.

Le script d'enrôlement vérifie d'abord l'inventaire Fleet et réutilise chaque
agent actif par nom d'hôte ; il ne crée donc pas une nouvelle instance lors
d'un second lancement. Les anciens enregistrements `uninstalled` restent
historiques et ne correspondent pas à un service actif.

Le téléchargement de l'Elastic Agent utilise un délai de 120 secondes et est
réessayé cinq fois, avec 15 secondes entre les tentatives. Ces valeurs peuvent
être adaptées ponctuellement avec `-e` si le réseau est particulièrement lent,
par exemple `-e elastic_agent_download_retries=8 elastic_agent_download_delay=30`.

Exécuter les playbooks depuis la racine du dépôt, avec l'inventaire Vagrant.

Pour déployer toute l'architecture en une seule commande, utiliser :

```bash
make ansible-deploy
```

Cette cible appelle `ansible/deploy-all.yml`. Le playbook démarre les VM sans
provisionnement implicite, exécute `site.yml` une seule fois, applique les
manifests Kubernetes versionnés, configure Elastic et Fleet, enrôle les VM,
déploie l'application puis vérifie les dashboards. Les mots de passe restent
dans `ELASTIC_PASSWORD` et `POSTGRESQL_PASSWORD` hors du dépôt.

## Documentation externe

- [Guide des playbooks Ansible](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks.html)
- [Inventaires Ansible](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
- [Templates Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)

## Rétention des VM

Le rôle `retention`, inclus dans `site.yml`, configure journald et logrotate,
puis active le nettoyage horaire des archives de plus de 24 h. Le playbook
`retention.yml` applique uniquement ces règles et la configuration Kafka ;
il redémarre le broker si son Quadlet change et réconcilie les topics existants.
Utiliser `make retention-deploy` et `make retention-verify` depuis la racine.
Les durées, plafonds, prérequis et limites sont détaillés dans le
[guide de rétention](../platform/elk/retention/README.md).
