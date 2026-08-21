# Matrice des métriques et de leurs sources

Une métrique est considérée comprise seulement lorsque sa source, son
collecteur, son chemin et sa destination sont identifiés. Les noms de champs
peuvent différer entre ECS, intégrations Elastic et OpenTelemetry : cette table
évite de les confondre.

| Famille / métrique attendue | Source primaire | Collecteur actif | Transport / traitement | Data stream ou convention | Dashboard consommateur | Alternative OpenTelemetry / Elastic à comparer |
| --- | --- | --- | --- | --- | --- | --- |
| CPU VM (`metrics.system.cpu.utilization`) | noyau Linux de la VM OpenTelemetry | EDOT `host_metrics` | EDOT → Elasticsearch ; pipeline de compatibilité `host.name` | `metrics-hostmetricsreceiver.otel-*` ; `metrics.*` | Infrastructure > Hosts | Metricbeat system ; Elastic Agent System integration |
| CPU, mémoire, disque, réseau de la VM Beats | noyau Linux | Metricbeat system | Metricbeat → Elasticsearch | `metrics-system.*` ; ECS `system.*` | Infrastructure > Hosts | EDOT `host_metrics` ; Elastic Agent System integration |
| CPU / mémoire nœuds Kubernetes | cgroups, Kubelet, API Kubernetes | EDOT DaemonSet / collector cluster | OTLP → gateway → Elasticsearch avec `elasticinframetrics` | `metrics-*` ; convention Infrastructure | Infrastructure / Inventory | Elastic Agent Kubernetes integration |
| JVM, HTTP, Kafka et métriques métier applicatives | Micrometer / Actuator Java | SDK/agent OpenTelemetry Java | OTLP HTTP → gateway → Elasticsearch ; `cumulativetodelta` | `metrics-*` ; attribut `service.name` | APM Services et dashboards applicatifs futurs | Agent Elastic APM + Micrometer ; OTLP via APM Server |
| Débit, durée et taux d'erreur APM | traces applicatives | connecteur `elasticapm` du backend OTel | Kafka `otel-traces` → backend OTel → Elasticsearch | `metrics-*` APM dérivées | APM Services / Transactions | Agent Elastic APM → APM Server |
| Connexions, opérations, stockage MongoDB | API MongoDB locale | EDOT MongoDB, Elastic Agent ou Metricbeat selon le profil | collecteur local → Elasticsearch | convention OTel ou `metrics-mongodb.*` | Intégration MongoDB | comparer la couverture et les dashboards par profil |
| État replica set / primary MongoDB | commande MongoDB `replSetGetStatus` | Elastic Agent + Fleet MongoDB | Agent → Elasticsearch ; pipeline d'adresse de service | `metrics-mongodb.replstatus-*` | SystemLens · MongoDB clusters | collecte custom OTel / exporter MongoDB, à qualifier |
| Brokers, topics, groupes et partitions Kafka | protocole Kafka | EDOT Kafka Metrics, Elastic Agent ou Metricbeat selon le profil | collecteur local → Elasticsearch | convention OTel ou `metrics-kafka.*` | Intégration Kafka | métriques client Micrometer/OTel, complémentaires des métriques broker |
| JVM, KRaft, réseau et réplication Kafka | MBeans JMX via Jolokia | Elastic Agent + intégration Kafka/Jolokia | Agent → Elasticsearch | `metrics-kafka.*` | Intégration Kafka | exporter JMX en Prometheus puis receiver Prometheus EDOT ; **non couvert à ce stade par les profils EDOT et Beats** |
| PostgreSQL : activité, bgwriter, taille | vues statistiques PostgreSQL | EDOT PostgreSQL | EDOT → Elasticsearch | `metrics-postgresqlreceiver.otel-*` | Intégration PostgreSQL | Elastic Agent PostgreSQL integration |

## Conventions à contrôler

- `host.name` est la dimension de regroupement attendue par de nombreux
  dashboards Infrastructure. Les métriques OTel de la VM OpenTelemetry portent aussi
  l'attribut natif `resource.attributes['host.name']`.
- `service.name` identifie un service applicatif. Il ne doit pas être remplacé
  par une adresse locale de scrape.
- `service.address` des métriques MongoDB locales est normalisé par pipeline
  vers le nom d'hôte pour que les regroupements ne fusionnent pas les adresses
  `127.0.0.1`.
- Les champs et data streams réellement présents prévalent toujours sur les
  noms supposés : les contrôler dans Discover avant de modifier un dashboard.

## Chantiers de qualification

Pour chaque alternative de la dernière colonne, ajouter une ligne de résultat
après test : version du composant, métriques couvertes, nom de data stream,
compatibilité dashboard, coût d'administration et décision retenue. Cette
comparaison doit porter sur des documents indexés, pas uniquement sur la
documentation du fournisseur.
