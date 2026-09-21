# Validation OpenTelemetry

Ce projet Ansible envoie une métrique OTLP/HTTP avec un marqueur unique, puis
attend son indexation dans Elasticsearch. Le parcours est exécuté en SSH sur
la machine du groupe `otel_collectors`. Comme Kibana Discover lit ces index, le playbook vérifie
également que l'API Kibana est joignable et affiche le marqueur à rechercher
dans Discover.

Le parcours validé dans l’architecture active est :

- `gateway-directe-ssh` : playbook SSH sur un collecteur → Gateway EDOT
  `127.0.0.1:4319` → Kafka `otel-metrics` → exporteur OTel `poc-01` → data stream
  `metrics-*` → Kibana.

## Prérequis

- Ansible, Vagrant et la VM `poc-01` démarrée ;
- un compte Elasticsearch ayant le droit de lire `metrics-*` ;
- le mot de passe fourni uniquement par l'environnement :

  ```bash
  source ./architecture/platform/elk/scripts/load-credentials.sh
  ```

## Paramétrage de l'inventaire

L'inventaire fournit les hôtes, leurs paramètres de connexion Ansible et
`otel_gateway_direct_endpoint`. Les URL Elastic, les paramètres de validation
et les identifiants sont définis dans `playbook.yml`.

Ne pas inscrire `elasticsearch_password` dans l'inventaire : sa valeur est
lue depuis `ELASTICSEARCH_PASSWORD`.

## Exécution et résultat attendu

Depuis la racine du dépôt :

```bash
make otel-validation
```

Le playbook porte le tag `host`. Sans tag, le parcours SSH est exécuté.

| Tag | Parcours validé | Commande |
| --- | --- | --- |
| `host` | Depuis le collecteur, directement vers le Gateway local | `make otel-validation VALIDATION_TAGS=host` |

Les tags sont transmis à Ansible avec `--tags`. Une valeur inconnue ne
sélectionne aucun play et ne constitue pas une validation.

Depuis ce répertoire, Ansible utilise directement `ansible.cfg` et son
inventaire par défaut :

```bash
source ../../architecture/platform/elk/scripts/load-credentials.sh
ansible-playbook playbook.yml
```

Pour un inventaire distinct :

```bash
make otel-validation INVENTORY=validation/otel/inventory/mon-environnement.yml
```

Le playbook réussit uniquement après avoir reçu une réponse OTLP réussie, un
statut `200` de Kibana et un document correspondant au marqueur dans `metrics-*`.
Il affiche alors le marqueur exact à coller dans Kibana Discover.
