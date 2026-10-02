# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
L’architecture crée cinq VM séparées : `supermarket-middleware-01` pour MongoDB, Kafka métier et PostgreSQL,
`otel-backend-01` pour le broker Kafka dédié OTel et le collecteur backend OTel, `otel-edge-01` pour HAProxy et le
Collecteur EDOT Edge et
`elk-01` pour Elasticsearch, Kibana et Fleet Server, et `k3s-01` pour le serveur
k3s et les workloads Kubernetes.
Chaque VM reçoit un Elastic Agent en mode EDOT standalone. Il collecte les logs
et métriques locaux et les envoie en OTLP au Collecteur Edge. Exception :
`otel-backend-01` publie directement ses métriques, logs, traces et sa
télémétrie interne dans le Kafka OTel local, car cette VM ne dépend pas de
l'accès OTLP à `otel-edge-01`. Aucun signal produit par l'agent EDOT du backend
ne passe par Edge. Le Kafka OTel du backend reste le buffer des signaux
Kubernetes et VM ; le Kafka de `supermarket-middleware-01` reste réservé aux événements métier.

La cible `make fleet-opamp-enable` active en plus le monitoring Fleet OpAMP
des agents EDOT vers Fleet Server sur `elk-01`. Les agents restent standalone :
la collecte reste déclarée dans Ansible et aucune intégration Fleet concurrente
n'est activée.

La télémétrie interne des agents EDOT standalone et des collecteurs EDOT
exécutés sur les VM est exportée périodiquement par OTLP vers un receiver local,
puis routée dans le dataset `collectortelemetry`. Elle comprend les métriques,
logs et traces du Collector. Chaque composant conserve la sortie propre à son
rôle : les agents et Edge envoient leurs signaux vers Kafka, tandis que le
backend les écrit dans Elasticsearch. Fleet peut ainsi afficher la
consommation CPU et mémoire des agents dans la liste des collecteurs OpAMP et
les dashboards peuvent suivre les erreurs et la performance des pipelines. Les
traces internes dépendent de la production effective de spans par la
distribution du Collector.

Le receiver `hostmetrics` active explicitement `system.cpu.utilization` et
`system.memory.utilization`. Ces métriques alimentent la vue Infrastructure
Inventory avec les champs `host.name` et `data_stream.dataset:
hostmetricsreceiver.otel`.

Le rôle `common` configure chrony avec `makestep 1.0 3` afin de corriger
automatiquement l’horloge après un redémarrage ou une reprise de VM. Cette
synchronisation continue est nécessaire aux fenêtres temporelles des dashboards
et au chemin OTLP → Kafka → Elasticsearch. `rtcsync` maintient également
l’horloge matérielle alignée sur l’horloge système. Vérifier les cinq VM avec
`make time-sync-verify` ; la commande attend une source NTP sélectionnée et un
état `Leap status : Normal` sur chaque nœud.

Le mode EDOT standalone est idempotent : la présence de
`/opt/Elastic/Agent/elastic-agent` et du marqueur
`/etc/observability/elastic-agent-otel.mode`, ainsi que la correspondance avec
`elastic_agent_version`, conserve l'installation après un redémarrage ou un
reprovisionnement. Une installation n'est relancée que si l'agent est absent,
que le mode EDOT est absent, que la version diffère ou qu'une réinstallation
explicite est demandée. Les VM ne sont pas enrôlées comme agents
Fleet classiques ; elles peuvent être visibles dans Fleet comme collecteurs
OTel monitorés par OpAMP.
Une réinstallation doit être demandée explicitement avec la variable Ansible
`elastic_agent_reinstall=true` ; elle ne fait pas partie du chemin normal de
démarrage.

Avant toute installation de paquets, `site.yml` retire durablement la route par
défaut du réseau privé VirtualBox avec une surcharge Netplan et configure des
résolveurs IPv4 sur l’interface NAT. Les VM utilisent Ubuntu 24.04 LTS avec la
box Vagrant `bento/ubuntu-24.04`.
Le rôle `common` actualise les index APT juste avant l'installation afin d'éviter
les références à des versions retirées des miroirs Ubuntu.
Les valeurs par défaut (`1.1.1.1,8.8.8.8`) sont déclarées par `vm_dns_servers`
dans `inventory/group_vars/all.yml` et doivent être remplacées par les DNS de l'entreprise
si le réseau sortant les impose.

La cible `make stock-view` affiche le catalogue et le stock depuis PostgreSQL
sur `supermarket-middleware-01`.

Les redirections SSH Vagrant utilisent `VAGRANT_SSH_PORT_BASE + id` de la
configuration Ruby `NODES`, avec
une base fixée à `2250` par défaut. Si un port est déjà occupé sur l’hôte,
Vagrant choisit automatiquement le prochain port disponible. Pour imposer une
autre plage de départ, utiliser par exemple
`VAGRANT_SSH_PORT_BASE=2300 make vms-up`.

