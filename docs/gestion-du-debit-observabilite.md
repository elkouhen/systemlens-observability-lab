# Gestion du débit de télémétrie

Ce guide décrit comment limiter le débit des traces, logs et métriques pour
les trois architectures du POC. Il ne faut pas confondre les mécanismes :

| Mécanisme | Fonction |
| --- | --- |
| Rate limiting | Refuser ou ralentir un débit entrant au-delà d'un seuil |
| Sampling/filtrage | Réduire volontairement le volume conservé |
| Batch | Regrouper les événements pour réduire le coût réseau et Elasticsearch |
| Backpressure | Ralentir la source lorsque le consommateur est saturé |
| Queue/buffer | Absorber une indisponibilité ou un pic temporaire |
| `memory_limiter` | Protéger un Collector contre l'épuisement mémoire |

Les valeurs ci-dessous sont des points de départ. Elles doivent être ajustées
à partir du volume observé, de la taille moyenne des événements, du nombre de
partitions Kafka et de la capacité d'indexation Elasticsearch.

## Stratégie commune

Le débit doit être contrôlé dans cet ordre :

```text
Entrée réseau → limite par source → réduction par signal → batch
→ queue/backpressure → indexation Elasticsearch
```

Définir un budget par signal, par exemple en événements par seconde :

| Signal | Budget à définir | Réaction au dépassement |
| --- | --- | --- |
| Traces | spans/s par service | sampling, puis réponse 429 au Gateway |
| Logs | événements/s par namespace ou VM | filtrage des logs verbeux, puis ralentissement |
| Métriques | séries actives et points/s | augmenter l'intervalle de collecte ou désactiver une famille |

Le budget doit être mesuré après enrichissement, car les événements enrichis
sont plus volumineux que les événements à l'entrée.

## Traces applicatives

### v1 — Elastic classique

```text
Agent APM → APM Server → Logstash → Elasticsearch
```

- Limiter à la source avec le taux de transaction APM et le sampling des
  transactions ; conserver un sampling plus élevé pour les erreurs.
- Régler la capacité APM Server et surveiller les files d'attente avant
  d'augmenter Logstash.
- Utiliser la queue persistante Logstash pour absorber une indisponibilité
  Elasticsearch ; elle ne remplace pas un plafond de débit.
- Sur Logstash, contrôler `pipeline.workers`, `pipeline.ordered` et la taille
  de la queue. Éviter d'ajouter une transformation coûteuse dans le pipeline
  APM avant d'avoir mesuré son impact.
- Vérifier le débit avec les métriques APM et les logs de rejet APM Server et
  Logstash.

### v2 — OpenTelemetry + Kafka

```text
OTel Java Agent → EDOT Gateway → Kafka otel-traces → EDOT backend → Elasticsearch
```

- Appliquer le sampling dans l'agent ou au Gateway. Le sampling doit être
  cohérent avec la corrélation logs/traces ; les erreurs et transactions lentes
  doivent rester prioritaires.
- Exposer le Gateway derrière une limite réseau par client ou namespace. Un
  middleware Traefik peut limiter les requêtes OTLP, mais il ne connaît pas le
  nombre de spans contenu dans chaque requête ; il faut donc compléter cette
  limite par le sampling.
- Conserver `memory_limiter` et `batch` dans le Gateway et le Collector backend.
  `memory_limiter` protège la mémoire mais ne constitue pas un rate limiter.
- Dimensionner `otel-traces` avec suffisamment de partitions et surveiller le
  consumer lag. En cas de saturation, réduire le sampling avant d'augmenter
  uniquement la taille des queues.

### v3 — Hybride Fleet

Le flux de traces v3 est identique à celui de v2. Les règles de sampling et de
limitation du Gateway s'appliquent donc aux applications, tandis que Fleet ne
transporte pas les traces des VM dans cette architecture.

## Logs applicatifs et Kubernetes

### v1 — Elastic classique

```text
stdout des pods → Elastic Agent Kubernetes → Logstash → Elasticsearch
```

- Limiter les logs au niveau applicatif : niveau `INFO` par défaut, `DEBUG`
  activé temporairement et par namespace.
- Configurer une taille maximale de batch et une queue mémoire Filebeat/Elastic
  Agent ; surveiller les événements abandonnés lorsque la queue est pleine.
- Utiliser le pipeline Logstash pour supprimer les lignes de healthcheck,
  probes et logs répétitifs avant indexation.
- Protéger Logstash avec une queue persistante et un nombre de workers adapté.
  Une queue persistante absorbe un pic, mais doit être accompagnée d'une alerte
  sur son taux de remplissage.

### v2 — OpenTelemetry + Kafka

```text
stdout des pods → EDOT DaemonSet → Kafka otel-logs → EDOT backend → Elasticsearch
```

- Filtrer les logs répétitifs dans `filelog/kubernetes` ou dans le pipeline
  Collector avant Kafka ; ne pas parser et indexer inutilement les probes.
- Régler `batch`, `memory_limiter` et la file du Collector backend. La file
  locale limite la perte lors d'une panne Elasticsearch, mais sa capacité doit
  être surveillée.
- Ajouter une limite par namespace au niveau d'entrée si le Gateway reçoit
  aussi des logs OTLP. Pour les logs stdout collectés par DaemonSet, le levier
  principal reste le filtrage et le niveau de logs applicatif.
- Surveiller le débit du topic `otel-logs`, le consumer lag et les rejets du
  backend.

### v3 — Hybride Fleet

