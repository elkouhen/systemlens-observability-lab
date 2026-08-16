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

MongoDB doit être accessible sur `192.168.33.10:27017` ou via une URI fournie
dans `SPRING_DATA_MONGODB_URI`. Kafka doit être accessible via
`SPRING_KAFKA_BOOTSTRAP_SERVERS` (par défaut : `kafka:9092`).

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

Démarrer d'abord un broker Kafka KRaft mono-nœud dans un troisième terminal :

```sh
docker run --rm --name apm-demo-kafka -p 9092:9092 \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093 \
  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092 \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  -e KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0 \
  -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=true \
  apache/kafka:3.9.2
```

Définir la configuration APM dans les deux terminaux :

```sh
export ELASTIC_APM_SERVER_URL=https://apm.192-168-1-158.sslip.io
export ELASTIC_APM_SECRET_TOKEN="$(kubectl -n elastic-stack get secret \
  apm-server-apm-token -o go-template='{{index .data "secret-token" | base64decode}}')"
export ELASTIC_APM_VERIFY_SERVER_CERT=false
export ELASTIC_APM_ENVIRONMENT=local
export SPRING_KAFKA_BOOTSTRAP_SERVERS=localhost:9092
```

Dans le premier terminal, démarrer le worker :

```sh
cd apm-demo
export ELASTIC_APM_SERVICE_NAME=apm-demo-worker
export SPRING_DATA_MONGODB_URI=mongodb://192.168.33.10:27017/observability_test
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
vagrant ssh -c 'mongosh --quiet mongodb://127.0.0.1:27017/observability_test \
  --eval "db.apm_demo_work.find({trigger: \"kafka\"}).sort({createdAt: -1}).limit(5)"'
```

## Déploiement Kubernetes

Construire les deux images depuis le Dockerfile multi-stage, les importer dans
k3d, créer le namespace isolé et y synchroniser le Secret APM, démarrer Kafka,
puis déployer les manifestes. Le Secret est recopié, jamais versionné :

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

kubectl apply -f kubernetes/kafka.yaml
kubectl -n apm-demo rollout status deployment/kafka --timeout=3m
kubectl apply -f kubernetes/apm-demo.yaml
kubectl -n apm-demo rollout status deployment/apm-demo --timeout=2m
kubectl -n apm-demo rollout status deployment/apm-demo-worker --timeout=2m
kubectl -n apm-demo port-forward service/apm-demo 3000:3000
```

Dans un autre terminal, appeler `http://localhost:3000/api/work` et
`http://localhost:3000/api/error`. Le manifeste transmet les paramètres APM
et lit le jeton depuis le Secret ECK, sans le copier dans le dépôt. Le broker
Kafka est un mono-nœud KRaft sans stockage persistant, adapté uniquement au
laboratoire.

Pour retirer la démonstration :

```sh
kubectl delete -f kubernetes/apm-demo.yaml
kubectl delete -f kubernetes/kafka.yaml
kubectl delete -f kubernetes/apm-demo-namespace.yaml
```
