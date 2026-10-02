# Architecture : Hybride Fleet

Architecture de référence avec Elastic Stack `9.5.4`. Les applications,
Kubernetes et les VM utilisent OpenTelemetry/EDOT avec Kafka comme tampon. Le
cluster Kubernetes de référence est k3s sur `k3s-01` ; k3d reste disponible
uniquement pour la comparaison pendant la migration.
Les agents VM restent standalone et sont supervisés par Fleet via OpAMP, sans
policy Fleet de collecte concurrente.

## Topologie VM

```text
Kubernetes / opérateur
          |
          v
      otel-edge-01  -- OTLP
          |
          v
      otel-backend-01  -- Kafka OTel + backend OTel
          |
          v
      supermarket-middleware-01  -- Kafka métier + MongoDB + PostgreSQL

      supermarket-middleware-01  -- Kafka métier + MongoDB + PostgreSQL

      otel-backend-01  -- Kafka OTel + exporteur backend --> elk-01
                                                  Elasticsearch + Kibana + Fleet Server
```

`otel-edge-01` est le point d’entrée OTLP exposé. Les accès Kibana,
Elasticsearch, Fleet et APM sont directs vers `elk-01`. `otel-backend-01` héberge
le Kafka dédié OTel et le Collector backend, `supermarket-middleware-01` héberge les middlewares du
scénario et son Kafka métier, et `elk-01` porte le stockage et la consultation
Elastic.

Le code Java et les images sont partagés avec la plateforme. Le déploiement et
la recette sont décrits dans le README Ansible et les cibles du `Makefile`.
Le cluster k3s de référence se prépare avec `make k3s-vm-up`, puis son
kubeconfig local peut être exporté avec `make k3s-kubeconfig`.

## Commandes principales

`make help` affiche uniquement les parcours opérateur courants. Les cibles
techniques conservées dans le `Makefile` servent aux dépendances et aux
diagnostics ciblés ; elles restent utilisables directement lorsque cela est
nécessaire.

Pour préparer et vérifier l'environnement :

```bash
make architecture-status
make credentials-generate
make platform-status
make kubernetes-validate
make ansible-validate
make ci-run
```

Pour construire et déployer :

```bash
make apps-build
make apps-test
make vms-start
make architecture-deploy
```

Pour contrôler la chaîne d'observabilité et l'application :

```bash
make dashboards-verify
make trace-context-verify
make observability-schema-verify
make application-data-verify
make order-service-command
```

Les opérations de cycle de vie et de diagnostic avancé restent disponibles
depuis `make help`, notamment `make retention-deploy` et `make otel-validate`.
`make vms-destroy` est destructif et demande une validation explicite de
l'opérateur.

Documents propres à l'architecture :

- [diagramme C4 interactif](https://elkouhen.github.io/systemlens-observability-lab/c4.html#/) ;
- [provisionnement des VM `supermarket-middleware-01`, `otel-backend-01`, `otel-edge-01` et `elk-01`](ansible/README.md) ;

La rétention des signaux et des logs est vérifiable avec
`make retention-verify`.
