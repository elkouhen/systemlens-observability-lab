SHELL := /bin/bash
.DEFAULT_GOAL := help

KUBECTL ?= kubectl
VAGRANT ?= vagrant
K3D_CLUSTER ?= elastic
K8S_NAMESPACE ?= elastic-stack
APP_NAMESPACE ?= supermarket-demo
ELASTICSEARCH_URL ?= https://elasticsearch.poc.test:443
KIBANA_URL ?= https://kibana.poc.test
KIBANA_HOST ?= kibana.poc.test
KIBANA_CURL_RESOLVE ?= kibana.poc.test:443:127.0.0.1
ELASTICSEARCH_CURL_RESOLVE ?= elasticsearch.poc.test:443:127.0.0.1
OTEL_GATEWAY_API_KEY_SECRET ?= otel-collector-elasticsearch-api-key
# Certificat racine Zscaler (ou proxy TLS d'entreprise équivalent) au format
# PEM. Laisser vide sur une machine sans interception TLS : voir certs/README.md.
ZSCALER_CA_CERT ?=
K3D_CA_DEST ?= /usr/local/share/ca-certificates/zscaler-root-ca.crt

.PHONY: help credentials-show cluster-info platform-status kubernetes-status vm-status apps-build images-import kubernetes-validate \
	elk-deploy kibana-fleet-config-deploy apps-deploy apm-token-sync otel-gateway-api-key-sync otel-gateway-deploy apm-deploy platform-deploy fleet-sync vm-provision \
	deploy architecture-deploy \
	otel-infrastructure-deploy elasticsearch-ready \
	dashboard-deploy apm-report-api-key-create \
	elastic-password-show kibana-password-show apm-token-show elasticsearch-api-key-create \
	beats-api-key-create order-service-logs-follow inventory-service-logs-follow k3d-ca-import

help: ## Afficher les tâches disponibles
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <cible>\n\n"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

credentials-show: ## Indiquer comment charger les identifiants dans le shell courant
	@printf 'source ./platform/elk/scripts/load-credentials.sh\n'

cluster-info: ## Afficher les URL et identifiants de l'environnement ELK local
	@es_password="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
	api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret $(OTEL_GATEWAY_API_KEY_SECRET) -o jsonpath='{.data.api-key}' | base64 --decode )"; \
	printf 'KIBANA_URL=%s\nELASTICSEARCH_URL=%s\nFLEET_URL=%s\nUSER=elastic\nPASSWORD=%s\nELASTIC_API_KEY_BASE64=%s\n' \
		'$(KIBANA_URL)' '$(ELASTICSEARCH_URL)' 'https://fleet.poc.test' "$$es_password" "$$api_key"

platform-status: kubernetes-status vm-status ## Vérifier Kubernetes et les VM

kubernetes-status: ## Afficher l’état Elastic, APM Server et applications
	@$(KUBECTL) -n $(K8S_NAMESPACE) get elasticsearch,kibana,apmserver,agent
	@$(KUBECTL) -n $(APP_NAMESPACE) get deployment,pods

vm-status: ## Vérifier les conteneurs MongoDB, Kafka et PostgreSQL des VM
	@./scripts/cluster-status.sh

apps-build: ## Construire les images applicatives OpenTelemetry (version 1.0.4 ; option ZSCALER_CA_CERT)
	@zscaler_ca_b64=""; \
	if [ -n "$(ZSCALER_CA_CERT)" ]; then \
	  test -f "$(ZSCALER_CA_CERT)" || { echo "Certificat Zscaler introuvable : $(ZSCALER_CA_CERT)" >&2; exit 1; }; \
	  zscaler_ca_b64="$$(base64 < "$(ZSCALER_CA_CERT)" | tr -d '\n')"; \
	fi; \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --target order-service -t order-service:1.0.4 apps/supermarket-demo && \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --target inventory-service -t inventory-service:1.0.4 apps/supermarket-demo

images-import: ## Importer les images dans le cluster k3d
	@k3d image import -c $(K3D_CLUSTER) order-service:1.0.4 inventory-service:1.0.4

k3d-ca-import: ## Faire confiance au certificat Zscaler dans les nœuds k3d (requiert ZSCALER_CA_CERT, puis redémarrer le cluster)
	@test -n "$(ZSCALER_CA_CERT)" || { echo "Définir ZSCALER_CA_CERT=chemin/vers/cert.crt" >&2; exit 1; }
	@test -f "$(ZSCALER_CA_CERT)" || { echo "Certificat Zscaler introuvable : $(ZSCALER_CA_CERT)" >&2; exit 1; }
	@nodes="$$(docker ps --filter "name=k3d-$(K3D_CLUSTER)-" --format '{{.Names}}')"; \
	test -n "$$nodes" || { echo "Aucun nœud k3d trouvé pour le cluster $(K3D_CLUSTER)" >&2; exit 1; }; \
	for node in $$nodes; do \
	  echo "→ $$node"; \
	  docker cp "$(ZSCALER_CA_CERT)" "$$node:$(K3D_CA_DEST)"; \
	  docker exec "$$node" update-ca-certificates; \
	done
	@echo "Redémarrer le cluster pour appliquer le nouveau magasin de confiance : k3d cluster stop $(K3D_CLUSTER) && k3d cluster start $(K3D_CLUSTER)"

