# Intégration MongoDB vers Elastic Fleet

Ce POC collecte les logs et métriques d'un MongoDB exécuté dans une VM Rocky
Linux avec Elastic Agent 9.5.1 géré par Fleet. Elasticsearch, Kibana et Fleet
Server sont déployés par ECK dans k3d et exposés par Traefik.

Le mode standalone historique reste disponible dans
[`elastic-agent/elastic-agent.yml`](elastic-agent/elastic-agent.yml), mais le
parcours principal du projet utilise désormais Fleet.

## Architecture

```text
MongoDB 192.168.33.10:27017
        │ logs + métriques
        ▼
Elastic Agent 9.5.1 (VM mongodb-01)
        │                               │
        │ check-in et politique         │ événements
        ▼                               ▼
Fleet Server :443                 Elasticsearch :443
        │
        ▼
Kibana Fleet
```

Fleet Server distribue les politiques et reçoit les check-ins. Les événements
ne transitent pas par Fleet Server : chaque agent les envoie directement à
Elasticsearch.

| Composant | Adresse externe |
| --- | --- |
| Elasticsearch | `https://elasticsearch.192-168-1-158.sslip.io` |
| Kibana | `https://kibana.192-168-1-158.sslip.io` |
| Fleet Server | `https://fleet.192-168-1-158.sslip.io` |
| MongoDB dans la VM | `192.168.33.10:27017` |

Les trois endpoints Elastic passent par le port `443`. `sslip.io` résout les
noms vers `192.168.1.158` sans modification de `/etc/hosts`.

## 1. Déployer Fleet Server

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
kubectl apply -f kubernetes/elastic-ingress.yaml

kubectl wait -n elastic-stack --for=condition=Ready pod \
  -l agent.k8s.elastic.co/name=fleet-server --timeout=5m
```

Vérifier ECK et l'endpoint public :

```sh
kubectl -n elastic-stack get agent fleet-server
curl -k https://fleet.192-168-1-158.sslip.io/api/status
```

Résultat attendu :

```json
{"name":"fleet-server","status":"HEALTHY"}
```

Le manifeste Kibana crée uniquement la politique ECK gérée de Fleet Server.
La politique applicative MongoDB n'y est volontairement pas déclarée : une
politique vide préconfigurée par Kibana écraserait ses intégrations lors d'un
redémarrage.

## 2. Configurer la politique MongoDB

La politique d'agent attendue est :

```text
MongoDB hosts (ID : mongodb-hosts)
```

Sa package policy reproductible est décrite dans
[`elastic-agent/mongodb-package-policy.json`](elastic-agent/mongodb-package-policy.json).
Elle configure :

- les logs `/var/log/mongodb/mongod.log` ;
- la cible métrique `192.168.33.10:27017` ;
- une période de `60s` ;
- `collstats`, `dbstats`, `metrics` et `status` ;
- `replstatus` désactivé, car le POC MongoDB n'est pas un replica set.

### Création dans Kibana

Dans **Management → Fleet → Agent policies**, créer `MongoDB hosts`, puis
ajouter l'intégration **MongoDB** avec les valeurs ci-dessus.

### Création reproductible par API

Si la politique `mongodb-hosts` existe déjà, créer la package policy avec :

```sh
ELASTIC_PASSWORD="$(kubectl -n elastic-stack get secret \
  elasticsearch-es-elastic-user \
  -o go-template='{{.data.elastic | base64decode}}')"

curl -k -u "elastic:${ELASTIC_PASSWORD}" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -X POST \
  https://kibana.192-168-1-158.sslip.io/api/fleet/package_policies \
  --data-binary @elastic-agent/mongodb-package-policy.json

unset ELASTIC_PASSWORD
```

Ne pas rejouer le `POST` si `mongodb-fleet` existe déjà. Pour une modification,
utiliser l'interface Fleet ou un `PUT` sur l'identifiant de la package policy.

## 3. Préparer et enrôler la VM

Le nom affiché dans Fleet vient du hostname de l'OS. Le définir avant
l'enrôlement :

```sh
sudo hostnamectl set-hostname mongodb-01
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
  --url=https://fleet.192-168-1-158.sslip.io:443 \
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
sous le nom `mongodb-01`, avec la politique `MongoDB hosts`.

Deux champs ont des rôles différents :

```text
host.name: mongodb-01
service.address: mongodb://192.168.33.10:27017
```

`host.name` identifie la VM ; `service.address` indique l'adresse utilisée par
l'intégration pour joindre MongoDB.

## 5. Générer du trafic MongoDB

Le script [`scripts/mongodb-elk-workload.js`](scripts/mongodb-elk-workload.js)
effectue des insertions, mises à jour, lectures, agrégations et suppressions
dans `observability_test.elk_validation`. Il active temporairement le profilage
MongoDB pour rendre ces opérations visibles dans `mongod.log`.

```sh
vagrant upload \
  scripts/mongodb-elk-workload.js \
  /tmp/mongodb-elk-workload.js

vagrant ssh -c \
  'mongosh --quiet mongodb://127.0.0.1:27017 /tmp/mongodb-elk-workload.js'
```

Chaque exécution affiche un `run_id`, insère 200 documents, en supprime 10 et
en conserve 190.

## 6. Vérifier les données dans Kibana

Dans **Discover**, utiliser une période récente et filtrer sur l'hôte Fleet :

```text
host.name: "mongodb-01" and data_stream.dataset: mongodb.*
```

Logs MongoDB :

```text
host.name: "mongodb-01" and data_stream.dataset: "mongodb.log"
```

Commandes du workload :

```text
host.name: "mongodb-01" and mongodb.log.attr.ns: observability_test*
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