La cible `make vms-up` démarre les cinq VM en parallèle, puis exécute un seul
playbook Ansible sur les cinq hôtes. Les rôles restent parallèles par hôte et
les variables sensibles viennent de l’environnement. Les données Kafka sont conservées dans le volume Podman
`kafka-data`, monté sur le répertoire déclaré par `KAFKA_LOG_DIRS`.

Le broker Kafka OTel protège les échanges de logs, métriques et traces avec
SASL/PLAIN. Le compte `otel_publisher` est utilisé par Edge et l'agent EDOT du
backend pour publier ; le compte `otel_consumer` est utilisé par le backend et
la collecte des métriques Kafka pour consommer. Définir
`KAFKA_OTEL_PUBLISHER_PASSWORD` et `KAFKA_OTEL_CONSUMER_PASSWORD` dans
l'environnement avant `make vms-up` ou `make ansible-deploy`. Les mots de passe
ne sont ni versionnés ni écrits dans les manifests Kubernetes ; le Job de
création des topics reçoit son secret par `otel-kafka-credentials-apply`.

La cible `make vms-restart` redémarre séquentiellement les cinq VM
(`supermarket-middleware-01`, `otel-backend-01`, `otel-edge-01`, `elk-01` et `k3s-01`) sans
reprovisionnement. Une VM arrêtée est démarrée avec `--no-provision`. Le script
affiche l’état Vagrant final pour permettre de vérifier que chaque VM est
`running`.

La cible `make metrics-chain-restart` redémarre uniquement la chaîne de
transport des métriques, sans reprovisionnement : collecteur backend OTel,
Kafka OTel, collecteur Edge, puis HAProxy OTLP. Elle vérifie les endpoints de
santé des collecteurs, l’état du broker et sa disponibilité du quorum.

Après une modification de la configuration EDOT du backend, utiliser
`make elastic-agent-backend-provision` pour reprovisionner uniquement
`otel-backend-01`. La cible attend les variables d’environnement habituelles
du provisionnement et ne crée pas la VM si elle n’existe pas encore.

Les agents EDOT qui envoient leurs signaux vers Edge utilisent une clé Bearer
distincte par client. Les cibles Makefile qui provisionnent l'architecture
chargent automatiquement `.observability-credentials.env` et vérifient les
identifiants avant d'exécuter Ansible. Pour lancer Ansible directement, charger
le fichier dans le shell courant avec `source ./.observability-credentials.env`.
Le collecteur Edge
conserve ces clés dans `/etc/observability/otel-edge.tokens` avec le mode
`0600`.

Pour générer et charger les clés Edge et les identifiants Kafka OTel du lab dans
le shell courant, exécuter
depuis `architecture/` :

```bash
source ./platform/elk/scripts/generate-otel-edge-keys.sh
```

La même génération peut être lancée sans conserver l'environnement du script
avec `make credentials-generate`, puis le fichier peut être chargé avec
`source ./.observability-credentials.env`.

Le script conserve les clés Edge et les mots de passe dans
`.observability-credentials.env`, ignoré par Git et protégé par le mode `0600`.
Le fichier contient `POSTGRESQL_PASSWORD`, `MONGODB_PASSWORD`,
`ELASTIC_PASSWORD`, les mots de passe Kafka OTel et les cinq clés Edge. Pour
remplacer tous les identifiants, utiliser
`OBSERVABILITY_CREDENTIALS_ROTATE=1 source ./platform/elk/scripts/generate-otel-edge-keys.sh`.

Pour supprimer les cinq VM et leurs disques locaux, exécuter la cible
destructive `make vms-destroy`. Cette opération ne supprime pas les ressources
Kubernetes ni les données persistées en dehors des VM.

Après `make deploy`, la phase `deploy-post` reprovisionne le collecteur backend
avec la clé API Elasticsearch courante et active le monitoring OpAMP des
agents VM. Cette phase peut être rejouée seule avec `make deploy-post` après
une rotation de clé ou une modification de configuration.

| VM | Collecteur | Acheminement |
| --- | --- | --- |
| `supermarket-middleware-01` | MongoDB, Kafka métier, PostgreSQL | Middlewares du scénario applicatif |
| `otel-backend-01` | Kafka OTel, backend OTel | Métriques, logs et traces locales → Kafka OTel local → APM Server / Elasticsearch |
| `otel-edge-01` | Collecteur EDOT Edge ; HAProxy | OTLP Kubernetes et VM → Kafka |
| `elk-01` | Elasticsearch, APM Server, Kibana, Fleet Server | Stockage, ingestion des traces, consultation et enrôlement |
| `k3s-01` | Serveur k3s | Cluster Kubernetes et workloads du lab |

## Ordre de lecture

1. `inventory/vagrant.yml` : hôtes ciblés, connexion SSH et capacités propres à chaque nœud ; les variables communes sont dans `inventory/group_vars/all.yml`.
2. `site.yml` : orchestration des rôles idempotents par groupes d’inventaire.
3. `roles/` : responsabilités séparées par type de VM et composants communs.
4. `roles/*/templates/` : unités Podman Quadlet et configurations propres à chaque rôle.
5. `status.yml` : diagnostic détaillé des services sur les VM.
6. `make vms-up` prépare les VM et installe les agents EDOT. Après
  l'initialisation d'Elastic, `make deploy` déploie le stack et les applications.

