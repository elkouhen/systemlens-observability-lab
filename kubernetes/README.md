# Composants Kubernetes Elastic Fleet

Ce répertoire contient :

| Fichier | Rôle |
| --- | --- |
| `kibana-fleet-patch.yaml` | Configure la sortie Fleet, les packages requis et la politique Fleet Server dans Kibana |
| `fleet-server.yaml` | Déploie Fleet Server 9.5.1 avec l'Agent CRD d'ECK |
| `elastic-ingress.yaml` | Expose Elasticsearch, Kibana et Fleet Server avec Traefik |

La politique applicative `mongodb-hosts` n'est pas préconfigurée dans la
ressource Kibana. Elle est administrée dans Fleet et sa package policy est
décrite par `../elastic-agent/mongodb-package-policy.json`. Cette séparation
évite qu'un redémarrage de Kibana réinitialise les intégrations ajoutées à la
politique.

## Ingress Elastic Stack

Le manifeste `elastic-ingress.yaml` expose les services ECK via trois
`IngressRoute` Traefik :

- `https://elasticsearch.192-168-1-158.sslip.io`
- `https://kibana.192-168-1-158.sslip.io`
- `https://fleet.192-168-1-158.sslip.io`

Le certificat HTTPS présenté côté client est le certificat par défaut de
Traefik. Il est auto-signé dans cette installation locale ; le navigateur ou
`curl` doit donc explicitement l'accepter.

## Déploiement complet

```sh
kubectl apply --server-side -f kubernetes/kibana-fleet-patch.yaml
kubectl apply -f kubernetes/fleet-server.yaml
kubectl apply -f kubernetes/elastic-ingress.yaml

kubectl wait -n elastic-stack --for=condition=Ready pod \
  -l agent.k8s.elastic.co/name=fleet-server --timeout=5m
```

Les manifestes supposent qu'Elasticsearch s'appelle `elasticsearch` et Kibana
`es-kb-quickstart-eck-kibana`, dans le namespace `elastic-stack`. Adapter
`metadata.name`, `kibanaRef` et `elasticsearchRefs` si nécessaire.

## Accès depuis l'hôte

Le load balancer k3d publie les ports 80 et 443 sur l'hôte. Les routes sont
donc accessibles directement, sans port-forward et sans modification de
`/etc/hosts`. Le service DNS dynamique `sslip.io` extrait automatiquement
l'adresse `192.168.1.158` des noms :

```sh
curl -k https://elasticsearch.192-168-1-158.sslip.io/
curl -k https://kibana.192-168-1-158.sslip.io/
curl -k https://fleet.192-168-1-158.sslip.io/api/status
```

Elasticsearch répondra `401 Unauthorized` sans identifiants, ce qui confirme
que la route atteint bien le service protégé. Kibana doit répondre par une
redirection ou une page HTML. Fleet Server doit répondre :

```json
{"name":"fleet-server","status":"HEALTHY"}
```

## Contrôles Kubernetes

```sh
kubectl -n elastic-stack get agent fleet-server
kubectl -n elastic-stack get pods \
  -l agent.k8s.elastic.co/name=fleet-server
kubectl -n elastic-stack get service fleet-server-agent-http
kubectl -n elastic-stack get endpoints fleet-server-agent-http
```

L'Agent ECK doit être `green`, avec une instance disponible sur une attendue.

## TLS du POC

ECK génère les certificats internes d'Elasticsearch et de Fleet Server.
`ServersTransport/eck-https` demande à Traefik de ne pas vérifier ces
certificats internes. Côté externe, Traefik présente son certificat par défaut
auto-signé : `curl` utilise donc `-k` et les agents externes sont enrôlés avec
`--insecure`.

En production, remplacer ces exceptions par une CA de confiance et des
certificats dont les SAN couvrent les noms DNS publiés.
