# POC observabilité : Elastic, Kafka, MongoDB, PostgreSQL et applications

Ce dépôt déploie un environnement de recette destiné à valider la visibilité
de bout en bout dans Elastic : infrastructure, Kafka, MongoDB, PostgreSQL et deux
applications Java instrumentées avec Elastic APM et OpenTelemetry.

## Architecture

| Composant | Implantation | Configuration principale | Données observées |
| --- | --- | --- | --- |
| Elasticsearch, Kibana, APM Server et Fleet Server | Kubernetes, namespace `elastic-stack` | Elastic Stack 8.11.3, pilotée par ECK 3.5.0, TLS ECK, accès Traefik | APM, logs et métriques |
| `data-01` à `data-03` | Vagrant / Rocky Linux 10 | `192.168.33.10` à `.12`, 1 vCPU et 1,5 Gio par VM ; aucun collecteur EDOT | journaux et métriques selon le profil Beats/Fleet |
| MongoDB | un conteneur Podman par VM | replica set `poc-rs`, port 27017 | logs et métriques MongoDB |
| PostgreSQL | conteneur Podman sur `data-01` uniquement | base `observability_test`, port 5432 | logs et métriques PostgreSQL |
| Kafka | un broker/controller KRaft par VM | réplication 3, `min.insync.replicas=2`, port 9092 | logs, métriques broker, partitions, groupes et JMX |
| `order-service` | Kubernetes, namespace `supermarket-demo` | service HTTP 3000, producteur Kafka | transactions et dépendance Kafka |
| `inventory-service` | Kubernetes, namespace `supermarket-demo` | service HTTP 3001, consommateur Kafka, MongoDB et PostgreSQL | transactions, dépendances Kafka, MongoDB et PostgreSQL |

Le scénario métier simule un supermarché en ligne : `order-service` publie une
commande Kafka chaque minute (commande en ligne) ; `inventory-service` la
consomme, décrémente le stock du produit puis écrit le résultat dans MongoDB et
PostgreSQL (`data-01`). L’endpoint `/api/orders` exerce également le chemin
HTTP synchrone entre les deux applications (commande passée en caisse).

## Guides de lecture

Avant de modifier une configuration, suivre les README locaux :

- [`platform/README.md`](platform/README.md) : point d'entrée de la plateforme ;
- [`platform/elk/README.md`](platform/elk/README.md) : chaîne de télémétrie
  Elastic et ses sous-répertoires ;
- [`apps/README.md`](apps/README.md) : séparation entre plateforme et workloads ;
- [`ansible/README.md`](ansible/README.md) : infrastructure des VM et templates ;
- [`scripts/README.md`](scripts/README.md) : outils de diagnostic partagés.
- [`docs/README.md`](docs/README.md) : objectifs du POC, architecture des
  signaux, comparatif des intégrations et matrices de recette.

Ces documents listent un ordre de lecture, les commandes associées et les
références officielles nécessaires pour comprendre les choix de configuration.

## Organisation du dépôt

```
platform/elk/       # Kubernetes ELK, Fleet, dashboards et scripts Elastic
apps/supermarket-demo/  # code Java, Dockerfile et manifests de l'application
ansible/             # infrastructure partagée des VM MongoDB/Kafka/PostgreSQL
scripts/             # utilitaires partagés aux VM
```

Les cibles `make elk-deploy` et `make apps-deploy` permettent de déployer les
deux périmètres séparément ; `make apm-deploy` reste disponible comme alias de
compatibilité pour les déployer ensemble. `make apm-deploy` et
`make platform-deploy` attendent Elasticsearch, synchronisent l'API key du
gateway OpenTelemetry, puis créent le gateway avant les applications. Pour
déployer l'architecture complète (Kubernetes, VM et applications), utiliser
`make deploy` (ou son alias `make architecture-deploy`).

## Prérequis

- VirtualBox et Vagrant ;
- Ansible Core et la collection `ansible.posix` sur l’hôte de provisionnement :

  ```bash
  ansible-galaxy collection install -r ansible/requirements.yml
  ```