## Rôles

Le playbook `site.yml` applique les rôles dans cet ordre, en utilisant les groupes de
`inventory/vagrant.yml` comme structure de déploiement :

1. `common` : prérequis système, réseau, pare-feu, répertoires et
   résolution des noms des VM ;
2. `elk` sur `elk_nodes` : Elasticsearch, APM Server, Kibana et Fleet Server ;
3. `otel_backend` sur `otel_backend_nodes` : Kafka OTel et backend OTel ;
4. `otel_edge` sur `otel_edge_nodes` : collecteur Edge et HAProxy ;
5. `lab` sur `supermarket_middleware_nodes` : MongoDB, Kafka métier et PostgreSQL ;
6. `k3s` sur `k3s_nodes` : serveur Kubernetes ;
7. `elastic_agent` sur `elastic_agent_nodes` : téléchargement et configuration EDOT,
   après le démarrage des services dont les agents dépendent.

Les ports pare-feu, la clé d’accès Edge et les besoins spécifiques du middleware
sont également déclarés par hôte dans l’inventaire. Les rôles utilisent les
groupes Ansible comme source de vérité pour sélectionner le comportement propre
à chaque VM ; les conditions restantes portent sur l’état observé de la machine
et l’idempotence.

`site-restructured.yml` est conservé comme alias de compatibilité et importe
`site.yml`. Chaque rôle possède ses propres templates afin que la tâche et la
configuration déployée restent au même endroit.

Le playbook `fleet-agent.yml` est le point d'entrée du monitoring OpAMP. Il
réapplique la configuration EDOT avec un jeton fourni temporairement par la
cible `make fleet-opamp-enable`, sans écrire ce jeton dans le dépôt.

Le script de monitoring réutilise un jeton OpAMP stable par VM ; il ne crée
donc pas une nouvelle clé lors d'un second lancement. L'identifiant OpAMP est
persisté sur la VM pour éviter les doublons dans Fleet.

Le téléchargement de l'Elastic Agent utilise un délai de 120 secondes et est
réessayé cinq fois, avec 15 secondes entre les tentatives. Ces valeurs peuvent
être adaptées ponctuellement avec `-e` si le réseau est particulièrement lent,
par exemple `-e elastic_agent_download_retries=8 elastic_agent_download_delay=30`.

Le rôle `elk` attend l'allocation des index primaires Elasticsearch avant de
réinitialiser le token de service Kibana. Une réponse 200 sur `GET /` ne suffit
pas toujours lors du premier démarrage : l'API des tokens écrit dans l'index
`.security`, qui peut encore être indisponible et répondre 503. La suppression
du token réessaie également les réponses 503 transitoires. Voir la
[documentation Elastic sur les comptes de service](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/service-accounts)
pour le stockage des tokens et la [documentation de l'API de santé du cluster](https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-cluster-health)
pour le mécanisme d'attente.

Exécuter les playbooks depuis la racine du dépôt, avec l'inventaire Vagrant.

Pour démarrer et provisionner les VM, utiliser :

```bash
make vms-up
make vm-status
```

Pour préparer le cluster k3s local, utiliser :

```bash
source ./platform/elk/scripts/load-credentials.sh
make k3s-vm-up
make k3s-kubeconfig
```

La première cible crée et provisionne `k3s-01`. La seconde exporte son
kubeconfig dans `.kube/k3s.config`. Le déploiement Elastic, OTel et applicatif
reste piloté par les cibles de déploiement dédiées.

L'installation de k3s utilise le script de la release épinglée sur GitHub. Ce
chemin évite la dépendance à `get.k3s.io` lorsque son service de distribution
est indisponible. La version reste déclarée par `k3s_version` dans
`inventory/group_vars/all.yml`.

Après vérification des services, déployer le reste de l'architecture avec :

```bash
make deploy
```

L'ordre opérationnel est volontairement séquentiel : plateforme Elastic sur
`elk-01`, backend OTel, Edge OTel, middleware du scénario, serveur k3s, puis
collecteurs Kubernetes et applications. Les namespaces et secrets Kubernetes
strictement nécessaires sont préparés en amont ; l'overlay Kubernetes complet
n'est appliqué qu'après le backend et Edge.

Lorsque `make deploy` réutilise une VM ELK déjà provisionnée, le mot de passe
Elasticsearch persistant sur `elk-01` est utilisé comme source de vérité pour
éviter un `401 Unauthorized` dû à un secret local différent. Le mot de passe
n'est jamais affiché ni versionné.

Les mots de passe restent dans `ELASTIC_PASSWORD`, `POSTGRESQL_PASSWORD` et
`MONGODB_PASSWORD` hors du dépôt. Si `MONGODB_PASSWORD` n'est pas défini, le
lab réutilise la valeur de `POSTGRESQL_PASSWORD`. La cible `ansible-deploy`
reste disponible pour l'orchestrateur Ansible complet.

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
Les durées, plafonds, prérequis et limites sont déclarés dans les fichiers de
configuration de rétention et vérifiables avec `make retention-verify`.
