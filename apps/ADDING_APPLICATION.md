# Ajouter une application Java observée

Ce guide décrit l'ajout d'une application Java Spring Boot à la chaîne
d'observabilité du POC. Le chemin des signaux est le suivant :

```text
application Java → agent Java Elastic APM → APM Server → Logstash → Elasticsearch
logs stdout ECS → Elastic Agent Kubernetes → Logstash → Elasticsearch
```

L'agent Java Elastic APM produit les traces, erreurs et métriques applicatives.
L'Elastic Agent Kubernetes collecte exclusivement les logs stdout ECS. Logstash
centralise ensuite la normalisation de l'environnement et le routage des seules
métriques APM Java.

## Préparer l'application

L'image doit contenir l'agent Java Elastic APM et démarrer la JVM avec
`-javaagent`. Le `Dockerfile` de `supermarket-demo` est la référence du dépôt.
L'application doit écrire des logs JSON ECS sur stdout, avec Spring Boot :

```yaml
logging:
  structured:
    format:
      console: ecs
```

Ne pas expédier les logs directement depuis l'application : l'Elastic Agent
Kubernetes les collecte sur le nœud.

## Déclarer les variables Kubernetes

Dans le Deployment, définir les identifiants cohérents des logs et de l'APM :

```yaml
env:
  - name: LOGGING_STRUCTURED_FORMAT_CONSOLE
    value: ecs
  - name: LOGGING_STRUCTURED_ECS_SERVICE_NAME
    value: my-service
  - name: LOGGING_STRUCTURED_ECS_SERVICE_ENVIRONMENT
    value: h0p1-my-namespace
  - name: ELASTIC_APM_SERVICE_NAME
    value: my-service
  - name: ELASTIC_APM_SERVICE_VERSION
    value: "1.0.0"
  - name: ELASTIC_APM_ENVIRONMENT
    value: h0p1-my-namespace
  - name: ELASTIC_APM_APPLICATION_PACKAGES
    value: com.example.myservice
  - name: ELASTIC_APM_SERVER_URL
    value: https://apm-server-apm-http.elastic-stack.svc:8200
  - name: ELASTIC_APM_SECRET_TOKEN
    valueFrom:
      secretKeyRef:
        name: my-service-apm-token
        key: secret-token
  - name: ELASTIC_APM_ENABLE_LOG_CORRELATION
    value: "true"
```

Le token APM et le certificat de l'APM Server doivent être copiés dans le
namespace de l'application, sur le modèle de la cible `apm-token-sync`. Ne
jamais les inscrire dans un manifest ou dans Git.

## Convention d'environnement

La valeur source a le format :

```text
<type><ptf_sur_3_caracteres>-<namespace>
```

Exemple : `h0p1-supermarket` signifie :

| Partie | Valeur | Rôle |
| --- | --- | --- |
| Type | `h` | Environnement Elastic `homologation` |
| PTF | `0p1` | Ajouté dans `labels.ptf` |
| Namespace | `supermarket` | Ajouté dans `labels.namespace` |

Les types acceptés sont `r` (recette), `p` (production), `h` (homologation),
`i` (integration) et `d` (developpement). Logstash normalise ensuite
`service.environment` avec ce nom canonique.

Les métriques APM dont `agent.name` vaut `java` et qui portent un `container.id`
sont routées vers :

```text
metrics-apm.app.kubernetes-<environnement-elastic>
```

Les traces et erreurs conservent leur data stream d'origine, tout en portant le
`service.environment` normalisé et les labels d'enrichissement. Les logs
applicatifs Kubernetes dont la valeur source respecte la convention sont
regroupés dans le même namespace Elastic, par exemple :

```text
logs-kubernetes.container_logs-homologation
```

## Raccorder la collecte des logs

L'Agent Kubernetes actuel cible les fichiers des pods du namespace
`supermarket-demo`. Pour une application dans un autre namespace, élargir de
façon explicite le chemin `paths` dans
`platform/kubernetes/base/observability/kubernetes-logs-agent.yaml`, ou ajouter
un stream dédié. Appliquer ensuite `make kubernetes-validate`, puis
`make apm-logstash-deploy`.

## Vérifier le résultat

Après le déploiement de l'application, générer une requête métier puis utiliser
Discover avec les filtres suivants :

```kql
# Métriques Java en homologation
data_stream.dataset : "apm.app.kubernetes"
and data_stream.namespace : "homologation"
and agent.name : "java"
```

```kql
# Logs applicatifs normalisés
data_stream.dataset : "kubernetes.container_logs"
and service.environment : "homologation"
and labels.ptf : "0p1"
and labels.namespace : "supermarket"
```

Le contrôle attendu est la présence de la même identité de service dans les
logs, métriques et traces, avec un `trace.id` sur les logs émis dans une
transaction.