- un cluster Kubernetes avec Traefik ; `make eck-deploy` installe ou met à jour
  l’opérateur ECK 3.5.0 avant le déploiement des ressources Elastic ;
- une image locale multi-stage `order-service:1.0.4` / `inventory-service:1.0.4`
  disponible pour les nœuds Kubernetes ;
- une résolution, depuis l’hôte et les VM, de `*.poc.test` vers l’Ingress
  Traefik. Les scripts VM ajoutent ces noms vers `192.168.33.1`.

Les certificats publics ne sont pas inclus : créer le secret TLS
`elastic-public-tls` dans `elastic-stack` avant d’appliquer les IngressRoutes.
Les secrets ECK, notamment `apm-server-apm-token`, sont créés et gérés par ECK.
Créer également une clé API Elasticsearch ayant les droits d’écriture sur les
data streams `logs-*` et `metrics-*`; elle est fournie à Vagrant par
`ELASTICSEARCH_API_KEY` et n’est jamais versionnée.

Le mot de passe PostgreSQL est également hors Git. Exporter
`POSTGRESQL_PASSWORD` depuis un gestionnaire de secrets : la cible
`make postgresql-credentials-apply` le crée dans les namespaces concernés.

Les opérations courantes sont regroupées dans le `Makefile` : `make help`
affiche les cibles disponibles, sous la convention `ressource-action`, notamment
`make elastic-password-show`, `make apm-token-show`,
`make apm-report-api-key-create`, `make elasticsearch-api-key-create`,
`make platform-deploy` et `make vm-provision`.
`make apm-report-api-key-create` renvoie une clé de lecture APM brute au format
`id:api_key`, que SystemLens encode lui-même pour l'en-tête HTTP.

```bash
export SYSTEMLENS_ELASTICSEARCH_API_KEY="$(make --no-print-directory apm-report-api-key-create)"
```

`make elasticsearch-api-key-create` renvoie une clé encodée en Base64 pour
`SYSTEMLENS_ELASTICSEARCH_API_KEY` ; utiliser `make beats-api-key-create` pour
obtenir le format brut `id:api_key` attendu par Filebeat et Metricbeat.
Pour charger les secrets nécessaires dans le shell courant sans les afficher,
utiliser `source ./platform/elk/scripts/load-credentials.sh` (ou `make credentials-show` pour
afficher cette commande).

### Machine derrière un proxy TLS d'entreprise (Zscaler)

