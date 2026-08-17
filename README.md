# POC observabilité : Elastic, Kafka, MongoDB et applications

Ce dépôt déploie un environnement de recette destiné à valider la visibilité
de bout en bout dans Elastic : infrastructure, Kafka, MongoDB et deux
applications Java instrumentées APM.

## Architecture

| Composant | Implantation | Configuration principale | Données observées |
| --- | --- | --- | --- |
| Elasticsearch, Kibana, APM Server et Fleet Server | Kubernetes, namespace `elastic-stack` | ECK 9.5.1, TLS ECK, accès Traefik | APM, logs et métriques |
| `data-01` à `data-03` | Vagrant / Rocky Linux 10 | `192.168.33.10` à `.12`, 1 vCPU et 1,5 Gio par VM | métriques System, journaux système |
| MongoDB | un conteneur Podman par VM | replica set `poc-rs`, port 27017 | logs et métriques MongoDB |
| Kafka | un broker/controller KRaft par VM | réplication 3, `min.insync.replicas=2`, port 9092 | logs, métriques broker, partitions, groupes et JMX |
| `apm-demo` | Kubernetes, namespace `apm-demo` | service HTTP 3000, producteur Kafka | transactions et dépendance Kafka |
| `apm-demo-worker` | Kubernetes, namespace `apm-demo` | service HTTP 3001, consommateur Kafka, MongoDB | transactions, dépendances Kafka et MongoDB |

Le flux applicatif est : `apm-demo` publie une tâche Kafka chaque minute ;
`apm-demo-worker` la consomme puis écrit le résultat dans MongoDB. L’endpoint
`/api/work` exerce également le chemin HTTP entre les deux applications.

## Prérequis

- VirtualBox et Vagrant ;
- Ansible Core et la collection `ansible.posix` sur l’hôte de provisionnement :

  ```bash
  ansible-galaxy collection install -r ansible/requirements.yml
  ```
- un cluster Kubernetes avec l’opérateur ECK, Traefik et les ressources
  Elasticsearch/Kibana initiales dans `elastic-stack` ;
- une image locale multi-stage `apm-demo:1.0.0` / `apm-demo-worker:1.0.0`
  disponible pour les nœuds Kubernetes ;
- une résolution, depuis l’hôte et les VM, de `*.poc.test` vers l’Ingress
  Traefik. Les scripts VM ajoutent ces noms vers `192.168.33.1`.

Les certificats publics ne sont pas inclus : créer le secret TLS
`elastic-public-tls` dans `elastic-stack` avant d’appliquer les IngressRoutes.
Les secrets ECK, notamment `apm-server-apm-token`, sont créés et gérés par ECK.

## Déploiement

1. Créer les VM et les clusters de données. Vagrant appelle le playbook
   `ansible/site.yml`, idempotent, qui configure le réseau, les unités Quadlet
   MongoDB/Kafka, les limites mémoire et Elastic Agent. Le token Fleet n’est
   jamais enregistré dans Git : le fournir seulement dans l’environnement de
   la commande.

   ```bash
   export FLEET_ENROLLMENT_TOKEN='…'
   vagrant up
   ./scripts/cluster-status.sh
   ```

   Chaque VM installe MongoDB 8.0 et Kafka 3.9.2 sous Podman, via des unités
   systemd Quadlet. Ansible ouvre uniquement les ports inter-nœuds nécessaires
   et enrôle l’agent dans la policy Fleet `mongodb-hosts`.

Chaque conteneur MongoDB et Kafka est plafonné à `512 Mio`. Kafka utilise un
heap JVM fixe de `256 Mio` et MongoDB limite le cache WiredTiger à `256 Mio`.
Ces valeurs sont volontairement adaptées au faible volume du POC ; les relever
avant une charge soutenue ou un volume de données significatif.

Kibana est volontairement traité à part : Fleet et les assets APM demandent
davantage de mémoire au démarrage. Sa limite est de `2 Gio` et le heap Node.js
est borné à `1280 Mio` (`NODE_OPTIONS=--max-old-space-size=1280`) afin d'éviter
une erreur `JavaScript heap out of memory` tout en gardant une marge pour les
allocations natives.

