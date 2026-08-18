SHELL := /bin/bash
.DEFAULT_GOAL := help

KUBECTL ?= kubectl
VAGRANT ?= vagrant
K3D_CLUSTER ?= elastic
K8S_NAMESPACE ?= elastic-stack
APP_NAMESPACE ?= apm-demo
ELASTICSEARCH_URL ?= https://elasticsearch.poc.test:443
KIBANA_URL ?= https://kibana.poc.test
KIBANA_HOST ?= kibana.poc.test

.PHONY: help credentials status k8s-status vm-status build import-images deploy-apm deploy \
	copy-apm-ca sync-fleet vm-provision elastic-password kibana-password apm-token \
	elasticsearch-api-key beats-api-key app-logs worker-logs

help: ## Afficher les tâches disponibles
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <cible>\n\n"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

credentials: ## Indiquer comment charger les identifiants dans le shell courant
	@printf 'source ./scripts/load-credentials.sh\n'

status: k8s-status vm-status ## Vérifier Kubernetes et les VM

k8s-status: ## Afficher l’état Elastic, APM Server et applications
	@$(KUBECTL) -n $(K8S_NAMESPACE) get elasticsearch,kibana,apmserver,agent
	@$(KUBECTL) -n $(APP_NAMESPACE) get deployment,pods

vm-status: ## Vérifier les conteneurs MongoDB et Kafka des VM
	@./scripts/cluster-status.sh

build: ## Construire les images applicatives OpenTelemetry (version 1.0.2)
	@docker build --target frontend -t apm-demo:1.0.2 apm-demo
	@docker build --target worker -t apm-demo-worker:1.0.2 apm-demo

import-images: ## Importer les images dans le cluster k3d
	@k3d image import -c $(K3D_CLUSTER) apm-demo:1.0.2 apm-demo-worker:1.0.2

copy-apm-ca: ## Copier le CA public APM Server vers le namespace applicatif
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret apm-server-apm-http-certs-public \
		-o jsonpath='{.data.ca\.crt}' | base64 --decode | \
		$(KUBECTL) -n $(APP_NAMESPACE) create secret generic apm-server-apm-http-certs-public \
		--from-file=ca.crt=/dev/stdin --dry-run=client -o yaml | $(KUBECTL) apply -f -

deploy-apm: copy-apm-ca ## Déployer APM Server et les applications OpenTelemetry
	@$(KUBECTL) apply -f kubernetes/apm-server.yaml
	@$(KUBECTL) apply -f kubernetes/apm-demo.yaml
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/apm-demo --timeout=180s
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/apm-demo-worker --timeout=180s

deploy: build import-images deploy-apm ## Construire, importer et déployer les applications

sync-fleet: ## Synchroniser les intégrations Fleet MongoDB/Kafka (requiert KIBANA_PASSWORD)
	@KIBANA_URL='$(KIBANA_URL)' KIBANA_HOST='$(KIBANA_HOST)' ./scripts/sync-fleet-policies.sh

vm-provision: ## Provisionner Filebeat/Metricbeat (requiert ELASTICSEARCH_API_KEY)
	@test -n "$$ELASTICSEARCH_API_KEY" || { echo "Définir ELASTICSEARCH_API_KEY" >&2; exit 1; }
	@$(VAGRANT) provision

elastic-password: ## Afficher le mot de passe du compte elastic ECK
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user \
		-o go-template='{{.data.elastic | base64decode}}{{"\\n"}}'

kibana-password: elastic-password ## Afficher le mot de passe Kibana (compte elastic)

apm-token: ## Afficher le token d’ingestion APM
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret apm-server-apm-token \
		-o go-template='{{index .data "secret-token" | base64decode}}{{"\\n"}}'

elasticsearch-api-key: ## Créer et afficher la clé API Elasticsearch pour Filebeat/Metricbeat
	@test -n "$$ELASTICSEARCH_PASSWORD" || { echo "Définir ELASTICSEARCH_PASSWORD (make elastic-password)" >&2; exit 1; }
	@curl --fail --silent --show-error --insecure \
		-u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-H 'Content-Type: application/json' \
		-X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
		--data '{"name":"vm-beats-$$(date +%Y%m%d%H%M%S)","role_descriptors":{"vm_beats_writer":{"cluster":["monitor"],"indices":[{"names":["logs-*","metrics-*"],"privileges":["auto_configure","create_doc"]}]}}}' \
		| jq -r '.id + ":" + .api_key'

beats-api-key: elasticsearch-api-key ## Alias de elasticsearch-api-key

app-logs: ## Suivre les logs de apm-demo
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/apm-demo

worker-logs: ## Suivre les logs de apm-demo-worker
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/apm-demo-worker