Sur une machine sans interception TLS, aucune action n'est requise : ce dépôt
fonctionne tel quel. Si un proxy comme Zscaler intercepte le trafic HTTPS
sortant (build Docker, pull d'images k3d, provisionnement Vagrant/Ansible),
placer le certificat racine au format PEM dans `certs/` puis exporter
`ZSCALER_CA_CERT` avant les commandes concernées :

```bash
cp /chemin/vers/ZscalerRootCertificate.pem certs/zscaler-root-ca.crt
export ZSCALER_CA_CERT=certs/zscaler-root-ca.crt

make apps-build        # confiance injectée dans le build Maven/Docker
make k3d-ca-import      # confiance injectée dans les nœuds k3d, puis :
k3d cluster stop elastic && k3d cluster start elastic
vagrant up              # ou `vagrant provision` : confiance installée sur les VM
```

Voir [`certs/README.md`](certs/README.md) pour le détail des mécanismes
(build-arg Docker encodé en base64, import dans les nœuds k3d via
`update-ca-certificates`, et `update-ca-trust` côté VM Rocky Linux).


## Déploiement

Pour un déploiement complet, une seule commande suffit après avoir renseigné
le token Fleet si les intégrations MongoDB/Kafka/PostgreSQL des VM doivent être
enrôlées :

```bash
export FLEET_ENROLLMENT_TOKEN='…' # optionnel : intégrations Fleet MongoDB/Kafka/PostgreSQL
export POSTGRESQL_PASSWORD='…'
make deploy
```

La cible applique d'abord la plateforme Kubernetes, attend Elasticsearch,
charge ensuite (ou crée) une clé API Elasticsearch limitée aux Beats, lance
`vagrant up`, puis construit,
importe dans k3d et déploie les deux applications. Une clé déjà fournie dans
`ELASTICSEARCH_API_KEY` n'est pas remplacée.

1. Créer les VM et les clusters de données. Vagrant appelle le playbook
   `ansible/site.yml`, idempotent, qui configure le réseau, les unités Quadlet
   MongoDB/Kafka/PostgreSQL, les limites mémoire, Filebeat et Metricbeat sur
   les VM correspondant au profil Beats. La clé API
   Elasticsearch n’est jamais enregistrée dans Git : la fournir seulement dans
   l’environnement de la commande.

   ```bash
   export ELASTICSEARCH_API_KEY='id:api_key'
   # Token d'enrôlement unique de la policy Fleet `mongodb-hosts`.
   # Cette policy est déclarée dans le manifest Kibana Kubernetes.
   export FLEET_ENROLLMENT_TOKEN='…'
   vagrant up
   ./scripts/cluster-status.sh
   ```

   Chaque VM installe MongoDB 8.0 et Kafka 3.9.2 sous Podman ; `data-01`
   installe aussi PostgreSQL 17. Les services sont gérés via des unités
   systemd Quadlet. Ansible ouvre uniquement les ports inter-nœuds nécessaires
   et démarre Filebeat et Metricbeat sur `data-03`. Aucun collecteur EDOT
   n'est installé. Avec le token Fleet, les intégrations MongoDB/Kafka
   dédiées aux métriques métier restent actives.

Chaque conteneur MongoDB, Kafka et PostgreSQL est plafonné à `512 Mio`. Kafka utilise un
heap JVM fixe de `256 Mio` et MongoDB limite le cache WiredTiger à `256 Mio`.
Ces valeurs sont volontairement adaptées au faible volume du POC ; les relever
avant une charge soutenue ou un volume de données significatif.

### Jolokia et JConsole

Après `vagrant up` ou `vagrant provision`, les endpoints Kafka sont exposés
uniquement sur la boucle locale de l'hôte :

| VM | Jolokia | JConsole (JMX/RMI) |
| --- | --- | --- |
| `data-01` | `http://127.0.0.1:18781/jolokia` | `service:jmx:rmi:///jndi/rmi://127.0.0.1:19991/jmxrmi` |
| `data-02` | `http://127.0.0.1:18782/jolokia` | `service:jmx:rmi:///jndi/rmi://127.0.0.1:19992/jmxrmi` |
| `data-03` | `http://127.0.0.1:18783/jolokia` | `service:jmx:rmi:///jndi/rmi://127.0.0.1:19993/jmxrmi` |

JConsole ne peut pas se connecter directement à Jolokia, qui est une API HTTP.
Utiliser l'URL JMX/RMI correspondante et laisser les identifiants vides. Cette
configuration sans authentification ni TLS est réservée à ce POC : les ports
ne sont publiés que sur `127.0.0.1` de la machine hôte.

Kibana est volontairement traité à part : Fleet et les assets APM demandent
davantage de mémoire au démarrage. Sa limite est de `2 Gio` et le heap Node.js
est borné à `1280 Mio` (`NODE_OPTIONS=--max-old-space-size=1280`) afin d'éviter
une erreur `JavaScript heap out of memory` tout en gardant une marge pour les
allocations natives.

2. Déployer la partie Elastic et les applications. Kubernetes est rendu par
   Kustomize ; la ressource Kibana est entièrement gérée dans le dépôt. Son nom
   `es-kb-quickstart-eck-kibana` doit rester cohérent avec les références Fleet
   et APM.
   Les artefacts sont séparés par responsabilité : `platform/elk/` contient
   toute la plateforme Elastic (manifests Kubernetes, Fleet, dashboards et
   scripts), tandis que `apps/supermarket-demo/` contient le code et les
   manifests de l'application de démonstration. Les collecteurs OpenTelemetry
   sont dans la plateforme ELK : ils constituent la chaîne d'ingestion, pas
   l'application.

   ```bash
   kubectl apply -k platform/kubernetes/overlays/local
   kubectl apply -k apps/supermarket-demo/kubernetes
   kubectl -n elastic-stack get elasticsearch,kibana,apmserver,agent
   kubectl -n supermarket-demo get deploy,pods,svc
   ```

3. La configuration Fleet MongoDB/Kafka/PostgreSQL est déclarée dans
   `platform/kubernetes/base/observability/kibana.yaml` et est appliquée avec
   Kibana. Depuis l'hôte, ne synchroniser que les pipelines Elasticsearch
   complémentaires :

   ```bash
   export KIBANA_PASSWORD='…'
   ./platform/elk/scripts/sync-fleet-policies.sh
   ```

   Le script installe le pipeline `metrics-kafka.topic@custom`, les pipelines
   Kafka associés et crée la package policy PostgreSQL si elle est absente. Les dashboards s'importent séparément avec
   `make dashboard-deploy`. Les policies Fleet MongoDB/Kafka restent visibles
   et gérées par la préconfiguration Kibana déclarée dans Kubernetes.

### Redéployer et corriger

Le playbook est idempotent : un simple `vagrant provision` applique les
modifications sans recréer les conteneurs lorsque leur configuration ne change
pas. Pour redéployer explicitement MongoDB, Kafka et PostgreSQL après une correction, tout
en conservant les volumes `mongodb-data` et `kafka-data`, utiliser :

```bash
POC_REDEPLOY_SERVICES=true vagrant provision
```

La relance recrée les conteneurs à partir des unités Quadlet, attend MongoDB et PostgreSQL,
réinitialise seulement si nécessaire le replica set et réajoute idempotemment
les membres. Le playbook installe le
certificat public d’Elasticsearch dans le magasin de confiance système de
chaque VM avant de démarrer les collecteurs ; cette opération est gérée
uniquement par Ansible. Pour un environnement non-POC, déployer une PKI de
confiance.

Les artefacts Jolokia et Beats sont conservés sous
`/opt/poc-observability` et `/var/cache/poc-observability`. Ansible utilise
`force: false` : une nouvelle exécution ne télécharge donc pas une version déjà
présente ; seul un changement de version des Beats déclenche un nouveau
téléchargement.

## Configurations d’observabilité réalisées

- Tracing et logs applicatifs : `order-service` charge l’agent Java Elastic et
  envoie ses traces directement à APM Server en HTTPS, avec le token et le
  certificat ECK synchronisés dans le namespace applicatif par
  `make apps-deploy`. `inventory-service` conserve l’agent Java OpenTelemetry,
  son identité de service et son endpoint OTLP HTTP/protobuf vers le gateway.
  Le gateway enrichit les traces d’`inventory-service` puis les publie au format
  `otlp_proto` dans le topic Kafka dédié `otel-traces`. Deux collectors backend
  du même consumer group les relisent, produisent les métriques APM agrégées et
  les exportent vers Elasticsearch en TLS, avec une clé API dédiée et limitée
  aux data streams `logs-*`, `metrics-*` et `traces-*`. Les métriques OTLP des
  applications continuent d'être exportées directement par le gateway.
  Kafka absorbe donc les indisponibilités courtes d'Elasticsearch, au prix d'un
  délai possible avant l'apparition des traces dans APM. Le topic est créé avec
  trois partitions, réplication 3, `min.insync.replicas=2` et une rétention de
  24 heures.
  Le processeur `cumulativetodelta` conserve les histogrammes Micrometer. L’encodeur Logback ECS produit du JSON avec ces mêmes champs ;
  le MDC du Java agent y ajoute les identifiants de trace. L’Agent Kubernetes
  les normalise en `trace.id` et `span.id` avant indexation pour naviguer d’un
  log à la trace correspondante. Les métriques Actuator/Micrometer sont exportées
  par OTLP directement vers APM Server ; les logs restent collectés sur stdout
  par Elastic Agent, donc l’exporteur OTLP Logs est explicitement désactivé.
- Logs Kubernetes : un Elastic Agent DaemonSet lit les logs de conteneurs du
  namespace `supermarket-demo`, décode les logs JSON ECS et ajoute les métadonnées
  Kubernetes.
- MongoDB : l’intégration Fleet collecte `collstats`, `dbstats`, `metrics`,
  `replstatus` et `status` toutes les 60 s.
- Kafka : l’intégration interroge le broker local et Jolokia local
  (`127.0.0.1:8778`) pour les métriques KRaft, JVM, réseau,
  réplication et topics. Les applications Spring publient leurs métriques JVM,
  HTTP, Kafka et métier via Actuator/Micrometer en OTLP vers APM Server ; elles
  ne dépendent pas de Jolokia. Le port Jolokia des brokers n’est pas publié sur
  le réseau privé.
  Les événements Jolokia sont étiquetés avec l’IP de la VM dans
  `service.address`, jamais avec l’adresse locale de scrape.
- PostgreSQL : il tourne seulement sur `data-01`; l'intégration Fleet collecte
  ses métriques et Filebeat y lit ses logs. L'input Fleet est conditionné
  à `data-01`, bien que la policy soit commune aux trois VM.

## Recette des dashboards

### Dashboard MongoDB : clusters et primary

Déployer ou mettre à jour le dashboard automatiquement avec :

```bash
source ./platform/elk/scripts/load-credentials.sh
make dashboard-deploy
```

La commande importe [`mongodb-cluster-primary.ndjson`](platform/elk/dashboards/mongodb-cluster-primary.ndjson)
dans Kibana et remplace les objets SystemLens existants. Le dashboard
**SystemLens · MongoDB clusters** affiche un replica set par ligne, son primary
issu du relevé `mongodb.replstatus` le plus récent, et l'horodatage de ce
relevé. Il restaure une fenêtre de temps de 24 heures et se rafraîchit toutes
les minutes.

Générer de l’activité avant la recette : ouvrir `https://kibana.poc.test`,
puis appeler l’endpoint de l’application via son Service/Ingress disponible.
Une requête vers `/api/work` doit produire le chemin HTTP puis une écriture
MongoDB ; le job planifié produit le chemin Kafka chaque minute. `/api/error`
doit créer une erreur APM contrôlée.

| Vue Kibana | Contrôles attendus | Diagnostic si absent |
| --- | --- | --- |
| Observability > APM > Services | les deux services, transactions HTTP, planifiées et messaging ; dépendances Kafka/MongoDB/PostgreSQL ; erreur de démonstration | vérifier le secret/token APM, l’URL `apm-server-apm-http`, les pods et le trafic généré |
| Observability > Infrastructure > Hosts | hôtes suivis par le profil Beats/Fleet | vérifier le service de collecte correspondant ; aucun service EDOT ne doit être présent |
| Observability > Infrastructure > Inventory / logs | logs `kubernetes.container_logs` des deux pods, métadonnées Kubernetes et champs ECS | vérifier le DaemonSet `kubernetes-logs`, ses RBAC et les montages `/var/log` |
| Intégration MongoDB | trois hôtes, état du replica set, connexions, opérations, stockage et logs MongoDB | exécuter `./scripts/cluster-status.sh`, contrôler `mongodb-fleet` et l’accès local à `localhost:27017` |
| Intégration Kafka | trois brokers, contrôleurs KRaft, partitions, groupes, JVM/réseau/réplication et logs Kafka | contrôler le quorum avec `cluster-status.sh`, le conteneur `poc-kafka` et Jolokia sur `127.0.0.1:8778` |
| PostgreSQL | `data-01`, activité, bgwriter, taille de base et logs | contrôler `poc-postgresql`, `logs-postgresql.log-*` et `metrics-postgresql.*` |

Une validation est réussie si aucun service `poc-otel-collector` n'est présent,
si les collecteurs Beats/Fleet attendus sont actifs, si les trois
membres MongoDB sont `PRIMARY`/`SECONDARY`, si PostgreSQL est disponible sur `data-01`, et si le quorum Kafka présente trois
voters, les deux services APM reçoivent des données et toutes les vues ci-dessus
contiennent des événements récents. Pour isoler une panne, commencer par
`./scripts/cluster-status.sh`, puis Fleet > Agents et enfin les logs du pod ou
conteneur concerné.

### Statut des clusters avec Ansible

Depuis la racine du dépôt, la commande suivante vérifie les conteneurs sur les
trois VM, affiche les membres et rôles du replica set MongoDB, l'état du quorum
Kafka KRaft, le lag du groupe `inventory-service` et le dernier traitement Kafka
persisté dans MongoDB et PostgreSQL :

```bash
ansible-playbook -i ansible/inventory/vagrant.yml ansible/status.yml
```

Pour Kafka 3.9, appliquer également le correctif Raft suivant : il retire
l'attribut JMX absent `number-of-voters` afin que le champ `current_leader`
soit indexé et visible dans la vue Raft.

```bash
ELASTICSEARCH_PASSWORD='…' ansible-playbook ansible/kafka-raft-pipeline.yml
```

L’inventaire utilise les ports SSH et clés privées générés par Vagrant ; il est
donc valide après un `vagrant up` et doit être exécuté depuis la racine du
dépôt.

### Policy Fleet commune aux VM

La policy `mongodb-hosts` et ses intégrations MongoDB/Kafka sont déclarées dans
`platform/kubernetes/base/observability/kibana.yaml`. Les trois Agents sur
`data-01`, `data-02` et `data-03` doivent être enrôlés avec le **même** token de
cette policy. Comme chaque Agent collecte `localhost`, les métriques restent
correctement attribuées à leur VM avec `host.name` et `service.address`.

Pour migrer des Agents déjà inscrits dans des policies historiques vers cette
policy commune, exécuter :

```bash
KIBANA_PASSWORD='…' ansible-playbook ansible/fleet-policies.yml
```

Le playbook ne crée ni policy ni package policy : Kubernetes reste la source de
vérité. Il cible par défaut l’Ingress local `127.0.0.1` avec le nom d’hôte
`kibana.poc.test`. Si Kibana est exposé ailleurs, remplacer ces valeurs sans
modifier le playbook :

```bash
KIBANA_URL='https://kibana.exemple.test' KIBANA_HOST='kibana.exemple.test' \
  KIBANA_PASSWORD='…' ansible-playbook ansible/fleet-policies.yml
```

## Constat de validation du 17 août 2026

Les ressources Kubernetes ECK (Kibana, APM Server, Fleet Server et Agent de
logs) sont `green` et les deux applications sont `Ready`. Elasticsearch est
opérationnel mais `yellow` car il ne possède qu’un nœud : les réplicas non
alloués sont attendus dans cette topologie de POC, mais cet état ne convient pas
à une validation de haute disponibilité.

Kafka est déployé exclusivement sur les trois VM Vagrant (`data-01` à
`data-03`). Il n'existe volontairement aucun Deployment ou Service Kafka dans
Kubernetes : les applications doivent joindre les brokers
`192.168.33.10:9092` à `.12:9092`. Cette règle évite qu'un Kafka mono-nœud de
test dans Kubernetes masque une erreur de connectivité ou de réplication du
cluster KRaft de référence.

La recette fonctionnelle doit donc valider un cycle complet
producteur → Kafka sur VM → consommateur → MongoDB + PostgreSQL. Tout `TimeoutException`,
`DisconnectException`, `UNKNOWN_TOPIC_OR_PARTITION` ou échec de commit Kafka
est un défaut à corriger sur ce chemin, et non un motif pour basculer vers un
broker Kubernetes.

La validation du 17 août confirme que les trois VM sont joignables en SSH et
que les pods Kubernetes atteignent les trois brokers Kafka (`9092`) et les trois
membres MongoDB (`27017`) et PostgreSQL (`data-01:5432`) sur le réseau VirtualBox `192.168.33.0/24`. Rejouer
la recette après chaque redéploiement afin de vérifier la production, la
consommation et la persistance du message, pas seulement l'ouverture des ports.

## Correction appliquée

Les IngressRoutes utilisent un `ServersTransport` dédié à chaque service ECK.
Ils référencent les secrets `*-http-certs-public`, qui portent bien la clé
`ca.crt` attendue par Traefik. Les secrets `*-http-ca-internal` ne contiennent
que `tls.crt` et `tls.key` : les utiliser comme CA provoque une erreur TLS et
des réponses HTTP 500. L’IngressRoute Kibana référence également
`eck-kibana-https`, le transport dédié, et non l’ancien transport générique.
