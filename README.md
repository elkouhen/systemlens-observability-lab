# Intégration MongoDB vers Elastic Fleet

Ce POC collecte les logs et métriques d'un replica set MongoDB et d'un cluster
Kafka KRaft répartis sur trois VMs Rocky Linux, avec Elastic Agent 9.5.1 géré
par Fleet. Elasticsearch, Kibana, Fleet
Server et APM Server sont déployés par ECK dans k3d et exposés par Traefik.

Le mode standalone historique reste disponible dans
[`elastic-agent/elastic-agent.yml`](elastic-agent/elastic-agent.yml), mais le
parcours principal du projet utilise désormais Fleet.

## Architecture

```text
data-01, data-02, data-03
MongoDB replica set :27017 + Kafka KRaft :9092
        │ logs + métriques
        ▼
Elastic Agent 9.5.1 (data-01 à data-03)
        │                               │
        │ check-in et politique         │ événements
        ▼                               ▼
Fleet Server :443                 Elasticsearch :443
        │
        ▼
Kibana Fleet

Applications instrumentées
        │ traces, métriques et erreurs
        ▼
APM Server :443 ─────────────────► Elasticsearch :443

Façade Spring Boot
        │ cron (toutes les minutes par défaut)
        ▼
Kafka KRaft (3 nœuds) ─────────────► Worker Spring Boot ───► MongoDB replica set
```

Fleet Server distribue les politiques et reçoit les check-ins. Les événements
ne transitent pas par Fleet Server : chaque agent les envoie directement à
Elasticsearch.

| Composant | Adresse externe |
| --- | --- |
| Elasticsearch | `https://elasticsearch.poc.test` |
| Kibana | `https://kibana.poc.test` |
| Fleet Server | `https://fleet.poc.test` |
| APM Server | `https://apm.poc.test` |
| MongoDB replica set | `192.168.33.10:27017`, `.11:27017`, `.12:27017` |
| Kafka KRaft | `192.168.33.10:9092`, `.11:9092`, `.12:9092` |

Les quatre endpoints Elastic passent par le port `443`. Les VMs les resolvent
vers l'interface host-only stable `192.168.33.1` via `/etc/hosts`.

## Prérequis et périmètre

Le dépôt contient les manifestes et la configuration d'observabilité ; il ne
crée pas le cluster Kubernetes. Avant de
suivre le guide, disposer de :

- `kubectl`, Docker et k3d, avec Traefik et l'opérateur ECK déjà installés ;
- un namespace `elastic-stack` contenant Elasticsearch `elasticsearch` et
  Kibana `es-kb-quickstart-eck-kibana` ;
- Vagrant et VirtualBox pour trois VMs Rocky Linux 10 aux adresses
  `192.168.33.10` à `192.168.33.12` ;
- l'archive Linux ARM64 d'Elastic Agent 9.5.1, extraite dans la VM si l'agent
  n'est pas déjà installé.

La [`Vagrantfile`](Vagrantfile) crée les trois VMs et provisionne sur chacune
un membre MongoDB et un broker/controller Kafka dans Podman. Le replica set
MongoDB est `poc-rs` et Kafka utilise un quorum KRaft de trois contrôleurs.

## Guides associés

| Sujet | Document |
| --- | --- |
| Ressources ECK, ingress et contrôles Kubernetes | [`kubernetes/README.md`](kubernetes/README.md) |
| Façade et worker Spring Boot instrumentés | [`apm-demo/README.md`](apm-demo/README.md) |
| Lecture des dashboards MongoDB | [`docs/mongodb-dashboards.md`](docs/mongodb-dashboards.md) |
| Configuration standalone historique | [`elastic-agent/elastic-agent.yml`](elastic-agent/elastic-agent.yml) |

## 1. Déployer Fleet Server et APM Server

Les manifestes supposent les ressources suivantes dans `elastic-stack` :

- Elasticsearch : `elasticsearch` ;
- Kibana : `es-kb-quickstart-eck-kibana`.

Les vérifier avant application :

```sh
kubectl -n elastic-stack get elasticsearch,kibana
```