elasticsearch-ready: ## Attendre qu'ECK rende Elasticsearch joignable
	@$(KUBECTL) -n $(K8S_NAMESPACE) wait \
		--for=condition=ElasticsearchIsReachable=True \
		elasticsearch/elasticsearch --timeout=300s

otel-gateway-api-key-sync: elasticsearch-ready ## Créer la clé writer du gateway si son secret est absent
	@if $(KUBECTL) -n $(K8S_NAMESPACE) get secret $(OTEL_GATEWAY_API_KEY_SECRET) >/dev/null 2>&1; then exit 0; fi; \
	es_password="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
	api_key="$$(curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' -u "elastic:$$es_password" -H 'Content-Type: application/json' -X POST '$(ELASTICSEARCH_URL)/_security/api_key' --data '{"name":"otel-collector-gateway","role_descriptors":{"otel_collector_gateway_writer":{"cluster":["monitor"],"indices":[{"names":["logs-*-*","metrics-*-*","traces-*-*"],"privileges":["auto_configure","create_doc"]}]}}}' | jq -er '.id + ":" + .api_key')"; \
	api_key_base64="$$(printf '%s' "$$api_key" | base64 | tr -d '\n')"; \
	$(KUBECTL) -n $(K8S_NAMESPACE) create secret generic $(OTEL_GATEWAY_API_KEY_SECRET) --from-literal="api-key=$$api_key_base64"

otel-gateway-deploy: otel-gateway-api-key-sync ## Déployer les collectors OTEL Kafka et Elasticsearch
	@$(KUBECTL) apply -f platform/kubernetes/base/observability/otel-collector-gateway.yaml
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-collector-gateway
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-collector-traces-backend
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-collector-gateway --timeout=180s
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-collector-traces-backend --timeout=180s

otel-infrastructure-deploy: ## Déployer les collecteurs EDOT Kubernetes et hôte
	@$(KUBECTL) apply -k platform/kubernetes/overlays/local
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status daemonset/otel-collector-daemon --timeout=180s
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-collector-cluster --timeout=180s

kibana-fleet-config-deploy: ## Appliquer la configuration Kibana/Fleet déclarative
	@$(KUBECTL) apply -k platform/kubernetes/overlays/local

elk-deploy: ## Déployer la plateforme d'observabilité hors gateway OpenTelemetry
	@$(KUBECTL) apply -k platform/kubernetes/overlays/local

apm-token-sync: ## Copier dans le namespace applicatif les secrets APM requis par order-service
	@set -euo pipefail; \
	token="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret apm-server-apm-token -o jsonpath='{.data.secret-token}' | base64 --decode)"; \
	ca_file="$$(mktemp)"; \
	trap 'rm -f "$$ca_file"' EXIT; \
	$(KUBECTL) -n $(K8S_NAMESPACE) get secret apm-server-apm-http-certs-public -o jsonpath='{.data.ca\\.crt}' | base64 --decode > "$$ca_file"; \
	$(KUBECTL) -n $(APP_NAMESPACE) create secret generic order-service-apm-token --from-literal=secret-token="$$token" --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	$(KUBECTL) -n $(APP_NAMESPACE) create secret generic order-service-apm-server-ca --from-file=ca.crt="$$ca_file" --dry-run=client -o yaml | $(KUBECTL) apply -f -

apps-deploy: apm-token-sync ## Déployer uniquement l'application de démonstration
	@$(KUBECTL) apply -k apps/supermarket-demo/kubernetes
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/order-service --timeout=180s
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/inventory-service --timeout=180s

apm-deploy: ## Alias historique : déployer ELK, le gateway puis l'application
	@$(MAKE) elk-deploy
	@$(MAKE) otel-gateway-deploy
	@$(MAKE) apps-deploy

platform-deploy: apps-build images-import ## Construire, importer et déployer l'ensemble séquencé
	@$(MAKE) apm-deploy

deploy: ## Déployer l'architecture complète : Kubernetes, VM et applications
	@set -euo pipefail; \
	$(MAKE) elk-deploy; \
	$(MAKE) otel-gateway-api-key-sync; \
	source ./platform/elk/scripts/load-credentials.sh; \
	$(MAKE) fleet-sync; \
	$(VAGRANT) up; \
	$(MAKE) otel-gateway-deploy; \
	$(MAKE) apps-build; \
	$(MAKE) images-import; \
	$(MAKE) apps-deploy

