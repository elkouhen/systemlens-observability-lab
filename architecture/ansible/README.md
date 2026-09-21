# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
L’architecture crée quatre VM séparées : `poc-01` pour MongoDB, Kafka et PostgreSQL,
`otel-backend-01` pour l’exporteur EDOT Kafka, `otel-edge-01` pour HAProxy et le
Collecteur EDOT Edge et
`elk-01` pour Elasticsearch, Kibana et Fleet Server.
Chaque VM reçoit un Elastic Agent en mode EDOT standalone. Il collecte les logs
et métriques locaux et les envoie en OTLP au Collecteur Edge. Kafka est le
buffer commun des signaux Kubernetes et VM.

Le rôle `common` configure chrony avec `makestep 1.0 3` afin de corriger
automatiquement l’horloge après un redémarrage ou une reprise de VM. Cette
synchronisation est nécessaire aux fenêtres temporelles des dashboards et au
chemin OTLP → Kafka → Elasticsearch.

Le mode EDOT standalone est idempotent : la présence de
`/opt/Elastic/Agent/elastic-agent` et du marqueur
`/etc/observability/elastic-agent-otel.mode` conserve l'installation après un
redémarrage ou un reprovisionnement. Les VM ne sont pas enrôlées dans Fleet.
Une réinstallation doit être demandée explicitement avec la variable Ansible
`fleet_agent_reinstall=true` ; elle ne fait pas partie du chemin normal de
démarrage.

Avant toute installation DNF, `site.yml` retire la route par défaut du réseau
privé VirtualBox et configure des résolveurs DNS sur l'interface NAT. Cette
séquence est nécessaire dès le premier provisioning, car les images Rocky
peuvent donner la priorité au réseau privé et empêcher la résolution des
miroirs de paquets.

La cible `make stock-view` affiche le catalogue et le stock depuis PostgreSQL
sur `poc-01`.

La cible `make vms-up` démarre et provisionne les quatre VM avant le déploiement
de la plateforme. Les données Kafka sont conservées dans le volume Podman
`kafka-data`, monté sur le répertoire déclaré par `KAFKA_LOG_DIRS`.

| VM | Collecteur | Acheminement |
| --- | --- | --- |
| `poc-01` | MongoDB, Kafka, PostgreSQL | Middlewares du scénario applicatif |
| `otel-backend-01` | Exporteur Kafka EDOT | Kafka `poc-01` → APM Server / Elasticsearch |
| `otel-edge-01` | Collecteur EDOT Edge ; HAProxy | OTLP Kubernetes et VM → Kafka ; point d’entrée Kibana, Elasticsearch et Fleet |
| `elk-01` | Elasticsearch, APM Server, Kibana, Fleet Server | Stockage, ingestion des traces, consultation et enrôlement |

## Ordre de lecture

1. `inventory/vagrant.yml` : hôtes ciblés et connexion SSH.
2. `site.yml` : orchestration des rôles idempotents.
3. `roles/` : responsabilités séparées par type de VM et composants communs.
4. `roles/*/templates/` : unités Podman Quadlet et configurations propres à chaque rôle.
5. `status.yml` : diagnostic détaillé des services sur les VM.
6. `make vms-up` prépare les VM et installe les agents EDOT. Après
  l'initialisation d'Elastic, `make deploy` déploie le stack et les applications.

## Rôles

Le playbook `site.yml` applique les rôles dans cet ordre :

1. `common` : prérequis système, réseau, pare-feu, SELinux, répertoires et
   résolution des noms des VM ;
2. `elastic_agent` : téléchargement, installation et configuration locale de l’agent EDOT ;
3. un rôle de service selon `node_role` : `poc`, `otel_backend`, `otel_edge` ou
   `elk`.

`site-restructured.yml` est conservé comme alias de compatibilité et importe
`site.yml`. Chaque rôle possède ses propres templates afin que la tâche et la
configuration déployée restent au même endroit.

Le playbook `fleet-agent.yml` est conservé comme point d'entrée de compatibilité,
mais le rôle `elastic_agent` configure désormais le mode EDOT standalone. Il ne
crée pas d'enrôlement Fleet pour les VM.

Le script d'enrôlement vérifie d'abord l'inventaire Fleet et réutilise chaque
agent actif par nom d'hôte ; il ne crée donc pas une nouvelle instance lors
d'un second lancement. Les anciens enregistrements `uninstalled` restent
historiques et ne correspondent pas à un service actif.

Le téléchargement de l'Elastic Agent utilise un délai de 120 secondes et est
réessayé cinq fois, avec 15 secondes entre les tentatives. Ces valeurs peuvent
être adaptées ponctuellement avec `-e` si le réseau est particulièrement lent,
par exemple `-e elastic_agent_download_retries=8 elastic_agent_download_delay=30`.

Exécuter les playbooks depuis la racine du dépôt, avec l'inventaire Vagrant.

Pour démarrer et provisionner les VM, utiliser :

```bash
make vms-up
make vm-status
```

Après vérification des services, déployer le reste de l'architecture avec :

```bash
make deploy
```

Les mots de passe restent dans `ELASTIC_PASSWORD` et `POSTGRESQL_PASSWORD` hors
du dépôt. La cible `ansible-deploy` reste disponible pour l'orchestrateur
Ansible complet.

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