Adapter les références si les noms diffèrent, puis appliquer dans cet ordre :

```sh
kubectl apply --server-side -f kubernetes/kibana-fleet-patch.yaml
kubectl apply -f kubernetes/fleet-server.yaml
kubectl apply -f kubernetes/apm-server.yaml
kubectl apply -f kubernetes/elastic-ingress.yaml

kubectl wait -n elastic-stack --for=condition=Ready pod \
  -l agent.k8s.elastic.co/name=fleet-server --timeout=5m
kubectl wait -n elastic-stack --for=condition=Ready apmserver/apm-server \
  --timeout=5m
```

Vérifier ECK et l'endpoint public :

```sh
kubectl -n elastic-stack get agent fleet-server
kubectl -n elastic-stack get apmserver apm-server
curl -k https://fleet.poc.test/api/status
curl -k https://apm.poc.test/
```

Résultat attendu :

```json
{"name":"fleet-server","status":"HEALTHY"}
```

APM Server doit répondre `200` (ou `401` sans jeton), ce qui confirme que sa
route publique est joignable.

### Connecter une application instrumentée

APM Server est déclaré dans
[`kubernetes/apm-server.yaml`](kubernetes/apm-server.yaml). ECK gère ses
références vers Elasticsearch et Kibana ; le jeton d'authentification est créé
à l'exécution et n'est pas versionné :

```sh
kubectl -n elastic-stack get secret apm-server-apm-token \
  -o go-template='{{index .data "secret-token" | base64decode}}'
```

Configurer l'agent APM de l'application avec les variables adaptées à son
langage, par exemple :

```sh
ELASTIC_APM_SERVER_URL=https://apm.poc.test
ELASTIC_APM_SECRET_TOKEN='<jeton récupéré ci-dessus>'
# POC uniquement : Traefik présente un certificat auto-signé.
ELASTIC_APM_VERIFY_SERVER_CERT=false
```

En production, utiliser un certificat de confiance et supprimer la dernière
variable. Les traces, erreurs et métriques applicatives seront visibles dans
**Observability → APM** dans Kibana.