architecture-deploy: deploy ## Alias explicite de deploy

kubernetes-validate: ## Générer les manifests Kustomize sans les appliquer
	@$(KUBECTL) kustomize platform/kubernetes/overlays/local >/dev/null
	@$(KUBECTL) kustomize apps/supermarket-demo/kubernetes >/dev/null

fleet-sync: ## Synchroniser les pipelines Kafka (policies Fleet déclarées dans Kubernetes)
	@KIBANA_URL='$(KIBANA_URL)' KIBANA_HOST='$(KIBANA_HOST)' ./platform/elk/scripts/sync-fleet-policies.sh

dashboard-deploy: ## Importer ou mettre à jour le dashboard MongoDB (requiert KIBANA_PASSWORD)
	@KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' ./platform/elk/scripts/deploy-kibana-dashboard.sh

apm-report-api-key-create: ## Créer une clé de lecture pour les rapports APM SystemLens
	@test -n "$$ELASTICSEARCH_PASSWORD" || { echo "Définir ELASTICSEARCH_PASSWORD (source platform/elk/scripts/load-credentials.sh)" >&2; exit 1; }
	@curl --fail --silent --show-error --insecure \
		--resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
		-u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-H 'Content-Type: application/json' \
		-X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
		--data "{\"name\":\"systemlens-apm-report-$$(date +%Y%m%d%H%M%S)\",\"role_descriptors\":{\"systemlens_apm_report_reader\":{\"cluster\":[\"monitor\"],\"indices\":[{\"names\":[\"traces-*\",\"metrics-*\"],\"privileges\":[\"read\",\"view_index_metadata\"]}]}}}" \
		| jq -r '.id + ":" + .api_key'

vm-provision: ## Provisionner les VM (requiert ELASTICSEARCH_API_KEY)
	@test -n "$$ELASTICSEARCH_API_KEY" || { echo "Définir ELASTICSEARCH_API_KEY" >&2; exit 1; }
	@$(VAGRANT) provision

elastic-password-show: ## Afficher le mot de passe du compte elastic ECK
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user \
		-o go-template='{{.data.elastic | base64decode}}{{"\\n"}}'

kibana-password-show: elastic-password-show ## Afficher le mot de passe Kibana (compte elastic)

apm-token-show: ## Afficher le token d’ingestion APM
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret apm-server-apm-token \
		-o go-template='{{index .data "secret-token" | base64decode}}{{"\\n"}}'

elasticsearch-api-key-create: ## Créer une clé API Base64 pour les rapports APM SystemLens
	@test -n "$$ELASTICSEARCH_PASSWORD" || { echo "Définir ELASTICSEARCH_PASSWORD (make elastic-password-show)" >&2; exit 1; }
	@api_key="$$(curl --fail --silent --show-error --insecure \
		-u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-H 'Content-Type: application/json' \
		-X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
		--data '{"name":"vm-beats-$$(date +%Y%m%d%H%M%S)","role_descriptors":{"vm_beats_writer":{"cluster":["monitor","read_ilm","manage_ilm","manage_index_templates"],"indices":[{"names":["logs-*","metrics-*","filebeat-*","metricbeat-*"],"privileges":["auto_configure","create_doc","read","view_index_metadata"]},{"names":["traces-*"],"privileges":["read","view_index_metadata"]}]}}}' \
		| jq -er '.id + ":" + .api_key')"; \
	printf '%s' "$$api_key" | base64 | tr -d '\n'; echo

beats-api-key-create: ## Créer une clé API brute id:api_key pour Filebeat/Metricbeat
	@test -n "$$ELASTICSEARCH_PASSWORD" || { echo "Définir ELASTICSEARCH_PASSWORD (make elastic-password-show)" >&2; exit 1; }
	@curl --fail --silent --show-error --insecure \
		-u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-H 'Content-Type: application/json' \
		-X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
		--data '{"name":"vm-beats-$$(date +%Y%m%d%H%M%S)","role_descriptors":{"vm_beats_writer":{"cluster":["monitor","read_ilm","manage_ilm","manage_index_templates"],"indices":[{"names":["logs-*","metrics-*","filebeat-*","metricbeat-*"],"privileges":["auto_configure","create_doc","read","view_index_metadata"]},{"names":["traces-*"],"privileges":["read","view_index_metadata"]}]}}}' \
		| jq -r '.id + ":" + .api_key'

order-service-logs-follow: ## Suivre les logs de order-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/order-service

inventory-service-logs-follow: ## Suivre les logs de inventory-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/inventory-service
