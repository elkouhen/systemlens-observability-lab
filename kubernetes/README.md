# Ingress Elastic Stack

Le manifeste `elastic-ingress.yaml` expose les services ECK via deux
`IngressRoute` Traefik :

- `https://elasticsearch.192-168-1-158.sslip.io`
- `https://kibana.192-168-1-158.sslip.io`

Le certificat HTTPS présenté côté client est le certificat par défaut de
Traefik. Il est auto-signé dans cette installation locale ; le navigateur ou
`curl` doit donc explicitement l'accepter.

## Déploiement

```sh
kubectl apply -f kubernetes/elastic-ingress.yaml
```

## Accès depuis l'hôte

Le load balancer k3d publie les ports 80 et 443 sur l'hôte. Les routes sont
donc accessibles directement, sans port-forward et sans modification de
`/etc/hosts`. Le service DNS dynamique `sslip.io` extrait automatiquement
l'adresse `192.168.1.158` des noms :

```sh
curl -k https://elasticsearch.192-168-1-158.sslip.io/
curl -k https://kibana.192-168-1-158.sslip.io/
```

Elasticsearch répondra `401 Unauthorized` sans identifiants, ce qui confirme
que la route atteint bien le service protégé. Kibana doit répondre par une
redirection ou une page HTML.
