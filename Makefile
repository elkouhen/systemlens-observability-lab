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
ELASTICSEARCH_CURL_RESOLVE ?= elasticsearch.poc.test:443:127.0.0.1
OTEL_GATEWAY_API_KEY_SECRET ?= otel-collector-elasticsearch-api-key

.PHONY: help credentials-show platform-status kubernetes-status vm-status apps-build images-import \
	otel-gateway-api-key-sync otel-gateway-deploy apm-deploy platform-deploy fleet-sync vm-provision \
	elastic-password-show kibana-password-show apm-token-show elasticsearch-api-key-create \
	beats-api-key-create apm-demo-logs-follow apm-demo-worker-logs-follow

help: ## Afficher les tâches disponibles
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <cible>\n\n"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

credentials-show: ## Indiquer comment charger les identifiants dans le shell courant
	@printf 'source ./scripts/load-credentials.sh\n'

platform-status: kubernetes-status vm-status ## Vérifier Kubernetes et les VM

kubernetes-status: ## Afficher l’état Elastic, APM Server et applications
	@$(KUBECTL) -n $(K8S_NAMESPACE) get elasticsearch,kibana,apmserver,agent
	@$(KUBECTL) -n $(APP_NAMESPACE) get deployment,pods

vm-status: ## Vérifier les conteneurs MongoDB et Kafka des VM
	@./scripts/cluster-status.sh

apps-build: ## Construire les images applicatives OpenTelemetry (version 1.0.4)
	@docker build --target frontend -t apm-demo:1.0.4 apm-demo
	@docker build --target worker -t apm-demo-worker:1.0.4 apm-demo

images-import: ## Importer les images dans le cluster k3d
	@k3d image import -c $(K3D_CLUSTER) apm-demo:1.0.4 apm-demo-worker:1.0.4

otel-gateway-api-key-sync: ## Créer la clé writer du gateway si son secret est absent
	@if $(KUBECTL) -n $(K8S_NAMESPACE) get secret $(OTEL_GATEWAY_API_KEY_SECRET) >/dev/null 2>&1; then exit 0; fi; \
	es_password="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
	api_key="$$(curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' -u "elastic:$$es_password" -H 'Content-Type: application/json' -X POST '$(ELASTICSEARCH_URL)/_security/api_key' --data '{"name":"otel-collector-gateway","role_descriptors":{"otel_collector_gateway_writer":{"cluster":["monitor"],"indices":[{"names":["logs-*-*","metrics-*-*","traces-*-*"],"privileges":["auto_configure","create_doc"]}]}}}' | jq -er '.id + ":" + .api_key')"; \
	api_key_base64="$$(printf '%s' "$$api_key" | base64 | tr -d '\\n')"; \
	$(KUBECTL) -n $(K8S_NAMESPACE) create secret generic $(OTEL_GATEWAY_API_KEY_SECRET) --from-literal="api-key=$$api_key_base64"

otel-gateway-deploy: otel-gateway-api-key-sync ## Déployer le gateway OpenTelemetry interne
	@$(KUBECTL) apply -f kubernetes/otel-collector-gateway.yaml
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-collector-gateway
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-collector-gateway --timeout=180s

apm-deploy: otel-gateway-deploy ## Déployer les composants APM et les applications OpenTelemetry
	@$(KUBECTL) apply -f kubernetes/apm-server.yaml
	@$(KUBECTL) apply -f kubernetes/apm-demo.yaml
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/apm-demo --timeout=180s
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/apm-demo-worker --timeout=180s

platform-deploy: apps-build images-import apm-deploy ## Construire, importer et déployer les applications

fleet-sync: ## Synchroniser les intégrations Fleet MongoDB/Kafka (requiert KIBANA_PASSWORD)
	@KIBANA_URL='$(KIBANA_URL)' KIBANA_HOST='$(KIBANA_HOST)' ./scripts/sync-fleet-policies.sh

vm-provision: ## Provisionner Filebeat/Metricbeat (requiert ELASTICSEARCH_API_KEY)
	@test -n "$$ELASTICSEARCH_API_KEY" || { echo "Définir ELASTICSEARCH_API_KEY" >&2; exit 1; }
	@$(VAGRANT) provision

elastic-password-show: ## Afficher le mot de passe du compte elastic ECK
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user \
		-o go-template='{{.data.elastic | base64decode}}{{"\\n"}}'

kibana-password-show: elastic-password-show ## Afficher le mot de passe Kibana (compte elastic)

apm-token-show: ## Afficher le token d’ingestion APM
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret apm-server-apm-token \
		-o go-template='{{index .data "secret-token" | base64decode}}{{"\\n"}}'

elasticsearch-api-key-create: ## Créer et afficher la clé API Elasticsearch pour Filebeat/Metricbeat
	@test -n "$$ELASTICSEARCH_PASSWORD" || { echo "Définir ELASTICSEARCH_PASSWORD (make elastic-password-show)" >&2; exit 1; }
	@curl --fail --silent --show-error --insecure \
		-u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-H 'Content-Type: application/json' \
		-X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
		--data '{"name":"vm-beats-$$(date +%Y%m%d%H%M%S)","role_descriptors":{"vm_beats_writer":{"cluster":["monitor"],"indices":[{"names":["logs-*","metrics-*"],"privileges":["auto_configure","create_doc"]}]}}}' \
		| jq -r '.id + ":" + .api_key'

beats-api-key-create: elasticsearch-api-key-create ## Alias de elasticsearch-api-key-create

apm-demo-logs-follow: ## Suivre les logs de apm-demo
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/apm-demo

apm-demo-worker-logs-follow: ## Suivre les logs de apm-demo-worker
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/apm-demo-worker