2. Déployer la partie Elastic et les applications. Appliquer le patch Kibana
   après la ressource Kibana de base ; son nom doit être
   `es-kb-quickstart-eck-kibana` ou être adapté dans les manifestes concernés.

   ```bash
   kubectl apply -f kubernetes/elasticsearch-resources.yaml
   kubectl apply -f kubernetes/kibana-fleet-patch.yaml
   kubectl apply -f kubernetes/fleet-server.yaml
   kubectl apply -f kubernetes/apm-server.yaml
   kubectl apply -f kubernetes/elastic-ingress.yaml
   kubectl apply -f kubernetes/kubernetes-logs-agent.yaml
   kubectl apply -f kubernetes/apm-demo-namespace.yaml
   kubectl apply -f kubernetes/apm-demo.yaml
   kubectl -n elastic-stack get elasticsearch,kibana,apmserver,agent
   kubectl -n apm-demo get deploy,pods,svc
   ```

3. Créer ou récupérer dans Fleet un token d’enrôlement de la policy
   `mongodb-hosts`, puis exécuter `vagrant provision` si les VM existent déjà.
   Synchroniser ensuite les intégrations Fleet depuis l’hôte :

   ```bash
   export KIBANA_PASSWORD='…'
   ./scripts/sync-fleet-policies.sh
   ```

   Le script crée la policy `mongodb-hosts`, configure les packages System,
   MongoDB et Kafka, et installe le pipeline
   `metrics-kafka.topic@custom`. Il retire intentionnellement les anciennes
   policies Jolokia applicatives : leurs endpoints ne sont plus exposés hors
   du cluster.

### Redéployer et corriger

Le playbook est idempotent : un simple `vagrant provision` applique les
modifications sans recréer les conteneurs lorsque leur configuration ne change
pas. Pour redéployer explicitement MongoDB et Kafka après une correction, tout
en conservant les volumes `mongodb-data` et `kafka-data`, utiliser :

```bash
POC_REDEPLOY_SERVICES=true vagrant provision
```

La relance recrée les conteneurs à partir des unités Quadlet, attend MongoDB,
réinitialise seulement si nécessaire le replica set et réajoute idempotemment
les membres. Pour refaire également l’enrôlement Fleet, fournir un nouveau
token et activer le mode dédié :

```bash
FLEET_ENROLLMENT_TOKEN='…' ELASTIC_AGENT_FORCE_REENROLL=true \
  POC_REDEPLOY_SERVICES=true vagrant provision
```

Ce dernier mode désinstalle puis réinstalle Elastic Agent sur chaque VM ; il ne
supprime ni les données MongoDB/Kafka ni les policies Fleet.

Le certificat Fleet public du POC est auto-signé. Le playbook installe le
certificat public d’Elasticsearch dans le magasin de confiance système de
chaque VM avant de démarrer les collecteurs ; cette opération est gérée
uniquement par Ansible. `--insecure` reste limité à l’enrôlement initial.
Pour un environnement non-POC, déployer une PKI de confiance et définir
`fleet_insecure: false`.

Les artefacts Jolokia et Elastic Agent sont conservés respectivement sous
`/opt/poc-observability` et `/var/cache/poc-observability`. Ansible utilise
`force: false` : une nouvelle exécution ne télécharge donc pas une version déjà
présente ; seul un changement de version Elastic Agent déclenche un nouveau
téléchargement.

## Configurations d’observabilité réalisées

- APM : les agents Java Elastic sont chargés dans les deux images. Les services
  `apm-demo` et `apm-demo-worker`, l’environnement `local`, le token APM et
  l’URL APM Server sont injectés par les Deployments. Jolokia est exclu des
  transactions APM pour ne pas polluer les données métier.
- Logs Kubernetes : un Elastic Agent DaemonSet lit les logs de conteneurs du
  namespace `apm-demo`, décode les logs JSON ECS et ajoute les métadonnées
  Kubernetes.
- MongoDB : l’intégration Fleet lit `/var/log/mongodb/mongod.log` et collecte
  `collstats`, `dbstats`, `metrics`, `replstatus` et `status` toutes les 60 s.
- Kafka : l’intégration lit `/var/log/kafka`, interroge le broker local et
  Jolokia local (`127.0.0.1:8778`) pour les métriques KRaft, JVM, réseau,
  réplication et topics. Les métriques JMX des clients producteur et consommateur
  sont aussi collectées depuis `data-01` ; les policies Fleet par VM les
  déploient avec une condition empêchant leur exécution sur les autres VM. Le
  port Jolokia des brokers n’est pas publié sur le réseau privé.
