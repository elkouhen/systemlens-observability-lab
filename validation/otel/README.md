# Validation OpenTelemetry

Ce projet Ansible envoie deux logs OTLP/HTTP avec des marqueurs uniques, puis
attend l'indexation de chacun dans Elasticsearch. Le premier parcours est
exécuté en SSH sur la VM ; le second est appelé directement depuis le poste de
contrôle Ansible. Comme Kibana Discover lit ces index, le playbook vérifie
également que l'API Kibana est joignable et affiche le marqueur à rechercher
dans Discover.

Les parcours validés en architecture v3 sont :

- `gateway-directe-ssh` : playbook SSH sur `data-01` → Gateway EDOT
  `127.0.0.1:4319` → Kafka `otel-logs` → `otel-kafka-exporter` → data stream
  `logs-*` → Kibana ;
- `haproxy-ip-port-direct` : contrôleur Ansible → HAProxy
  `192.168.33.10:4318` → Gateway EDOT `127.0.0.1:4319` → même chaîne Elastic.

## Prérequis

- Ansible, Vagrant et la VM `data-01` démarrée ;
- un compte Elasticsearch ayant le droit de lire `logs-*` ;
- le mot de passe fourni uniquement par l'environnement :

  ```bash
  source ./v3/platform/elk/scripts/load-credentials.sh
  ```

L'IP `192.168.33.10` est l'interface privée de la VM, joignable depuis le
poste de contrôle. Elle permet de vérifier HAProxy par son IP et son port,
sans passer par SSH. L'adresse `192.168.5.2:4318`, destinée aux pods
Kubernetes, reste un endpoint distinct de cette recette.

## Paramétrage de l'inventaire

Copier ou adapter `inventory/hosts.yml`. Les paramètres sont portés par
l'inventaire pour permettre de cibler une autre instance :
`otel_gateway_direct_endpoint`, `otel_haproxy_direct_endpoint`, `kibana_url`,
`elasticsearch_url`, `elasticsearch_username`,
`elasticsearch_validate_certs`, `validation_index_pattern`,
`validation_timeout_seconds` et `validation_poll_delay_seconds`.

Ne pas inscrire `elasticsearch_password` dans l'inventaire : sa valeur est
lue depuis `ELASTICSEARCH_PASSWORD`.

## Exécution et résultat attendu

Depuis la racine du dépôt :

```bash
make otel-validation
```

Pour un inventaire distinct :

```bash
make otel-validation INVENTORY=validation/otel/inventory/mon-environnement.yml
```

Le playbook réussit uniquement après avoir reçu une réponse OTLP réussie pour
chacun des deux parcours, un statut `200` de Kibana et un document correspondant
à chacun des marqueurs dans `logs-*`. Il affiche alors les marqueurs exacts à
coller dans Kibana Discover.
