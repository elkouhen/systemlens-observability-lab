# Spécification technique

Cette spécification décrit l’implémentation de référence de la chaîne
d’observabilité. Elle précise les composants, les interfaces, les flux et
les contraintes qui réalisent les exigences de la
[spécification fonctionnelle](specification-fonctionnelle.md).

| Élément | Définition |
| --- | --- |
| Nature | Spécification technique de référence |
| Périmètre | Kubernetes, EDOT, Kafka et Elastic de l’architecture active |
| Public | Architectes, développeurs plateforme et opérateurs |
| Version Elastic | `9.4.3` |
| Architecture associée | [Architecture active](architecture.md) |

## 1. Découpage technique

L’architecture sépare les chemins de collecte selon leur origine : les applications et
Kubernetes passent par OpenTelemetry, EDOT et Kafka ; les VM passent par
Elastic Agent EDOT standalone et exportent vers le Collecteur Edge.

Cette séparation réduit le couplage entre la collecte Kubernetes et la
collecte des VM. Elle impose en contrepartie deux modes d’administration : les
collecteurs Kubernetes sont déclarés par Kustomize, tandis que les agents VM
sont provisionnés par Ansible en mode EDOT standalone.

## 2. Topologie des composants

| Composant | Déploiement | Fonction technique |
| --- | --- | --- |
| Service `otel-edge-vm` | Kubernetes, namespace `elastic-stack` | Exposer le Collecteur Edge sur les ports `4317` et `4318` |
| EDOT DaemonSet | Kubernetes | Lire les logs stdout et les métriques Kubernetes prévues par la configuration |
| Kafka | `poc-01` | Tamponner les signaux applicatifs, Kubernetes et VM dans trois topics dédiés |
| Collector backend EDOT | `otel-backend-01` | Consommer Kafka, traiter les signaux et les exporter vers Elastic |
| HAProxy et routage TLS | `otel-edge-01` | Exposer les points d’entrée OTLP, Elasticsearch, Kibana et Fleet |
| Elasticsearch | `elk-01` | Stocker les signaux et fournir les API d’ingestion et de recherche |
| Kibana | `elk-01` | Fournir Discover, APM, Fleet et les dashboards |
| Fleet Server | `elk-01` | Fournir le plan de contrôle Fleet et le monitoring OpAMP optionnel |
| Elastic Agent EDOT standalone | Chaque VM active | Collecter les logs et métriques des VM et des services intégrés |

Les workloads applicatifs utilisent le namespace `h0tl-supermarche-app`. Les
ressources de plateforme utilisent `elastic-stack`.

## 3. Interfaces et flux

### 3.1 Interfaces Kubernetes

Le Service `otel-edge-vm` expose le Collecteur Edge sur les ports OTLP `4317`
et `4318`. Les applications et les collecteurs Kubernetes utilisent ce Service
comme point d’entrée OTLP.

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
| `otel-traces` | Collecteur Edge et collecte de traces | Collector backend |
| `otel-logs` | Collecteur Edge et collecte filelog | Collector backend |
| `otel-metrics` | Collecteur Edge et collecte des métriques | Collector backend |

Le groupe de consommation du backend est `otel-backend`. La séparation des
topics évite de décoder des payloads de types différents dans un même flux.

### 3.3 Flux VM

Chaque VM active exécute un Elastic Agent EDOT standalone. Il collecte les
logs locaux et les métriques hôte, puis les publie en OTLP vers le Collecteur
Edge ; les signaux suivent ensuite `otel-logs`, `otel-metrics` ou
`otel-traces` jusqu’au Collector backend.

## 4. Configuration et sources IaC

| Domaine | Source versionnée |
| --- | --- |
| Architecture et manifests Kubernetes | `architecture/platform/kubernetes/` |
| Collecteurs et buffer Kafka | `architecture/platform/kubernetes/base/observability/otel-kafka.yaml` |
| Instrumentation applicative | `kubernetes/apps/supermarket-demo/default/otel-instrumentation.yaml` |
| Provisionnement des VM | `architecture/ansible/` |
| Configuration EDOT VM et intégrations Elastic | `architecture/ansible/roles/elastic_agent/` et `architecture/platform/elk/fleet/` |
| Dashboards et objets Kibana | `architecture/platform/elk/dashboards/` |
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

Les collecteurs EDOT Kubernetes et les agents EDOT standalone des VM sont
configurés par les sources IaC correspondantes. Le monitoring Fleet OpAMP est
optionnel et ne fait pas partie du chemin de collecte.

### 5.3 Sécurité des secrets

Les mots de passe et clés d’API sont fournis par les variables d’environnement,
les Secrets Kubernetes ou les scripts de credentials prévus par le dépôt. Ils
ne doivent pas apparaître dans les manifests versionnés, les logs ou la
documentation.

### 5.4 Transport des signaux

Kafka fournit le tampon des flux applicatifs, Kubernetes et VM. Le Collector
backend applique le traitement et l’export vers Elastic. Les VM ne passent pas
par un collecteur Kubernetes intermédiaire.

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
make vms-up
make vm-status
make deploy
```

Vérifier la chaîne après déploiement :

```bash
make otel-validation
make kafka-jolokia-verify
make dashboards-verify
```

Les contrôles d’état complémentaires et les procédures de dépannage sont
déclarés dans le `Makefile` et les README des composants.

## 7. Critères techniques d’acceptation

| ID | Contrôle | Critère de succès |
| --- | --- | --- |
| TA-01 | `make kubernetes-validate` | Le rendu Kustomize est généré sans erreur |
| TA-02 | `make ansible-validate` | Les playbooks de l’architecture passent le contrôle de syntaxe |
| TA-03 | `make otel-validation` | Les flux OTLP attendus sont validés |
| TA-04 | `make kafka-jolokia-verify` | Les métriques Kafka attendues sont accessibles |
| TA-05 | `make dashboards-verify` | Les datasets nécessaires aux dashboards sont récents |
| TA-06 | Fleet et Discover | Les données VM sont présentes et séparées des topics OTLP |

## 8. Références

- [Architecture](architecture.md) : invariants et topologie ;
- [Spécification fonctionnelle](specification-fonctionnelle.md) :
  capacités et critères fonctionnels ;
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie.md) :
  chaîne détaillée et sources IaC ;
- [README de l'architecture](../architecture/README.md) : flux et composants
  de la plateforme.
