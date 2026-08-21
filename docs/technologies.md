# Technologies et sigles

Ce glossaire recense les technologies effectivement utilisées par le POC, ainsi
que les sigles rencontrés dans les configurations. Chaque lien pointe vers une
documentation officielle ; cette page n'en remplace pas la lecture détaillée.

## Observabilité Elastic et OpenTelemetry

| Technologie / sigle | Explication synthétique | Référence officielle |
| --- | --- | --- |
| **Elastic Stack (ELK)** | Ensemble Elasticsearch, Logstash et Kibana. Dans ce POC, l'ingestion est principalement assurée par Agents, Beats et Collectors plutôt que Logstash. | [Elastic Stack](https://www.elastic.co/elastic-stack) |
| **Elasticsearch (ES)** | Moteur distribué qui indexe, recherche et agrège logs, métriques et traces. | [Documentation Elasticsearch](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch) |
| **Kibana** | Interface d'exploration, de dashboards, d'APM et d'administration Fleet. | [Documentation Kibana](https://www.elastic.co/docs/explore-analyze) |
| **APM** | *Application Performance Monitoring* : analyse des services, transactions, spans, erreurs et dépendances. | [Elastic APM](https://www.elastic.co/docs/solutions/observability/apm) |
| **ECK** | *Elastic Cloud on Kubernetes* : opérateur Kubernetes qui crée et administre les ressources Elastic. | [Documentation ECK](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s) |
| **Fleet** | Plan de gestion centralisé des Elastic Agents : policies, intégrations, tokens et mises à jour. | [Fleet](https://www.elastic.co/docs/reference/fleet) |
| **Fleet Server** | Service de contrôle auquel les Elastic Agents s'enrôlent et auprès duquel ils récupèrent leurs policies. | [Fleet Server](https://www.elastic.co/docs/reference/fleet/fleet-server) |
| **Elastic Agent** | Agent unifié Elastic qui exécute les intégrations reçues de Fleet et envoie les données vers Elasticsearch. | [Elastic Agent](https://www.elastic.co/docs/reference/fleet/elastic-agent) |
| **Beats** | Famille d'agents Elastic légers, configurés localement. | [Beats](https://www.elastic.co/docs/reference/beats) |
| **Filebeat** | Beat qui lit des fichiers ou flux de logs et les envoie vers Elasticsearch. | [Filebeat](https://www.elastic.co/docs/reference/beats/filebeat) |
| **Metricbeat** | Beat qui interroge le système et des services afin de publier leurs métriques. | [Metricbeat](https://www.elastic.co/docs/reference/beats/metricbeat) |
| **EDOT** | *Elastic Distribution of OpenTelemetry* : distribution Elastic du Collector OpenTelemetry. | [EDOT Collector](https://www.elastic.co/docs/reference/edot-collector/) |
| **OpenTelemetry (OTel)** | Standard ouvert et ensemble de SDK, API et Collectors pour logs, métriques et traces. | [OpenTelemetry](https://opentelemetry.io/docs/) |
| **OTLP** | *OpenTelemetry Protocol* : protocole d'échange des signaux OTel, notamment via gRPC ou HTTP/protobuf. | [Spécification OTLP](https://opentelemetry.io/docs/specs/otlp/) |
| **ECS** | *Elastic Common Schema* : convention de champs Elastic commune aux événements indexés. | [Elastic Common Schema](https://www.elastic.co/docs/reference/ecs) |
| **W3C Trace Context** | Standard de propagation du contexte distribué, notamment l'en-tête `traceparent`. | [Trace Context](https://www.w3.org/TR/trace-context/) |

## Plateforme et automatisation

| Technologie / sigle | Explication synthétique | Référence officielle |
| --- | --- | --- |
| **Kubernetes (K8s)** | Orchestrateur de conteneurs qui exécute la plateforme Elastic et les Collectors. `K8s` est son abréviation courante. | [Kubernetes](https://kubernetes.io/docs/home/) |
| **k3d** | Outil qui exécute un cluster Kubernetes léger (k3s) dans des conteneurs Docker. | [k3d](https://k3d.io/stable/) |
| **Kustomize** | Outil de composition de manifests Kubernetes, utilisé pour les bases et overlays du dépôt. | [Kustomize](https://kustomize.io/) |
| **kubectl** | Client en ligne de commande pour appliquer et interroger les ressources Kubernetes. | [kubectl](https://kubernetes.io/docs/reference/kubectl/) |
| **Traefik** | Proxy inverse et contrôleur d'Ingress qui publie les services HTTPS du cluster. | [Traefik Proxy](https://doc.traefik.io/traefik/) |
| **TLS / CA** | *Transport Layer Security* chiffre les communications ; une *Certificate Authority* signe les certificats de confiance. | [TLS dans Kubernetes](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) |
| **Vagrant** | Outil de création et provisionnement reproductible de machines virtuelles. | [Vagrant](https://developer.hashicorp.com/vagrant/docs) |
| **VirtualBox** | Hyperviseur utilisé par Vagrant pour exécuter les VM du POC. | [VirtualBox](https://www.virtualbox.org/manual/) |
| **Rocky Linux** | Distribution Linux installée sur les VM de données. | [Rocky Linux Documentation](https://docs.rockylinux.org/) |
| **Ansible** | Outil d'automatisation déclarative qui configure les VM et leurs services. | [Ansible Documentation](https://docs.ansible.com/) |
| **GNU Make** | Outil qui regroupe les commandes de build, déploiement et vérification dans le `Makefile`. | [GNU Make](https://www.gnu.org/software/make/manual/) |
| **Bash** | Interpréteur des scripts d'automatisation et de synchronisation du dépôt. | [GNU Bash](https://www.gnu.org/software/bash/manual/) |
| **Podman** | Moteur de conteneurs sans démon central, utilisé pour les services de données sur les VM. | [Podman](https://docs.podman.io/) |
| **systemd** | Gestionnaire de services Linux qui démarre et supervise les collecteurs et conteneurs. | [systemd](https://systemd.io/) |
| **Quadlet** | Format systemd de Podman permettant de décrire un conteneur comme un service. | [Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html) |
| **Docker** | Moteur de construction et distribution des images de conteneurs utilisées par le cluster local. | [Docker Docs](https://docs.docker.com/) |

## Services de données et instrumentation applicative

| Technologie / sigle | Explication synthétique | Référence officielle |
| --- | --- | --- |
| **Apache Kafka** | Plateforme distribuée de publication et consommation d'événements ; elle sert aussi de tampon pour les traces. | [Apache Kafka](https://kafka.apache.org/documentation/) |
| **KRaft** | Mode Kafka basé sur le consensus Raft, qui remplace ZooKeeper pour les métadonnées du cluster. | [Kafka KRaft](https://kafka.apache.org/documentation/#kraft) |
| **JMX** | *Java Management Extensions* : API Java exposant des MBeans de supervision JVM et Kafka. | [JMX](https://docs.oracle.com/en/java/javase/21/management/java-management-extensions-jmx-technology-tutorial.html) |
| **Jolokia** | Passerelle HTTP/JSON pour lire les MBeans JMX. | [Jolokia](https://jolokia.org/reference/html/manual/jolokia_protocol.html) |
| **MongoDB** | Base de données orientée documents, collectée localement par les trois modes de collecte. | [MongoDB Manual](https://www.mongodb.com/docs/manual/) |
| **PostgreSQL** | Base de données relationnelle, collectée par le receiver PostgreSQL sur la VM OpenTelemetry. | [PostgreSQL Documentation](https://www.postgresql.org/docs/) |
| **Java / JVM** | Java est le langage et la JVM son environnement d'exécution ; les deux portent l'instrumentation automatique. | [Java Documentation](https://docs.oracle.com/en/java/javase/21/) |
| **Maven** | Outil de build et de gestion des dépendances Java. | [Maven](https://maven.apache.org/guides/) |
| **Spring Boot** | Framework Java qui héberge les services de démonstration. | [Spring Boot](https://docs.spring.io/spring-boot/documentation.html) |
| **Actuator** | Module Spring Boot qui expose des informations de santé et métriques applicatives. | [Spring Boot Actuator](https://docs.spring.io/spring-boot/reference/actuator/) |
| **Micrometer** | Façade de métriques Java ; le registre OTLP transmet les métriques applicatives au Collector. | [Micrometer](https://docs.micrometer.io/micrometer/reference/) |
| **Logback** | Bibliothèque de journalisation Java qui produit les événements applicatifs sur stdout. | [Logback](https://logback.qos.ch/documentation.html) |
| **API key** | Jeton d'authentification Elasticsearch limité à des privilèges précis, utilisé par les collecteurs et Beats. | [API keys Elasticsearch](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/api-keys) |

## À ne pas confondre

- **Fleet Server** distribue les policies ; il ne sert normalement pas de
  relais pour les données d'un Elastic Agent vers Elasticsearch.
- **Elastic Agent**, **Filebeat**, **Metricbeat** et **EDOT** sont des moyens de
  collecte différents. Ils ne doivent pas lire la même source sur une même VM.
- **OTel** est le standard ; **EDOT** est la distribution Elastic d'un
  Collector qui met ce standard en œuvre.
- **APM** est un usage de l'observabilité applicative ; **OTLP** est un
  protocole qui peut transporter ses traces, métriques et logs.