Une démonstration Spring Boot instrumentée est fournie dans
[`apm-demo/`](apm-demo/). Elle déploie une façade et un worker ; `/api/work`
produit une trace distribuée entre les deux services et `/api/error` une erreur
APM. La façade publie aussi périodiquement un message Kafka que le worker
traite et persiste dans MongoDB. Voir son [guide d'exécution](apm-demo/README.md)
pour un lancement local ou Kubernetes.

Le manifeste Kibana crée uniquement la politique ECK gérée de Fleet Server.
La politique applicative MongoDB n'y est volontairement pas déclarée : une
politique vide préconfigurée par Kibana écraserait ses intégrations lors d'un
redémarrage.

## 2. Configurer la politique Fleet des services de donnees

La politique d'agent attendue est :

```text
MongoDB hosts (ID : mongodb-hosts)
```

Sa package policy reproductible est décrite dans
[`elastic-agent/mongodb-package-policy.json`](elastic-agent/mongodb-package-policy.json).
Elle configure :

- les logs `/var/log/mongodb/mongod.log` ;
- les metriques MongoDB locales de chaque VM ;
- une période de `60s` ;
- `collstats`, `dbstats`, `metrics` et `status` ;
- `replstatus` activé pour suivre l'état du replica set.

La package policy Kafka complementaire est
[`elastic-agent/kafka-package-policy.json`](elastic-agent/kafka-package-policy.json).
Elle collecte les logs de `/var/log/kafka` ainsi que les metriques broker et
KRaft via Jolokia sur `127.0.0.1:8778`. Ce port est publie uniquement sur la
boucle locale de chaque VM ; il n'est pas expose sur le reseau prive.

### Création dans Kibana

Dans **Management → Fleet → Agent policies**, créer `MongoDB hosts`, puis
ajouter l'intégration **MongoDB** avec les valeurs ci-dessus.

### Synchronisation reproductible par API

Le script idempotent crée la politique `mongodb-hosts` si nécessaire, puis crée
ou remplace les deux package policies. Il est donc la seule commande à
rejouer après un redéploiement :

```sh
KIBANA_PASSWORD="$(kubectl -n elastic-stack get secret \
  elasticsearch-es-elastic-user \
  -o go-template='{{.data.elastic | base64decode}}')"

KIBANA_PASSWORD="$KIBANA_PASSWORD" ./scripts/sync-fleet-policies.sh
unset KIBANA_PASSWORD
```

La policy Kafka active les streams `broker`, `partition`, `consumergroup` et
`topic`. Les trois premiers alimentent **[Metrics Kafka] Overview** ; le stream
`topic` est indispensable au dashboard **[Metrics Kafka] Topic**.
Le pipeline Elasticsearch versionné `metrics-kafka.topic@custom` normalise le
champ `kafka.topic.name`, attendu par le dashboard du package Kafka 1.27.2.

Les dashboards **Consumer** et **Producer** ne sont pas des métriques de
broker : ils exigent un endpoint Jolokia dans chaque application cliente. Ils
restent donc volontairement vides tant qu'un agent Fleet n'est pas déployé à
côté des clients Kafka. Le stream Raft du package 1.27.2 est incompatible avec
Kafka 3.9.2 (attribut JMX `number-of-voters` absent) ; l'état KRaft reste
vérifiable par `scripts/cluster-status.sh` en attendant une correction du
package Elastic.

### Enrôlement Fleet via Vagrant

L'enrôlement fait partie du provisionnement. Injecter un enrollment token de la
policy `mongodb-hosts` au lancement, sans l'écrire dans un fichier :

```sh
export FLEET_ENROLLMENT_TOKEN='…token Fleet mongodb-hosts…'
vagrant provision data-01 data-02 data-03
unset FLEET_ENROLLMENT_TOKEN
```

Le script `scripts/install-elastic-agent.sh` est idempotent : sur une VM déjà
enrôlée il redémarre le service seulement s'il était arrêté. Les policies sont
ensuite synchronisées par `scripts/sync-fleet-policies.sh`.

## 3. Préparer et enrôler la VM

Le nom affiché dans Fleet vient du hostname de l'OS. Les VMs créées par
Vagrant sont déjà nommées `data-01`, `data-02` et `data-03`. Enrôler un agent
Fleet sur chaque VM, en remplaçant le nom de VM dans les commandes suivantes :

```sh
hostnamectl
```

Arrêter tout agent standalone. Une seule instance Elastic Agent peut être
installée sur un hôte :

```sh
sudo systemctl stop elastic-agent 2>/dev/null || true
sudo pkill -f '/home/vagrant/elastic-agent-9.5.1-linux-arm64/elastic-agent' || true
```

Si le répertoire extrait a déjà servi au mode standalone, déplacer son état
local. Les sockets présents dans `data/tmp` ne peuvent pas être copiés par la
commande `install` :

```sh
cd /home/vagrant/elastic-agent-9.5.1-linux-arm64
sudo mv data data.standalone-backup
```

Dans **Fleet → Agents → Add agent**, sélectionner `MongoDB hosts` et copier le
jeton d'enrôlement, puis exécuter dans la VM :

```sh
sudo ./elastic-agent install \
  --url=https://fleet.poc.test:443 \
  --enrollment-token='<enrollment-token>' \
  --insecure \
  --tag mongodb,poc
```

`--insecure` est requis uniquement parce que Traefik présente un certificat
auto-signé dans ce laboratoire. Le trafic reste chiffré, mais la chaîne du
certificat n'est pas vérifiée. En production, distribuer la CA et supprimer
`--insecure` ainsi que `ssl.verification_mode: none`.

## 4. Vérifier l'agent

```sh
sudo /opt/Elastic/Agent/elastic-agent status
sudo /opt/Elastic/Agent/elastic-agent status --output yaml
sudo journalctl -u elastic-agent -n 100 --no-pager
```

Les composants attendus sont :

```text
fleet                     Connected
log-default               Healthy
mongodb/metrics-default   Healthy
```

Dans Kibana, ouvrir **Management → Fleet → Agents**. L'hôte doit apparaître
sous les noms `data-01`, `data-02` et `data-03`, avec la politique `MongoDB hosts`.

Deux champs ont des rôles différents :

```text
host.name: data-01
service.address: mongodb://192.168.33.10:27017,192.168.33.11:27017,192.168.33.12:27017
```

`host.name` identifie une VM ; `service.address` indique les membres utilisés
par l'intégration pour joindre MongoDB.

## 5. Générer du trafic MongoDB

Le script [`scripts/mongodb-elk-workload.js`](scripts/mongodb-elk-workload.js)
effectue des insertions, mises à jour, lectures, agrégations et suppressions
dans `observability_test.elk_validation`. Il active temporairement le profilage
MongoDB pour rendre ces opérations visibles dans `mongod.log`.

```sh
vagrant upload \
  scripts/mongodb-elk-workload.js \
  /tmp/mongodb-elk-workload.js \
  data-01

vagrant ssh data-01 -c \
  'sudo podman cp /tmp/mongodb-elk-workload.js poc-mongodb:/tmp/mongodb-elk-workload.js && \
   sudo podman exec poc-mongodb mongosh --quiet mongodb://127.0.0.1:27017 \
   /tmp/mongodb-elk-workload.js'
```

Chaque exécution affiche un `run_id`, insère 200 documents, en supprime 10 et
en conserve 190.

## 6. Vérifier les données dans Kibana

Dans **Discover**, utiliser une période récente et filtrer sur l'hôte Fleet :

```text
host.name: data-* and data_stream.dataset: mongodb.*
```

Logs MongoDB :

```text
host.name: data-* and data_stream.dataset: "mongodb.log"
```

Commandes du workload :

```text
host.name: data-* and mongodb.log.attr.ns: observability_test*
```

Data streams attendus :

```text
logs-mongodb.log-default
metrics-mongodb.collstats-default
metrics-mongodb.dbstats-default
metrics-mongodb.metrics-default
metrics-mongodb.status-default
```

`metrics-mongodb.replstatus-default` n'est attendu qu'après activation d'un
replica set MongoDB et du stream `replstatus` dans la package policy.

Les dashboards MongoDB sont décrits dans
[`docs/mongodb-dashboards.md`](docs/mongodb-dashboards.md).

## Diagnostic

### Fleet Server répond `404`

La route Traefik n'est probablement pas appliquée :

```sh
kubectl apply -f kubernetes/elastic-ingress.yaml
kubectl -n elastic-stack get ingressroute fleet-server
```

### Fleet Server répond `502`

Vérifier le service et ses endpoints :

```sh
kubectl -n elastic-stack get service fleet-server-agent-http
kubectl -n elastic-stack get endpoints fleet-server-agent-http
```

### Certificat « not yet valid »

L'horloge de la VM est décalée :

```sh
sudo timedatectl set-ntp true
sudo systemctl enable --now chronyd
sudo chronyc makestep
```

### Certificat signé par une autorité inconnue

Pour ce POC uniquement, ajouter `--insecure` à `elastic-agent install` ou
`elastic-agent enroll`.

### Agent sain mais aucune donnée MongoDB

Vérifier que la politique possède bien la package policy `mongodb-fleet` :

```sh
sudo /opt/Elastic/Agent/elastic-agent status --output yaml
sudo test -r /var/log/mongodb/mongod.log
sudo ss -lntp | grep 27017
```

Si seuls `filestream-monitoring` et `http/metrics-monitoring` apparaissent,
l'intégration MongoDB n'est pas attachée à la politique de l'agent.

## Mode standalone historique

Le fichier [`elastic-agent/elastic-agent.yml`](elastic-agent/elastic-agent.yml)
reste disponible à des fins de comparaison. Il utilise une clé API fournie par
`ELASTICSEARCH_API_KEY` et configure directement les inputs locaux. Ne jamais
lancer ce mode en même temps que le service Fleet installé dans
`/opt/Elastic/Agent`.
