# Spécification technique v3

Cette spécification décrit l’implémentation de référence de la chaîne
d’observabilité v3. Elle précise les composants, les interfaces, les flux et
les contraintes qui réalisent les exigences de la
[spécification fonctionnelle](specification-fonctionnelle-v3.md).

| Élément | Définition |
| --- | --- |
| Nature | Spécification technique de référence |
| Périmètre | Kubernetes, EDOT, Kafka, Fleet et Elastic de la v3 |
| Public | Architectes, développeurs plateforme et opérateurs |
| Version Elastic | `9.4.3` |
| Architecture associée | [Architecture v3](architecture-v3.md) |

## 1. Découpage technique

La v3 sépare les chemins de collecte selon leur origine : les applications et
Kubernetes passent par OpenTelemetry, EDOT et Kafka ; les VM passent par
Elastic Agent Fleet et exportent directement vers Elasticsearch.

Cette séparation réduit le couplage entre la collecte Kubernetes et la
collecte des VM. Elle impose en contrepartie deux modes d’administration : les
collecteurs Kubernetes sont déclarés par Kustomize et Fleet via OpAMP, tandis
que les agents VM sont provisionnés par Ansible et enrôlés dans Fleet.

## 2. Topologie des composants

| Composant | Déploiement | Fonction technique |
| --- | --- | --- |
| `otel-gateway` | Kubernetes, namespace `elastic-stack` | Recevoir les signaux OTLP sur les ports `4317` et `4318` et les publier dans Kafka |
| EDOT DaemonSet | Kubernetes | Lire les logs stdout et les métriques Kubernetes prévues par la configuration |
| Kafka | `poc-01` | Tamponner les signaux applicatifs et Kubernetes dans trois topics dédiés |
| Collector backend EDOT | `otel-backend-01` | Consommer Kafka, traiter les signaux et les exporter vers Elastic |
| HAProxy et routage TLS | `otel-edge-01` | Exposer les points d’entrée OTLP, Elasticsearch, Kibana et Fleet |
| Elasticsearch | `elk-01` | Stocker les signaux et fournir les API d’ingestion et de recherche |
| Kibana | `elk-01` | Fournir Discover, APM, Fleet et les dashboards |
| Fleet Server | `elk-01` | Enrôler et administrer les Elastic Agents des VM |
| Elastic Agent | Chaque VM active | Collecter les logs et métriques des VM et des services intégrés |

Les workloads applicatifs utilisent le namespace `h0tl-supermarche-app`. Les
ressources de plateforme utilisent `elastic-stack`.

## 3. Interfaces et flux

### 3.1 Interfaces Kubernetes

Le Service `otel-gateway` expose les ports OTLP `4317` et `4318`. Les
applications et les collecteurs Kubernetes utilisent ce Service comme point
d’entrée OTLP.

Le routage externe s’appuie sur Traefik et les hôtes suivants :

- `elasticsearch.observability.test` ;
- `kibana.observability.test` ;
- `fleet.observability.test`.

Fleet Server se vérifie avec `/api/status`. Sa racine `/` n’est pas une
interface utilisateur.

### 3.2 Interfaces Kafka

Les topics OTLP sont séparés par type de signal :

| Topic | Producteurs principaux | Consommateur |
| --- | --- | --- |
| `otel-traces` | Gateway OTLP et collecte de traces | Collector backend |
| `otel-logs` | Gateway OTLP et collecte filelog | Collector backend |
| `otel-metrics` | Gateway OTLP et collecte des métriques | Collector backend |

Le groupe de consommation du backend est `otel-backend`. La séparation des
topics évite de décoder des payloads de types différents dans un même flux.

### 3.3 Flux VM

Chaque VM active exécute un Elastic Agent enrôlé dans la policy Fleet
`data-fleet`. Les intégrations System, Kafka, MongoDB et PostgreSQL envoient
leurs événements directement vers Elasticsearch.

Les VM ne publient pas leur télémétrie dans `otel-logs`, `otel-metrics` ou
`otel-traces`.

## 4. Configuration et sources IaC

| Domaine | Source versionnée |
| --- | --- |
| Architecture et manifests Kubernetes | `v3/platform/kubernetes/` |
| Collecteurs et buffer Kafka | `v3/platform/kubernetes/base/observability/otel-kafka.yaml` |
| Instrumentation applicative | `kubernetes/apps/supermarket-demo/v3/otel-instrumentation.yaml` |
| Provisionnement des VM | `v3/ansible/` |
| Policy Fleet et intégrations VM | `v3/platform/elk/fleet/` et `v3/platform/elk/scripts/` |
| Dashboards et objets Kibana | `v3/platform/elk/dashboards/` |
| Validation partagée | `validation/otel/` et cibles du `Makefile` |

Toute modification durable doit être réalisée dans ces sources puis appliquée
avec la cible `Makefile` adaptée. Les secrets, mots de passe et jetons restent
hors Git.

## 5. Contraintes techniques

### 5.1 Déploiement déclaratif

Kubernetes est géré par Kustomize. Ansible est réservé au provisionnement des
VM et aux services qui ne relèvent pas du cluster. Les rôles Ansible doivent
rester idempotents.

### 5.2 Administration Fleet

Les collecteurs EDOT Kubernetes sont gérés par Fleet via OpAMP. Les agents des
VM sont installés et enrôlés par Ansible. L’identité d’un agent actif est
réutilisée lors d’un reprovisionnement afin d’éviter les doublons dans Fleet.

### 5.3 Sécurité des secrets

Les mots de passe et clés d’API sont fournis par les variables d’environnement,
les Secrets Kubernetes ou les scripts de credentials prévus par le dépôt. Ils
ne doivent pas apparaître dans les manifests versionnés, les logs ou la
documentation.

### 5.4 Transport des signaux

Kafka fournit le tampon des flux applicatifs et Kubernetes. Le Collector
backend applique le traitement et l’export vers Elastic. La chaîne VM reste
directe afin de ne pas ajouter Kafka au chemin de collecte Fleet.

## 6. Déploiement et validation

Valider les sources sans appliquer de ressource :

```bash
make kubernetes-validate
make ansible-validate
```

Déployer la plateforme et l’application avec les cibles prévues par le
Makefile :

```bash
export POSTGRESQL_PASSWORD='...'
make deploy
```

Vérifier la chaîne après déploiement :

```bash
make otel-validation
make kafka-jolokia-verify
make dashboards-verify
```

Les contrôles d’état complémentaires et les procédures de dépannage sont
décrits dans [Déploiement et exploitation](deploiement-et-exploitation.md).

## 7. Critères techniques d’acceptation

| ID | Contrôle | Critère de succès |
| --- | --- | --- |
| TA-01 | `make kubernetes-validate` | Le rendu Kustomize est généré sans erreur |
| TA-02 | `make ansible-validate` | Les playbooks v3 passent le contrôle de syntaxe |
| TA-03 | `make otel-validation` | Les flux OTLP attendus sont validés |
| TA-04 | `make kafka-jolokia-verify` | Les métriques Kafka attendues sont accessibles |
| TA-05 | `make dashboards-verify` | Les datasets nécessaires aux dashboards sont récents |
| TA-06 | Fleet et Discover | Les données VM sont présentes et séparées des topics OTLP |

## 8. Références

- [Architecture v3](architecture-v3.md) : invariants et topologie ;
- [Spécification fonctionnelle v3](specification-fonctionnelle-v3.md) :
  capacités et critères fonctionnels ;
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie-v3.md) :
  chaîne détaillée et sources IaC ;
- [README de la plateforme v3](../v3/platform/README.md) : exploitation des
  composants Elastic et Kubernetes.
