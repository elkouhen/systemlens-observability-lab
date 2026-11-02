# ADR-011 : nommer les spans HTTP client par leur chemin normalisé

## Statut

Accepted

## Date

2026-11-02

## Contexte

La convention sémantique HTTP d'OpenTelemetry nomme un span client
`{méthode} {url.template}`, et `{méthode}` seul faute de gabarit. L'agent
Java 2.28.1 ne connaît pas le gabarit des appels `RestTemplate` : l'appel
order-service → `POST http://inventory-service:3001/api/reservations`
apparaît comme un span `POST` dans `POST /api/orders`. Dans l'UI APM, rien ne
distingue deux appels sortants d'un même service.

Inventaire des appels HTTP sortants (Elasticsearch, `traces-apm*`, 7 jours,
et sources Java) :

| Service | Client | URL appelée |
| --- | --- | --- |
| order-service | `RestTemplate` (`RestTemplateBuilder`, client JDK `HttpClient`, scope `io.opentelemetry.java-http-client`) | `http://inventory-service:3001/api/reservations` |
| les trois services | registre Micrometer OTLP (`HttpURLConnection`, scope `io.opentelemetry.http-url-connection`) | `http://otel-edge-vm.elastic-stack.svc.cluster.local:4318/v1/metrics` |

Les autres échanges passent par Kafka (`KafkaTemplate`, `@KafkaListener`) et
JDBC. Aucune URL appelée ne contient aujourd'hui d'identifiant, mais
`inventory-service` expose `GET /api/products/{productId}` (codes du type
`PASTA-500G`) : un futur client l'appellera avec un identifiant.

## Décision

Le collecteur Edge renomme les spans HTTP client, pour toutes les
applications qu'il reçoit, dans le processor
`transform/http-client-span-name` du pipeline `traces`
(`ansible/roles/otel_edge/templates/otel-edge.yaml.j2`), avant
`transform/kafka-topic`.

- **Spans concernés** : `kind` = `CLIENT`, attribut `url.full` présent et nom
  égal à `http.request.method` (ou `HTTP` pour une méthode inconnue). Un nom
  déjà plus précis, les spans serveur, base de données et Kafka ne changent
  pas.
- **Nom** : `{nom actuel} {chemin}`. Le chemin est `url.full` sans schéma,
  hôte, port, requête ni fragment ; un chemin vide vaut `/`.
- **Normalisation** : un segment identifiant devient `{id}`, pour borner la
  cardinalité des noms. Est identifiant un segment entièrement numérique, un
  UUID, une suite hexadécimale d'au moins 16 caractères, ou un code en
  majuscules, chiffres, `-` et `_` contenant au moins un chiffre. Un segment
  en minuscules (`api`, `v1`, `reservations`) est conservé. La substitution
  est appliquée deux fois, pour couvrir des identifiants contigus.
- Les attributs ne changent pas : `url.full`, `server.address` et
  `server.port` restent la source de `span.destination.service.resource`.

| URL appelée | Nom du span |
| --- | --- |
| `POST http://inventory-service:3001/api/reservations` | `POST /api/reservations` |
| `GET http://inventory-service:3001/api/products/PASTA-500G` | `GET /api/products/{id}` |
| `GET http://h/api/v1/orders/123/items/<uuid>?x=1` | `GET /api/v1/orders/{id}/items/{id}` |
| `POST http://otel-edge-vm…:4318/v1/metrics` | `POST /v1/metrics` |

La règle est générique : aucune valeur n'est propre à `supermarche`.

## Alternatives considérées

- **Règles de gabarit de l'agent Java** : l'agent 2.28.1 contient un
  personnalisateur expérimental (`RegexUrlTemplateCustomizer`) qui lit
  `instrumentation/development.java.common.http.client.url_template_rules`.
  Cette liste structurée n'est lue que dans la configuration déclarative
  YAML : les propriétés plates (`otel.properties`) ne la transmettent pas.
  Elle exige aussi `emit-experimental-telemetry`, et chaque application
  devrait déclarer ses propres expressions régulières. Rejeté : migration de
  la configuration des agents vers un format expérimental, règles par
  application.
- **Gabarit côté application** (`RestTemplate` à URI template, observation
  Micrometer) : l'agent OTel ne lit pas le gabarit du `RestTemplate`, et la
  règle serait à reproduire dans chaque client.
- **Attribut `url.template` posé par l'Edge** : ajouterait un champ
  `labels.url_template` aux documents APM sans usage actuel. Le chemin reste
  dans le cache du processor.

## Conséquences

- Les spans client et les transactions racines de type client prennent leur
  chemin : l'appel vers inventory-service devient `POST /api/reservations`,
  et l'export Micrometer, transaction racine, devient `POST /v1/metrics`
  (au lieu de `POST`). Ces transactions d'export et les sondes de santé ne
  sont pas filtrées.
- Les métriques agrégées d'APM Server portent le nouveau nom
  (`span.name` de `metrics-apm.service_destination.*`,
  `transaction.name` de `metrics-apm.transaction.*`) ; la ressource de
  destination `inventory-service:3001` est inchangée.
- Un segment identifiant non couvert (mot en minuscules servant de clé,
  par exemple) garde sa valeur dans le nom. Une application dont les URL
  contiennent de tels segments doit étendre l'expression du processor.
- Les spans HTTP encore émis avec les anciennes conventions (`http.method`,
  `http.url`) ne sont pas renommés.

## Vérification

Le 2026-11-02, après `make otel-edge-vm-provision` et douze commandes
(`make order-service-command`, dont deux en rupture de stock), le span
client de `POST /api/orders` s'appelle `POST /api/reservations` dans
`traces-apm-supermarche_homologation`. Aucun span ni transaction ne s'appelle
`POST` seul ; les transactions métier, de santé et d'export Micrometer
arrivent toujours. Un essai local du processor (collecteur 0.164.0,
OTLP/JSON, exporteur `debug`) donnent les noms du tableau.
