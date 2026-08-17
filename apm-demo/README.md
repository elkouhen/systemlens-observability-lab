# Application de démonstration APM Spring Boot

Cette démo remplace l'ancienne implémentation Node.js par deux services Java
21/Spring Boot, organisés dans un projet Maven multi-modules :

- `apm-demo` est la façade exposée sur le port `3000` ;
- `apm-demo-worker` est le service aval, exposé sur le port `3001`.

`GET /api/work` sur la façade appelle le worker en `RestTemplate`. Le worker
simule 150 ms de calcul, puis enregistre le résultat dans la collection MongoDB
`apm_demo_work`. L'agent Elastic APM est attaché au démarrage de chaque JVM ;
la propagation W3C `traceparent` produit donc une trace distribuée. La route
`GET /api/error` produit une erreur APM contrôlée.

La façade planifie également `publishScheduledWork` toutes les minutes par
défaut. Cette tâche publie un `WorkRequested` sur le topic Kafka
`apm-demo.work.requested`; le worker le consomme et persiste un document avec
`trigger: "kafka"`. Définir `APM_DEMO_CRON` pour modifier l'expression cron
Spring à six champs (secondes incluses).

## Prérequis

Déployer d'abord APM Server en suivant le
[guide principal](../README.md#1-déployer-fleet-server-et-apm-server). Pour un
lancement local, installer un JDK 21 et Maven 3.9+. Docker, k3d et `kubectl`
sont requis pour le déploiement Kubernetes.

MongoDB est un replica set `poc-rs` réparti entre `192.168.33.10` à `.12`.
Kafka KRaft est réparti sur les mêmes trois VMs. Les valeurs par défaut de
`SPRING_DATA_MONGODB_URI` et `SPRING_KAFKA_BOOTSTRAP_SERVERS` ciblent les trois
nœuds ; elles peuvent être remplacées par l'environnement.

## Indexation avec SystemLens

Le projet utilise les conventions reconnues par SystemLens : modules Maven,
classes `@SpringBootApplication`, contrôleurs Spring MVC, appel `RestTemplate`,
entité `@Document`, dépôt `MongoRepository`, `KafkaTemplate` et
`@KafkaListener`.

Depuis ce répertoire :

```sh
systemlens init
systemlens doctor
systemlens index --full
systemlens microservices
systemlens apis
systemlens mongodb
systemlens topics
```

L'index doit identifier les deux microservices, la relation REST
`apm-demo` → `apm-demo-worker` sur `GET /api/work`, et la collection
`apm_demo_work` utilisée par le worker. `systemlens topics` doit afficher
`apm-demo.work.requested`, produit par la façade et consommé par le worker.

## Exécution locale

Démarrer les trois VMs afin d'installer et de démarrer les clusters MongoDB et
Kafka :

```sh
vagrant up data-01 data-02 data-03
vagrant ssh data-01 -c 'sudo podman ps'
```

Définir la configuration APM dans les deux terminaux :

```sh
export ELASTIC_APM_SERVER_URL=https://apm.poc.test
export ELASTIC_APM_SECRET_TOKEN="$(kubectl -n elastic-stack get secret \
  apm-server-apm-token -o go-template='{{index .data "secret-token" | base64decode}}')"
export ELASTIC_APM_VERIFY_SERVER_CERT=false
export ELASTIC_APM_ENVIRONMENT=local
export SPRING_KAFKA_BOOTSTRAP_SERVERS=192.168.33.10:9092,192.168.33.11:9092,192.168.33.12:9092
```

Dans le premier terminal, démarrer le worker :

```sh
cd apm-demo
export ELASTIC_APM_SERVICE_NAME=apm-demo-worker
export SPRING_DATA_MONGODB_URI='mongodb://192.168.33.10:27017,192.168.33.11:27017,192.168.33.12:27017/observability_test?replicaSet=poc-rs'
mvn --projects apm-demo-worker spring-boot:run
```

Dans le second terminal, démarrer la façade :

```sh
cd apm-demo
export ELASTIC_APM_SERVICE_NAME=apm-demo
export APM_DEMO_WORKER_URL=http://localhost:3001
mvn --projects apm-demo spring-boot:run
```

Puis appeler la façade :

```sh
curl http://localhost:3000/api/work
curl -i http://localhost:3000/api/error
```

La première commande répond avec l'identifiant MongoDB, le résultat `499500`
et `durationMs: 150`. La seconde répond `500`. Les transactions sont visibles
dans **Observability → APM → Services**. Après le prochain cron, vérifier
l'arrivée d'un traitement Kafka :

```sh
vagrant ssh data-01 -c 'sudo podman exec poc-mongodb mongosh --quiet \
  mongodb://127.0.0.1:27017/observability_test \
  --eval "db.apm_demo_work.find({trigger: \"kafka\"}).sort({createdAt: -1}).limit(5)"'
```

## Déploiement Kubernetes

Construire les deux images depuis le Dockerfile multi-stage, les importer dans
k3d, créer le namespace isolé et y synchroniser le Secret APM, puis déployer
les manifestes. Les trois VMs doivent déjà être démarrées avec
`vagrant up data-01 data-02 data-03`. Le Secret est recopié, jamais versionné :

```sh
docker build --target frontend -t apm-demo:1.0.0 apm-demo
docker build --target worker -t apm-demo-worker:1.0.0 apm-demo
k3d image import apm-demo:1.0.0 apm-demo-worker:1.0.0 -c elastic
kubectl apply -f kubernetes/apm-demo-namespace.yaml

APM_TOKEN="$(kubectl -n elastic-stack get secret apm-server-apm-token \
  -o go-template='{{index .data "secret-token" | base64decode}}')"
kubectl -n apm-demo create secret generic apm-server-apm-token \
  --from-literal=secret-token="$APM_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
unset APM_TOKEN

kubectl apply -f kubernetes/apm-demo.yaml
kubectl -n apm-demo rollout status deployment/apm-demo --timeout=2m
kubectl -n apm-demo rollout status deployment/apm-demo-worker --timeout=2m
kubectl -n apm-demo port-forward service/apm-demo 3000:3000
```

Dans un autre terminal, appeler `http://localhost:3000/api/work` et
`http://localhost:3000/api/error`. Le manifeste transmet les paramètres APM
et lit le jeton depuis le Secret ECK, sans le copier dans le dépôt. Le broker
Kafka est un cluster KRaft de trois nœuds avec des volumes Podman persistants,
adapté uniquement au laboratoire.

### Métriques Kafka Producer et Consumer

Les deux images exposent Jolokia : port `8775` pour le producteur `apm-demo`
et port `8774` pour le consommateur `apm-demo-worker`. Les routes Traefik du
laboratoire les rendent joignables uniquement depuis le réseau host-only, sous
`kafka-producer-jolokia.poc.test` et `kafka-consumer-jolokia.poc.test`.
L'agent Fleet de `data-01` les collecte ; les agents des deux autres VMs sont
exclus par une condition de policy pour éviter les doublons.

Après un rollout des deux deployments, les dashboards **[Metrics Kafka]
Producer** et **Consumer** reçoivent respectivement les data streams
`kafka.producer` et `kafka.consumer`.

Pour retirer la démonstration :

```sh
kubectl delete -f kubernetes/apm-demo.yaml
kubectl delete -f kubernetes/apm-demo-namespace.yaml
```
