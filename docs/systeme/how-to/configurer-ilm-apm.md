# Configurer la rétention ILM des données APM

Utilisez ce guide pour maîtriser la rétention des traces, erreurs et métriques
APM stockées dans Elasticsearch. Il s'applique aux data streams APM ; il ne
modifie ni l'agent Java ni APM Server.

Les templates et mappings APM sont gérés par Elastic. Ne les modifiez pas et
ne créez pas un index ordinaire nommé `traces-apm-default` : ce nom est réservé
au data stream. Les personnalisations durables passent par le composant
`@custom` référencé par le template APM.

## Prérequis

- L'intégration APM est installée et `traces-apm-default` existe comme data
  stream.
- Le compte utilisé dans Kibana Dev Tools dispose des droits de gestion des
  index et des policies ILM.
- Aucune réindexation active ne cible le data stream. Attendre sa fin avant de
  forcer un rollover.

Vérifier d'abord le data stream et le template effectivement utilisés :

```http
GET /_data_stream/traces-apm-default
```

Noter la valeur de `template`, puis consulter le template :

```http
GET /_index_template/<template>
```

La liste `composed_of` doit référencer `traces-apm@custom`. Si ce n'est pas le
cas, ne pas appliquer les commandes ci-dessous sans vérifier la procédure
correspondant à la version installée de l'intégration APM.

## Créer une policy simple pour les traces

L'exemple suivant est dimensionné pour un disque Elasticsearch de 50 Go : il
conserve les traces dix jours. Le backing index est renouvelé chaque jour ou
lorsqu'un shard primaire atteint 5 Go, selon le premier seuil atteint. À un
volume observé de 2,35 Go par jour, cette rétention représente environ 23,5 Go
de traces primaires. Surveiller l'occupation du disque afin de préserver une
marge pour les métriques, les merges et les pics d'ingestion.

```http
PUT /_ilm/policy/apm-traces-10d
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_primary_shard_size": "5gb",
            "max_age": "1d"
          }
        }
      },
      "delete": {
        "min_age": "10d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

Surveillez l'occupation du disque et adaptez `10d`, `1d` et `5gb` au volume
réel. Les traces brutes sont généralement plus coûteuses que les métriques
agrégées. Avec une réplique effectivement allouée, doublez approximativement
le besoin de stockage et réduisez la rétention ou augmentez le volume.

## Appliquer la policy sans écraser les assets APM

Créer ou mettre à jour uniquement le composant `traces-apm@custom` :

```http
PUT /_component_template/traces-apm@custom
{
  "template": {
    "settings": {
      "index": {
        "lifecycle": {
          "name": "apm-traces-10d",
          "prefer_ilm": true
        }
      }
    }
  }
}
```

Cette opération s'applique aux **nouveaux** backing indices seulement. Elle ne
change ni le mapping ni la policy du backing index d'écriture actuel.

Pour prendre effet immédiatement, forcer un rollover pendant une période
calme :

```http
POST /traces-apm-default/_rollover
```

Vérifier le résultat :

```http
GET /_data_stream/traces-apm-default
GET /traces-apm-default/_ilm/explain
```

Le data stream doit exposer `ilm_policy: apm-traces-10d` et le nouveau backing
index doit être géré par cette policy.

## Autres familles APM

Appliquez des rétentions distinctes selon l'usage :

| Famille | Exemple de rétention | Composant à personnaliser |
| --- | --- | --- |
| traces brutes | 10 jours (disque de 50 Go) | `traces-apm@custom` |
| erreurs APM | 30 à 90 jours | `logs-apm.error@custom` |
| métriques applicatives | 90 jours ou plus | `metrics-apm.app@custom` |

Créez une policy distincte pour chaque durée, puis répétez la configuration du
composant avec le nom de policy correspondant. Ne réutilisez pas une policy de
traces courtes pour les métriques si les graphiques historiques doivent rester
disponibles.

## Contrôles et limites

- Un cluster mono-nœud peut rester `yellow` à cause des réplicas non alloués ;
  cela n'empêche pas ILM de supprimer les backing indices arrivés à échéance.
- Le rollover crée un nouveau backing index mais ne supprime pas tout de suite
  l'ancien : la phase `delete` s'en charge à l'âge défini.
- Conservez les index d'archive issus d'une migration séparés des data streams
  APM. Une archive telle que `apm_legacy_traces_YYYYMMDD` ne doit pas être
  ajoutée aux patterns de la vue APM tant que ses mappings historiques ne sont
  pas validés.
- Après une mise à niveau mineure d'Elastic ou du package APM, contrôlez que le
  template APM référence toujours le composant `@custom`.

Référence : [gestion du cycle de vie des index APM](https://www.elastic.co/docs/solutions/observability/apm/index-lifecycle-management).
