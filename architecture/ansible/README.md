# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
L’architecture crée cinq VM séparées : `supermarket-middleware-01` pour MongoDB, Kafka métier et PostgreSQL,
`otel-backend-01` pour le broker Kafka dédié OTel et le collecteur backend OTel, `otel-edge-01` pour HAProxy et le
Collecteur Edge (OpenTelemetry Collector Contrib) et
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
puis routée dans le dataset `collectortelemetry`. Elle comprend les métriques
(niveau `normal`, toutes les 30 s) et les logs du Collector, sans traces
([ADR-013](../docs/ADR-013-livraison-kafka-et-telemetrie-interne.md)). Chaque composant conserve la sortie propre à son
rôle : les agents et Edge envoient leurs signaux vers Kafka, tandis que le
backend les écrit dans Elasticsearch. Fleet peut ainsi afficher la
consommation CPU et mémoire des agents dans la liste des collecteurs OpAMP et
les dashboards peuvent suivre les erreurs et la performance des pipelines.

Le collecteur backend ne commite un offset Kafka qu'après l'écriture du
message dans la file persistante de son exporteur (`message_marking.after`) :
un redémarrage peut rejouer des messages, mais n'en perd pas. Si APM Server ou
Elasticsearch est indisponible, la file se remplit puis le lag du groupe
`otel-backend` augmente : Kafka sert de tampon (ADR-013).

Le receiver `hostmetrics` active explicitement `system.cpu.utilization` et
`system.memory.utilization`. Ces métriques alimentent la vue Infrastructure
Inventory avec les champs `host.name` et `data_stream.dataset:
hostmetricsreceiver.otel`.

Le rôle `common` configure chrony avec `makestep 1.0 -1` et `maxpoll 6` sur
chaque source : chrony interroge ses sources au moins toutes les 64 s et saute
l’horloge dès qu’elle dérive de plus d’une seconde. Une VM VirtualBox mise en
pause par la veille de l’hôte se recale ainsi en trois minutes environ. Cette
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
explicite est demandée. Les VM restent en mode EDOT standalone et ne reçoivent
pas de policy Fleet de collecte ; elles peuvent être visibles dans Fleet comme
collecteurs OTel monitorés par OpAMP.
Une réinstallation doit être demandée explicitement avec la variable Ansible
`elastic_agent_reinstall=true` ; elle ne fait pas partie du chemin normal de
démarrage.

Avant toute installation de paquets, `site.yml` retire durablement la route par
défaut du réseau privé VirtualBox avec une surcharge Netplan et configure des
résolveurs IPv4 sur l’interface NAT. Les VM utilisent Ubuntu 24.04 LTS avec la
box Vagrant `bento/ubuntu-24.04`.
Sur `supermarket-middleware-01`, la même configuration conserve une route
persistante vers le réseau des pods k3s (`10.42.0.0/16` via `k3s-01`) afin que
les connexions Kubernetes vers PostgreSQL, MongoDB et Kafka aient un chemin
retour explicite. `k3s-01` classe également ce réseau dans la zone firewalld
`trusted` afin que le trafic des pods puisse sortir par son interface privée.
Le rôle `common` actualise les index APT juste avant l'installation afin d'éviter
les références à des versions retirées des miroirs Ubuntu.
Les valeurs par défaut (`1.1.1.1,8.8.8.8`) sont déclarées par `vm_dns_servers`
dans `inventory/group_vars/all.yml` et doivent être remplacées par les DNS de l'entreprise
si le réseau sortant les impose.

La cible `make stock-view` affiche le catalogue et le stock depuis PostgreSQL
sur `supermarket-middleware-01`.

Le receiver PostgreSQL OTel émet aussi les événements `db.server.query_sample`
et `db.server.top_query`. L'extension `pg_stat_statements` est créée dans la
base applicative et dans la base `postgres`, que le receiver utilise pour les
top queries. Le collecteur backend les indexe en mode OTel natif, comme tous
ses flux (ADR-012), afin qu'ils arrivent dans `logs-postgresqlreceiver.otel-*`,
le data stream lu par les dashboards du package `postgresql_otel`. Contrôle :
`make postgresql-otel-dashboards-verify`.

Lors du premier provisionnement, les images Elastic sont pré-téléchargées sur
`elk-01` avant le démarrage des unités Quadlet : un téléchargement sous systemd
dépasse son délai de démarrage. Derrière un proxy TLS (`ZSCALER_CA_CERT`
défini), le certificat racine est aussi monté dans Kibana
(`NODE_EXTRA_CA_CERTS`) pour l'accès au registre des packages Fleet.

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