Les logs applicatifs et Kubernetes v3 suivent le même chemin que v2 et les
mêmes contrôles s'appliquent. Les logs VM sont traités séparément par Fleet.

## Métriques applicatives et Kubernetes

### v1 — Elastic classique

```text
Actuator / kubelet → Elastic Agent → Logstash → Elasticsearch
```

- Augmenter l'intervalle de scrutation avant d'augmenter la capacité de
  Logstash. Un intervalle de 30 secondes produit deux fois plus de points
  qu'un intervalle d'une minute.
- Réduire les métriques cardinales : labels dynamiques, identifiants de
  requête et noms de chemins non normalisés sont à éviter.
- Désactiver les familles de métriques non nécessaires dans la policy Agent.
- Surveiller le nombre de séries actives et le volume du data stream Prometheus.

### v2 — OpenTelemetry + Kafka

```text
OTel Java Agent / EDOT DaemonSet → Kafka otel-metrics → EDOT backend → Elasticsearch
```

- Utiliser `collection_interval` pour les métriques hôte et techniques ;
  conserver une fréquence plus élevée uniquement pour les signaux utiles au
  diagnostic.
- Réduire la cardinalité avant Kafka avec les processeurs OTel `filter` ou
  `transform`, après avoir vérifié que les champs utilisés par Kibana sont
  conservés.
- Dimensionner le topic `otel-metrics` à partir des séries actives, pas du seul
  nombre de messages.
- Conserver `batch` et `memory_limiter` sur les trois étages. Le consumer lag
  Kafka est le signal principal de saturation du chemin.

### v3 — Hybride Fleet

Les métriques applicatives v3 sont scrappées toutes les 15 secondes par le
receiver Prometheus du Gateway sur les endpoints `/actuator/prometheus`, puis
suivent Kafka et le Collector backend. Les métriques Kubernetes suivent le
chemin EDOT DaemonSet de v2. Les métriques VM utilisent les intervalles et la
policy Fleet décrits ci-dessous.

## Logs et métriques des VM

### v1 — Elastic classique

```text
Filebeat / Metricbeat → Logstash → Elasticsearch
```

- Réduire `period`/`scan_frequency` et limiter les fichiers surveillés avant
  d'augmenter les ressources de la VM.
- Utiliser `bulk_max_size` et la queue du Beat pour contrôler la taille des
  lots. Surveiller les fichiers trop volumineux et les rotations manquées.
- Filtrer les logs système répétitifs et les datasets inutiles dans Filebeat.
- Contrôler le débit reçu par Logstash sur le port Beats `5045` et la queue
  persistante.

### v2 — OpenTelemetry + Kafka

```text
EDOT Agent VM → Kafka otel-logs / otel-metrics → EDOT backend → Elasticsearch
```

- Régler les `collection_interval` des receivers `hostmetrics`, Kafka,
  MongoDB et PostgreSQL dans le template EDOT VM.
- Filtrer les fichiers de logs et réduire les familles de métriques avant
  l'export Kafka.
- Conserver la queue locale et le retry de l'exporteur, puis surveiller son
  remplissage et le consumer lag Kafka.
- Ne pas augmenter la queue sans limite : lorsque le disque local est saturé,
  il faut réduire le débit ou augmenter la capacité backend.

### v3 — Hybride Fleet

```text
Elastic Agent Fleet VM → Elasticsearch
```

- Régler les périodes des inputs System, Kafka, MongoDB et PostgreSQL dans la
  policy `data-fleet`.
- Désactiver les inputs non nécessaires et limiter les chemins de logs suivis.
- Utiliser les processeurs de la policy pour supprimer les événements répétitifs
  avant indexation ; conserver `host.name`, `service.name` et les champs
  `data_stream.*` nécessaires aux dashboards.
- Fleet fournit la gestion et la supervision de l'agent, mais ne fournit pas un
  quota global de débit Elasticsearch. Pour un plafond strict, appliquer une
  limite en amont par VM ou par réseau et compléter par le filtrage.
- Surveiller l'état `Healthy` de l'agent, les erreurs d'output et le débit des
  data streams `logs-*` et `metrics-*`.

## Contrôles et alertes

Pour chaque architecture, créer au minimum des alertes sur :

- taux de rejet ou d'erreur de l'agent, du Gateway, d'APM Server ou de Logstash ;
- remplissage des queues locales et persistantes ;
- consumer lag Kafka pour `otel-traces`, `otel-logs` et `otel-metrics` ;
- taux de réponse `429` et erreurs d'indexation Elasticsearch ;
- volume d'événements par `service.name`, `kubernetes.namespace.name` et
  `host.name` ;
- nombre de séries actives et cardinalité des métriques.

Une limitation est considérée comme opérationnelle seulement si son seuil,
son action de dépassement, sa métrique de saturation et sa procédure de retour
à la normale sont documentés.

## Mise en œuvre dans ce dépôt

Les réglages actuels fournissent déjà du batch, de la protection mémoire et du
buffering pour les flux EDOT v2/v3. Ils ne définissent pas encore de quotas
numériques par source. Avant de fixer ces quotas :

1. mesurer le débit réel avec `make dashboards-verify` et les métriques des
   Collectors ;
2. choisir un budget séparé pour traces, logs et métriques ;
3. ajouter les limites dans les manifests de l'architecture active ;
4. valider le rendu avec `make kubernetes-validate` ;
5. provoquer un dépassement contrôlé et vérifier le rejet, le lag et la reprise.