- Système : CPU, mémoire, charge, réseau, processus, disponibilité et disques
  sont remontés ; les pseudo-systèmes de fichiers sont exclus. Les journaux
  Rocky `/var/log/messages*` et `/var/log/secure*` sont collectés.

## Recette des dashboards

Générer de l’activité avant la recette : ouvrir `https://kibana.poc.test`,
puis appeler l’endpoint de l’application via son Service/Ingress disponible.
Une requête vers `/api/work` doit produire le chemin HTTP puis une écriture
MongoDB ; le job planifié produit le chemin Kafka chaque minute. `/api/error`
doit créer une erreur APM contrôlée.

| Vue Kibana | Contrôles attendus | Diagnostic si absent |
| --- | --- | --- |
| Observability > APM > Services | les deux services, transactions HTTP, planifiées et messaging ; dépendances Kafka/MongoDB ; erreur de démonstration | vérifier le secret/token APM, l’URL `apm-server-apm-http`, les pods et le trafic généré |
| Observability > Infrastructure > Hosts | `data-01`, `data-02`, `data-03` avec CPU, mémoire, disques et réseau | vérifier dans Fleet que les trois agents sont Healthy et la policy `system-fleet` |
| Observability > Infrastructure > Inventory / logs | logs `kubernetes.container_logs` des deux pods, métadonnées Kubernetes et champs ECS | vérifier le DaemonSet `kubernetes-logs`, ses RBAC et les montages `/var/log` |
| Intégration MongoDB | trois hôtes, état du replica set, connexions, opérations, stockage et logs MongoDB | exécuter `./scripts/cluster-status.sh`, contrôler `mongodb-fleet` et l’accès local à `localhost:27017` |
| Intégration Kafka | trois brokers, contrôleurs KRaft, partitions, groupes, JVM/réseau/réplication et logs Kafka | contrôler le quorum avec `cluster-status.sh`, le conteneur `poc-kafka` et Jolokia sur `127.0.0.1:8778` |

Une validation est réussie si les trois hôtes sont sains dans Fleet, les trois
membres MongoDB sont `PRIMARY`/`SECONDARY`, le quorum Kafka présente trois
voters, les deux services APM reçoivent des données et toutes les vues ci-dessus
contiennent des événements récents. Pour isoler une panne, commencer par
`./scripts/cluster-status.sh`, puis Fleet > Agents et enfin les logs du pod ou
conteneur concerné.

### Statut des clusters avec Ansible

Depuis la racine du dépôt, la commande suivante vérifie les conteneurs sur les
trois VM, affiche les membres et rôles du replica set MongoDB, l'état du quorum
Kafka KRaft, le lag du groupe `apm-demo-worker` et le dernier traitement Kafka
persisté dans MongoDB :

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

### Policies Fleet par VM

MongoDB Overview et les vues Kafka utilisent `service.address`. Le playbook
suivant crée trois policies Fleet d'observabilité, une par VM, configure
respectivement `192.168.33.10`, `.11` et `.12` pour MongoDB (`27017`) et Kafka
(`9092`), puis réaffecte les agents en ligne à leur policy dédiée :

```bash
KIBANA_PASSWORD='…' ansible-playbook ansible/fleet-policies.yml
```

Le playbook cible par défaut l’Ingress local `127.0.0.1` avec le nom d’hôte
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
producteur → Kafka sur VM → consommateur → MongoDB. Tout `TimeoutException`,
`DisconnectException`, `UNKNOWN_TOPIC_OR_PARTITION` ou échec de commit Kafka
est un défaut à corriger sur ce chemin, et non un motif pour basculer vers un
broker Kubernetes.

La validation du 17 août confirme que les trois VM sont joignables en SSH et
que les pods Kubernetes atteignent les trois brokers Kafka (`9092`) et les trois
membres MongoDB (`27017`) sur le réseau VirtualBox `192.168.33.0/24`. Rejouer
la recette après chaque redéploiement afin de vérifier la production, la
consommation et la persistance du message, pas seulement l'ouverture des ports.

## Correction appliquée

Les IngressRoutes utilisent un `ServersTransport` dédié à chaque service ECK.
Ils référencent les secrets `*-http-certs-public`, qui portent bien la clé
`ca.crt` attendue par Traefik. Les secrets `*-http-ca-internal` ne contiennent
que `tls.crt` et `tls.key` : les utiliser comme CA provoque une erreur TLS et
des réponses HTTP 500. L’IngressRoute Kibana référence également
`eck-kibana-https`, le transport dédié, et non l’ancien transport générique.
