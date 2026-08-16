# Application de démonstration APM

Cette démonstration contient deux services Express : `apm-demo`, la façade,
et `apm-demo-worker`, le service aval. Chaque requête vers `/work` traverse
les deux services. L'agent Node.js injecte et lit automatiquement le contexte
W3C `traceparent` sur l'appel HTTP : APM affiche donc une seule trace
distribuée. L'endpoint `/error` de la façade remonte une erreur contrôlée.

## Prérequis

APM Server doit être déployé et accessible. Suivre d'abord le
[guide principal](../README.md#1-déployer-fleet-server-et-apm-server), puis
vérifier que son endpoint répond :

```sh
curl -k https://apm.192-168-1-158.sslip.io/
```

Pour l'exécution locale, utiliser une version de Node.js compatible avec
l'image de démonstration (Node 22). Pour Kubernetes, Docker, k3d et `kubectl`
sont nécessaires.

## Exécution locale

Récupérer le jeton APM, puis lancer l'application :

```sh
export ELASTIC_APM_SERVER_URL=https://apm.192-168-1-158.sslip.io
export ELASTIC_APM_SECRET_TOKEN="$(kubectl -n elastic-stack get secret \
  apm-server-apm-token -o go-template='{{index .data "secret-token" | base64decode}}')"
# Certificat auto-signé de Traefik, uniquement pour ce POC.
export ELASTIC_APM_VERIFY_SERVER_CERT=false
export ELASTIC_APM_SERVICE_NAME=apm-demo
export ELASTIC_APM_ENVIRONMENT=local

npm install
npm start
```

Dans un second terminal, lancer le service aval avec son identité APM propre :

```sh
export ELASTIC_APM_SERVER_URL=https://apm.192-168-1-158.sslip.io
export ELASTIC_APM_SECRET_TOKEN="$(kubectl -n elastic-stack get secret \
  apm-server-apm-token -o go-template='{{index .data "secret-token" | base64decode}}')"
export ELASTIC_APM_VERIFY_SERVER_CERT=false
export ELASTIC_APM_SERVICE_NAME=apm-demo-worker
export ELASTIC_APM_ENVIRONMENT=local
PORT=3001 npm run start:worker
```

Dans un autre terminal :

```sh
curl http://localhost:3000/work # Trace apm-demo -> apm-demo-worker
curl http://localhost:3000/error
```

`/work` répond avec le résultat calculé par le worker ; `/error` répond `500`
et crée une erreur APM volontaire. Si le worker n'est pas encore démarré,
`/work` répond `502` après deux secondes.

Les transactions apparaissent dans **Observability → APM → Services**. Ouvrir
une transaction `/work` de `apm-demo` : son appel HTTP pointe vers
`apm-demo-worker` et la transaction aval partage le même trace ID.

## Déploiement Kubernetes

Construire l'image et la rendre disponible à k3d :

```sh
docker build -t apm-demo:1.0.0 apm-demo
k3d image import apm-demo:1.0.0 -c elastic
kubectl apply -f kubernetes/apm-demo.yaml
kubectl -n elastic-stack rollout status deployment/apm-demo --timeout=2m
kubectl -n elastic-stack rollout status deployment/apm-demo-worker --timeout=2m
kubectl -n elastic-stack port-forward service/apm-demo 3000:3000
```

Puis appeler les mêmes endpoints sur `http://localhost:3000`. Le manifeste
récupère le jeton directement depuis le Secret ECK ; il ne doit jamais être
copié dans le dépôt.

Pour retirer la démonstration après vérification :

```sh
kubectl delete -f kubernetes/apm-demo.yaml
```