Après une modification de la configuration du collecteur backend, utiliser
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
| `otel-edge-01` | Collecteur Edge (Contrib) ; HAProxy | OTLP Kubernetes et VM → Kafka |
| `elk-01` | Elasticsearch, APM Server, Kibana, Fleet Server | Stockage, ingestion des traces, consultation et enrôlement |
| `k3s-01` | Serveur k3s | Cluster Kubernetes et workloads du lab |

## Version du Kafka OTel

Le broker Kafka OTel d'`otel-backend-01` utilise `apache/kafka:4.4.0`, monté
en place depuis `3.9.2` sur le volume `otel-kafka-data`. Le
`metadata.version` du cluster KRaft reste à `3.9-IV0` : il n'est pas finalisé,
ce qui conserve un retour arrière possible vers `3.9.2` en restaurant l'image
dans `roles/otel_backend/templates/kafka.container.j2`. Le Kafka métier de
`supermarket-middleware-01` reste en `3.9.2`.

## Routage des data streams par topic Kafka

Le dataset nomme l'application ou la plateforme, le namespace l'environnement
([ADR-010](../docs/ADR-010-dataset-application-namespace-environnement.md)).
Le nom du topic porte toute la cible : le collecteur backend la lit et la
reporte sur chaque ressource
([ADR-007](../docs/ADR-007-namespace-data-stream-par-topic.md), note du
2026-11-02) :

| Topic consommé | Logs et métriques | Traces (APM Server) |
| --- | --- | --- |
| `otel-logs`, `otel-metrics`, `otel-traces` | dataset et namespace de la source, sinon receiver et `default` | idem |
| `otel-<signal>-<namespace>` | `data_stream.namespace` = `<namespace>` | `data_stream.namespace` = `<namespace>` |
| `otel-<signal>-<dataset>-<namespace>` | `data_stream.dataset` = `<dataset>`, `data_stream.namespace` = `<namespace>` | `data_stream.namespace` et `apm.route.namespace` = `<dataset>_<namespace>` |

Chemin : producteur → topic du Kafka OTel → receiver `kafka/otlp`
(souscription par regex) → `resource/kafka-topic` (copie de `kafka.topic`)
→ `transform/data-stream-route` (`ExtractPatterns` sur le topic, puis
suppression de `otel.kafka.topic`) → exporteur Elasticsearch ou APM Server.
Le backend ne lit pas l'environnement de la ressource et ne normalise rien :
le format du topic contraint les noms (dataset `[a-z0-9_.]` sans `-`,
namespace `[a-z0-9_]`). Un topic hors de ces formes ne pose rien.

Tous les flux sont en mode de mapping OTel : l'exporteur ajoute `.otel` au
dataset des logs et des métriques
([ADR-012](../docs/ADR-012-logs-otel-natifs-sans-ecs.md)). Les logs des VM
arrivent ainsi dans `logs-generic.otel-default` et les logs internes des
collecteurs dans `logs-collectortelemetry.otel-default`.

### Topics choisis par le collecteur Edge

Le collecteur Edge choisit le topic de chaque ressource
([ADR-009](../docs/ADR-009-namespaces-supermarche-et-k8s.md)). Le
processor `transform/kafka-topic` pose `otel.kafka.topic`, lu par
`topic_from_attribute` de l'exporteur Kafka ; sans attribut, le topic de base
s'applique. La table de routage de `inventory/group_vars/otel_edge_nodes.yml`
est le seul endroit qui fixe la cible d'un flux :

```yaml
otel_edge_application_routes:
  - kubernetes_namespace: h0tl-supermarche-app
    kafka_topic: supermarche-homologation   # <dataset>-<namespace>
    platform: k3s-01                        # k8s.cluster.name
    environment: homologation               # deployment.environment.name
otel_edge_kubernetes_route:
  kafka_topic: homologation                 # <namespace>
```

Le rôle `otel_edge` vérifie le format (`[a-z0-9_]` de part et d'autre du
`-`) et l'unicité des topics avant de déployer la configuration, ainsi que
la présence de `platform` et d'`environment`, égal au `<namespace>` du topic.

Pour les applications déployées, l'Edge est la référence de la plateforme et
de l'environnement : il pose `k8s.cluster.name` = `platform` et
`deployment.environment.name` = `environment` sur toute ressource de la
route, en écrasant la valeur envoyée. Les manifests applicatifs ne déclarent
plus `deployment.environment.name`. APM Server en tire `service.environment`.

