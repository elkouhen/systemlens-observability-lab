# Intégration MongoDB vers Elastic

Ce projet collecte les logs et métriques d'un MongoDB exécuté dans une VM
Rocky Linux, au moyen d'Elastic Agent en mode autonome. Elasticsearch et
Kibana sont déployés dans k3d et exposés par Traefik.

## Architecture

```text
MongoDB :27017
   │ logs + métriques
   ▼
Elastic Agent 9.5.1 (VM Rocky)
   │ HTTPS :443
   ▼
elasticsearch.192-168-1-158.sslip.io
   │ Traefik IngressRoute
   ▼
Service ECK elasticsearch-es-http:9200
```

Les URL ne nécessitent ni modification de `/etc/hosts`, ni port-forward :

- Elasticsearch : `https://elasticsearch.192-168-1-158.sslip.io`
- Kibana : `https://kibana.192-168-1-158.sslip.io`

`sslip.io` résout les deux noms vers `192.168.1.158`.

## 1. Créer la clé API

Dans **Kibana → Management → Dev Tools**, exécuter :

```http
POST /_security/api_key
{
  "name": "rocky-mongodb-agent",
  "expiration": "90d",
  "role_descriptors": {
    "mongodb_agent_writer": {
      "cluster": [
        "monitor"
      ],
      "indices": [
        {
          "names": [
            "logs-mongodb.*-*",
            "metrics-mongodb.*-*",
            "logs-elastic_agent*",
            "metrics-elastic_agent*"
          ],
          "privileges": [
            "auto_configure",
            "create_doc"
          ]
        }
      ]
    }
  }
}
```

La réponse contient notamment `id`, `api_key` et `encoded`. Pour la sortie
Elasticsearch d'Elastic Agent, il faut utiliser la forme **non encodée** :

```text
<id>:<api_key>
```

Le champ `api_key` seul et le champ `encoded` provoquent un `401 Unauthorized`
dans cette configuration.

## 2. Configurer Elastic Agent

Le modèle autonome se trouve dans
[`elastic-agent/elastic-agent.yml`](elastic-agent/elastic-agent.yml). Il
collecte :

- `/var/log/mongodb/mongod.log` dans `logs-mongodb.log-default` ;
- `collstats`, `dbstats`, `metrics`, `replstatus` et `status` toutes les 60 s.

Points importants :

- le endpoint Elasticsearch passe par Traefik sur le port `443`, et non le
  port natif `9200` ;
- `ssl.verification_mode: none` accepte le certificat Traefik auto-signé du
  laboratoire. En production, installer une CA de confiance à la place ;
- le YAML ne doit contenir qu'une seule clé racine `inputs:`. Une seconde clé
  masque la première et empêche silencieusement le démarrage de MongoDB.

Transférer la configuration dans la VM :

```sh
vagrant upload \
  elastic-agent/elastic-agent.yml \
  /tmp/elastic-agent.yml

vagrant ssh -c \
  'sudo install -m 0600 /tmp/elastic-agent.yml /home/vagrant/elastic-agent-9.5.1-linux-arm64/elastic-agent.yml'
```

Définir la clé sans l'enregistrer dans Git, puis démarrer l'agent :

```sh
sudo -i
cd /home/vagrant/elastic-agent-9.5.1-linux-arm64
export ELASTICSEARCH_API_KEY='<id>:<api_key>'
./elastic-agent run -c elastic-agent.yml
```

Dans un autre terminal, contrôler son état :

```sh
sudo /home/vagrant/elastic-agent-9.5.1-linux-arm64/elastic-agent status
```

Les composants `log-default` et `mongodb/metrics-default` doivent être
présents et `HEALTHY`.

> Une variable exportée manuellement disparaît au redémarrage. Pour un agent
> permanent, stocker la clé dans un gestionnaire de secrets et installer
> Elastic Agent comme service systemd.

## 3. Générer une activité MongoDB de test

Le script [`scripts/mongodb-elk-workload.js`](scripts/mongodb-elk-workload.js)
effectue des insertions, mises à jour, lectures, agrégations et suppressions
dans `observability_test.elk_validation`. Il active temporairement le profilage
MongoDB afin que ces opérations apparaissent dans `mongod.log`.

```sh
vagrant upload \
  scripts/mongodb-elk-workload.js \
  /tmp/mongodb-elk-workload.js

vagrant ssh -c \
  'mongosh --quiet mongodb://127.0.0.1:27017 /tmp/mongodb-elk-workload.js'
```

Chaque exécution affiche un identifiant `run_id` et conserve 190 documents de
test.

## 4. Vérifier dans Kibana

Dans **Discover**, sélectionner une période récente, puis utiliser les filtres
KQL suivants.

Tous les logs MongoDB :

```text
data_stream.dataset: "mongodb.log"
```

Les commandes enregistrées par le profileur :

```text
data_stream.dataset: "mongodb.log" and message: "Slow query"
```

Les opérations sur la base de validation :

```text
mongodb.log.attr.ns: observability_test*
```

Tous les jeux de métriques MongoDB :

```text
data_stream.dataset: mongodb.*
```

Les data streams attendus sont :

```text
logs-mongodb.log-default
metrics-mongodb.collstats-default
metrics-mongodb.dbstats-default
metrics-mongodb.metrics-default
metrics-mongodb.replstatus-default
metrics-mongodb.status-default
```

## Diagnostic rapide

- `401 Unauthorized` : clé absente, invalide ou au mauvais format ; vérifier
  `<id>:<api_key>`.
- `403 Forbidden` : clé valide mais privilèges insuffisants.
- `dial tcp ...:9200` : ajouter explicitement `:443` au nom de l'Ingress.
- erreur `x509` : faire confiance à la CA ou, uniquement en laboratoire,
  utiliser `ssl.verification_mode: none`.
- aucun composant MongoDB dans `elastic-agent status` : rechercher plusieurs
  clés racines `inputs:` dans le YAML.