| Ressource reçue par l'Edge | Topic | Data stream |
| --- | --- | --- |
| Log avec `k8s.namespace.name` = `h0tl-supermarche-app` (agent OTel) | `otel-logs-supermarche-homologation` | `logs-supermarche.otel-homologation` |
| Métrique avec `otel.edge.source` = `kubernetes` | `otel-metrics-homologation` | `metrics-<receiver>.otel-homologation` |
| Métrique avec `k8s.namespace.name` = `h0tl-supermarche-app` | `otel-metrics-supermarche-homologation` | `metrics-supermarche.otel-homologation` |
| Trace avec `k8s.namespace.name` = `h0tl-supermarche-app` | `otel-traces-supermarche-homologation` | `traces-apm-supermarche_homologation`, `logs-apm.error-supermarche_homologation`, `metrics-apm.<métrique>.1m-supermarche_homologation` |
| Log avec `otel.edge.source` = `kubernetes` (autre namespace, si un receiver `filelog` est rétabli) | `otel-logs-homologation` | `logs-<receiver>.otel-homologation` |
| Autre ressource (VM, Edge, Fleet) | topic de base | inchangé, namespace `default` |

Avant le choix du topic, l'Edge supprime les attributs de routage fournis
par le client : `otel.kafka.topic`, `data_stream.namespace` et
`apm.route.namespace` sur toute ressource, `data_stream.dataset` sur toute
ressource routée ou qui porte `k8s.namespace.name`. Les agents EDOT des VM
gardent ainsi le dataset `collectortelemetry` de leur télémétrie interne.

Les traces gardent les datasets `apm`, `apm.error` et `apm.*` d'APM Server.
Leur namespace porte donc l'application et l'environnement
(`<dataset>_<namespace>`), recopié dans `apm.route.namespace`. APM Server en
fait le label global `apm_route_namespace`, reporté sur ses métriques
agrégées. Le pipeline Elasticsearch `apm-route-namespace`, appelé par les
pipelines `@custom` des data streams APM, range ces agrégats dans ce
namespace et retire le label de tous les documents APM
(`make apm-ingest-pipelines-deploy`). Une trace d'un topic à un seul segment
(Kubernetes) ou de base (VM) n'a pas ce label.

Les signaux Kubernetes gardent le dataset de leur receiver
(`kubeletstatsreceiver`, `k8sclusterreceiver`, `hostmetricsreceiver`,
`prometheusreceiver`), lu par les dashboards Fleet `[Kubernetes OTel]`. Les
collecteurs Kubernetes posent le marqueur `otel.edge.source=kubernetes`,
supprimé par l'Edge. Un log suit le namespace de son pod, une métrique ou une
trace suit son émetteur : les métriques `kubeletstats` d'un pod applicatif
vont donc dans `metrics-kubeletstatsreceiver.otel-homologation`.

Les six topics routés sont créés par le job `otel-telemetry-topics`, avec
trois partitions et la rétention d'un jour des topics de base. Les
collecteurs Kubernetes n'émettent que des métriques ; les topics de logs et
de traces de leur route servent un receiver `filelog` rétabli. Un autre
producteur peut publier directement dans un topic du Kafka OTel
(`192.168.33.20:9092`, SASL PLAIN, compte `otel_publisher`) et choisit ainsi
sa cible. Le broker crée alors le topic avec ses valeurs par défaut, jusqu'au
passage de `make retention-deploy`, et le backend le découvre en moins d'une
minute.

Vérification après publication (remplacer `<namespace>`) :

```bash
vagrant ssh otel-backend-01 -c 'sudo podman exec -e KAFKA_OPTS= observability-otel-kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config /opt/kafka/config/otel-kafka-client.properties --describe --group otel-backend'
```

Le topic doit apparaître avec un retard nul, puis
`GET _data_stream/*-<namespace>` dans Kibana Dev Tools doit lister les data
streams correspondants.

### Nom des spans HTTP client

Dans le pipeline `traces`, le processor `transform/http-client-span-name`
précède `transform/kafka-topic`
([ADR-011](../docs/ADR-011-nom-des-spans-http-client.md)). Il renomme tout
span `CLIENT` qui porte `url.full` et dont le nom se réduit à la méthode
HTTP : `POST` devient `POST /api/reservations`. Les segments identifiants
(nombre, UUID, hexadécimal long, code majuscule avec chiffre) deviennent
`{id}`. La règle vaut pour toutes les ressources reçues par l'Edge ; elle ne
filtre aucun span et ne modifie aucun attribut.

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

`site.yml` est l'unique point d'entrée du provisionnement général. Chaque rôle
possède ses propres templates afin que la tâche et la configuration déployée
restent au même endroit.

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
