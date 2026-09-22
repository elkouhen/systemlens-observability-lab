SHELL := /bin/bash
.DEFAULT_GOAL := help

KUBECTL ?= kubectl
VAGRANT ?= vagrant
K3D_CLUSTER ?= elastic
DEPLOYMENT_PROFILE := minimal
ARCH_NAME := Hybride Fleet
ARCH_ROOT := .
K8S_NAMESPACE ?= elastic-stack
APP_NAMESPACE ?= h0tl-supermarche-app
APP_IMAGE_TAG ?= 1.1.3
OTEL_JAVA_AGENT_VERSION ?= 2.28.1
ORDER_PRODUCT_ID ?= PASTA-500G
ORDER_QUANTITY ?= 1
ELASTIC_STACK_VERSION ?= 9.4.3
SKIP_ELK_VM_PROVISION ?= 0
SKIP_KUBERNETES_APPLY ?= 0
ELASTICSEARCH_URL ?= http://elasticsearch.observability.test:9200
KIBANA_URL ?= http://kibana.observability.test:5601
KIBANA_HOST ?= kibana.observability.test
KIBANA_CURL_RESOLVE ?= kibana.observability.test:5601:192.168.33.30
ELASTICSEARCH_CURL_RESOLVE ?= elasticsearch.observability.test:9200:192.168.33.30
# Certificat racine Zscaler (ou proxy TLS d'entreprise équivalent) au format
# PEM. Laisser vide sur une machine sans interception TLS : voir certs/README.md.
ZSCALER_CA_CERT ?=
K3D_CA_DEST ?= /usr/local/share/ca-certificates/zscaler-root-ca.crt

.PHONY: help architecture-status credentials-show cluster-info platform-status kubernetes-status apps-build apps-test images-import kubernetes-validate ansible-validate slides elastic-stack-deploy otel-elasticsearch-credentials-apply \
	elk-deploy kibana-fleet-config-deploy apm-data-view-deploy business-dashboard-deploy business-dashboard-replace apm-logstash-credentials-apply apm-logstash-deploy apps-deploy apm-token-sync fleet-sync fleet-vms-provision vm-provision \
	observability-policies-validate observability-policies-deploy ansible-deploy \
	postgresql-credentials-apply kafka-jolokia-verify mongodb-workload otel-elasticsearch-credentials-apply otel-gateway-vm-provision otel-gateway-vm-status otel-gateway-kubernetes-bascule otel-gateway-relocate otel-kafka-exporter-vm-provision otel-kafka-exporter-vm-status otel-kafka-exporter-kubernetes-bascule otel-kafka-exporter-relocate \
	otel-validation kubernetes-observability-deploy otel-gateway-kubernetes-remove \
	otel-edge-vm-provision elastic-agent-vm-provision fleet-vm-monitoring \
	vms-up deploy elastic-disk-ensure elasticsearch-ready kibana-ready apm-kibana-role-apply \
	dashboards-backup dashboards-verify kubernetes-otel-dashboards-deploy kubernetes-otel-dashboards-verify apm-report-api-key-create \
	elastic-password-show kibana-password-show apm-token-show elasticsearch-api-key-create \
	beats-api-key-create stock-view order-service-command order-service-logs-follow inventory-service-logs-follow restock-service-logs-follow k3d-ca-import public-tls-apply ci

##@ Informations et diagnostic

help: ## Afficher les tâches disponibles
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <cible>\n"} \
		/^##@/ {printf "\n%s\n", substr($$0, 5); next} \
		/^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-32s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

architecture-status: ## Afficher la configuration de l'architecture
	@printf 'ARCH_NAME=%s\nELASTIC_STACK_VERSION=%s\nARCH_ROOT=%s\n' '$(ARCH_NAME)' '$(ELASTIC_STACK_VERSION)' '$(ARCH_ROOT)'

credentials-show: ## Indiquer comment charger les identifiants dans le shell courant
	@printf 'source ./$(ARCH_ROOT)/platform/elk/scripts/load-credentials.sh\n'

cluster-info: ## Afficher les URL et identifiants de l'environnement ELK local
	@printf 'KIBANA_URL=%s\nELASTICSEARCH_URL=%s\nFLEET_URL=%s\nUSER=elastic\n' \
		'$(KIBANA_URL)' '$(ELASTICSEARCH_URL)' 'https://fleet.observability.test'

platform-status: kubernetes-status vm-status ## Vérifier Kubernetes et les VM

kubernetes-status: ## Afficher l’état Elastic et applications
	@$(KUBECTL) -n $(K8S_NAMESPACE) get service,ingressroute
	@$(KUBECTL) -n $(APP_NAMESPACE) get deployment,pods

vm-status: ## Vérifier les conteneurs MongoDB, Kafka et PostgreSQL des VM
	@DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POC_VM_NAME='poc-01' ../scripts/cluster-status.sh

##@ Construction et préparation locale

apps-build: ## Construire les images applicatives avec les agents Elastic APM et OpenTelemetry
	@zscaler_ca_b64=""; \
	if [ -n "$(ZSCALER_CA_CERT)" ]; then \
	  test -f "$(ZSCALER_CA_CERT)" || { echo "Certificat Zscaler introuvable : $(ZSCALER_CA_CERT)" >&2; exit 1; }; \
	  zscaler_ca_b64="$$(base64 < "$(ZSCALER_CA_CERT)" | tr -d '\n')"; \
	fi; \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --build-arg OTEL_JAVA_AGENT_VERSION=$(OTEL_JAVA_AGENT_VERSION) --target order-service -t order-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo && \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --build-arg OTEL_JAVA_AGENT_VERSION=$(OTEL_JAVA_AGENT_VERSION) --target inventory-service -t inventory-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo && \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --build-arg OTEL_JAVA_AGENT_VERSION=$(OTEL_JAVA_AGENT_VERSION) --target restock-service -t restock-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo

apps-test: ## Exécuter les tests unitaires et d'intégration Maven des applications
	@mvn --batch-mode verify -f ../apps/supermarket-demo/pom.xml

images-import: ## Importer les images dans le cluster k3d
	@k3d image import -c $(K3D_CLUSTER) order-service:$(APP_IMAGE_TAG) inventory-service:$(APP_IMAGE_TAG) restock-service:$(APP_IMAGE_TAG)

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

##@ Déploiement de la plateforme Elastic

public-tls-apply: ## Créer ou réparer le certificat TLS public local du POC
	@tmp_dir="$$(mktemp -d)"; trap 'rm -rf "$$tmp_dir"' EXIT; recreate=1; \
	if $(KUBECTL) -n $(K8S_NAMESPACE) get secret elastic-public-tls >/dev/null 2>&1; then \
		$(KUBECTL) -n $(K8S_NAMESPACE) get secret elastic-public-tls -o jsonpath='{.data.tls\.crt}' | base64 --decode > "$$tmp_dir/current.crt"; \
		if openssl x509 -in "$$tmp_dir/current.crt" -noout -checkend 0 >/dev/null 2>&1 && openssl x509 -in "$$tmp_dir/current.crt" -noout -text | grep -Fq 'CA:TRUE' && openssl x509 -in "$$tmp_dir/current.crt" -noout -text | grep -Fq 'DNS:*.observability.test'; then recreate=0; echo "Secret TLS public elastic-public-tls valide"; fi; \
	fi; \
	if test "$$recreate" = 1; then \
		printf '%s\n' '[req]' 'distinguished_name = req_distinguished_name' 'x509_extensions = v3_req' 'prompt = no' '' '[req_distinguished_name]' 'CN = *.observability.test' '' '[v3_req]' 'subjectAltName = DNS:*.observability.test,DNS:observability.test' 'basicConstraints = critical,CA:TRUE' 'keyUsage = critical,digitalSignature,keyEncipherment' 'extendedKeyUsage = serverAuth' > "$$tmp_dir/openssl.cnf"; \
		openssl req -x509 -nodes -newkey rsa:2048 -days 825 -keyout "$$tmp_dir/tls.key" -out "$$tmp_dir/tls.crt" -config "$$tmp_dir/openssl.cnf" >/dev/null 2>&1; \
		$(KUBECTL) -n $(K8S_NAMESPACE) create secret tls elastic-public-tls --cert="$$tmp_dir/tls.crt" --key="$$tmp_dir/tls.key" --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
		echo "Secret TLS public elastic-public-tls créé ou réparé"; \
	fi

elasticsearch-ready: ## Attendre qu'Elasticsearch Quadlet rende son endpoint joignable
	@password="$${ELASTIC_PASSWORD:-password}"; \
	test -n "$$password" || { echo 'ELASTIC_PASSWORD absent' >&2; exit 1; }; \
	for attempt in $$(seq 1 60); do curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' -u "elastic:$$password" '$(ELASTICSEARCH_URL)' >/dev/null && exit 0; sleep 2; done; \
	echo 'Elasticsearch Quadlet inaccessible après 120s' >&2; exit 1

kibana-ready: ## Attendre que Kibana soit prêt avant l'import de ses objets
	@for attempt in $$(seq 1 60); do \
		status="$$(curl --silent --show-error --insecure \
			--resolve '$(KIBANA_CURL_RESOLVE)' -o /dev/null -w '%{http_code}' \
			'$(KIBANA_URL)/login' || true)"; \
		if test "$$status" = 200 || test "$$status" = 302 || test "$$status" = 401; then \
			echo "Ingress Kibana accessible"; exit 0; \
		fi; \
		sleep 5; \
	done; \
	echo "Ingress Kibana inaccessible après 300s" >&2; exit 1

kibana-fleet-config-deploy: ## Appliquer la configuration Kibana/Fleet déclarative
	@if test '$(SKIP_KUBERNETES_APPLY)' != 1; then $(KUBECTL) apply -k $(ARCH_ROOT)/platform/kubernetes/overlays/local; fi
	@$(MAKE) kibana-ready
	@set -euo pipefail; kibana_password="$${KIBANA_PASSWORD:-password}"; \
	 postgresql_password="$${POSTGRESQL_PASSWORD:-password}"; \
	 test -n "$$kibana_password" && test -n "$$postgresql_password" || { echo 'Identifiants Kibana/PostgreSQL absents' >&2; exit 1; }; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" POSTGRESQL_PASSWORD="$$postgresql_password" ./$(ARCH_ROOT)/platform/elk/scripts/bootstrap-fleet-policies.sh; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ./$(ARCH_ROOT)/platform/elk/scripts/reconcile-kubernetes-otel-dashboards.sh; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ELASTICSEARCH_PASSWORD="$$kibana_password" ./$(ARCH_ROOT)/platform/elk/scripts/reconcile-otel-dashboards.sh

kubernetes-otel-dashboards-deploy: ## Réconcilier les dashboards Kubernetes OTel du package Fleet
	@kibana_password="$${KIBANA_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$kibana_password" || { echo 'KIBANA_PASSWORD ou le secret ECK est requis' >&2; exit 1; }; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ./$(ARCH_ROOT)/platform/elk/scripts/reconcile-kubernetes-otel-dashboards.sh

otel-dashboards-reconcile: ## Corriger les filtres des dashboards OTel System, Kafka, MongoDB et PostgreSQL
	@kibana_password="$${KIBANA_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$kibana_password" || { echo 'KIBANA_PASSWORD ou le secret ECK est requis' >&2; exit 1; }; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ./$(ARCH_ROOT)/platform/elk/scripts/reconcile-otel-dashboard-controls.sh; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ELASTICSEARCH_PASSWORD="$$kibana_password" ./$(ARCH_ROOT)/platform/elk/scripts/reconcile-otel-dashboard-queries.sh; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ./$(ARCH_ROOT)/platform/elk/scripts/reconcile-otel-dashboard-labels.sh

elastic-stack-deploy: ## Déployer Elasticsearch, Kibana et Fleet Server sur elk-01 via Quadlet
	@password="$${ELASTIC_PASSWORD:-password}"; \
	api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	test -n "$$password" || { echo 'ELASTIC_PASSWORD absent : définir le secret hors Git avant le déplacement.' >&2; exit 1; }; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' ELASTIC_PASSWORD="$$password" OTEL_ELASTICSEARCH_API_KEY="$$api_key" $(VAGRANT) up elk-01 --no-provision
	@$(MAKE) elastic-disk-ensure
	@if test '$(SKIP_ELK_VM_PROVISION)' = 1; then \
		echo 'Provisionnement Ansible complet de elk-01 déjà effectué par deploy'; \
	else \
		password="$${ELASTIC_PASSWORD:-password}"; api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
		DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' ELASTIC_PASSWORD="$$password" OTEL_ELASTICSEARCH_API_KEY="$$api_key" $(VAGRANT) provision elk-01 --provision-with ansible; \
	fi

elastic-disk-ensure: ## Dimensionner idempotemment le disque système d'elk-01
	@VAGRANT='$(VAGRANT)' ./scripts/ensure-vm-disk.sh elk-01 30720

postgresql-credentials-apply: ## Créer ou mettre à jour le secret PostgreSQL Fleet (requiert POSTGRESQL_PASSWORD)
	@$(KUBECTL) apply -f ../kubernetes/apps/supermarket-demo/base/namespace.yaml
	@postgresql_password="$${POSTGRESQL_PASSWORD:-password}"; \
	test -n "$$postgresql_password" || { echo "Définir POSTGRESQL_PASSWORD hors Git (requis au premier déploiement)" >&2; exit 1; }; \
	$(KUBECTL) -n $(K8S_NAMESPACE) create secret generic postgresql-fleet-credentials \
		--from-literal=password="$$postgresql_password" --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	$(KUBECTL) -n $(APP_NAMESPACE) create secret generic postgresql-credentials \
		--from-literal=password="$$postgresql_password" --dry-run=client -o yaml | $(KUBECTL) apply -f -

otel-elasticsearch-credentials-apply: ## Créer ou réconcilier la clé API Elasticsearch du Collector OTel
	@current_api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials \
		-o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	if test -n "$$current_api_key" && curl --fail --silent --show-error --insecure \
		--resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
		-H "Authorization: ApiKey $$current_api_key" \
		'$(ELASTICSEARCH_URL)/_security/_authenticate' >/dev/null; then \
		password="$${ELASTIC_PASSWORD:-password}"; \
		key_id="$$(printf '%s' "$$current_api_key" | base64 --decode 2>/dev/null | cut -d: -f1)"; \
		key_has_metadata_privilege="$$(curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
			-u "elastic:$$password" '$(ELASTICSEARCH_URL)/_security/api_key?id='"$$key_id" \
			| jq -r '([.api_keys[0].role_descriptors[]?.indices[]?.privileges[]?] | index("view_index_metadata")) != null')"; \
		if test "$$key_has_metadata_privilege" != true; then \
			curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
				-u "elastic:$$password" -H 'Content-Type: application/json' \
				-X PUT "$(ELASTICSEARCH_URL)/_security/api_key/$$key_id" \
				--data '{"role_descriptors":{"otel_writer":{"cluster":["monitor"],"indices":[{"names":["traces-*","metrics-*","logs-*"],"privileges":["auto_configure","create_doc","view_index_metadata"]}]}}}' \
				| jq -e '.updated == true' >/dev/null; \
			echo "Clé API otel-elasticsearch-credentials mise à jour"; \
		else \
			echo "Clé API otel-elasticsearch-credentials valide"; \
		fi; \
	else \
		password="$${ELASTIC_PASSWORD:-password}"; \
		api_key="$$(curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
			-u "elastic:$$password" -H 'Content-Type: application/json' -X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
			--data '{"name":"otel-collector-writer","role_descriptors":{"otel_writer":{"cluster":["monitor"],"indices":[{"names":["traces-*","metrics-*","logs-*"],"privileges":["auto_configure","create_doc","view_index_metadata"]}]}}}' \
			| jq -er '.encoded')"; \
		$(KUBECTL) -n $(K8S_NAMESPACE) create secret generic otel-elasticsearch-credentials \
			--from-literal=api-key="$$api_key" --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
		echo "Clé API otel-elasticsearch-credentials réconciliée"; \
	fi

elk-deploy: elastic-stack-deploy ## Déployer la plateforme d'observabilité Elastic sur elk-01
	@$(KUBECTL) -n $(K8S_NAMESPACE) delete job otel-telemetry-topics --ignore-not-found
	@$(KUBECTL) apply -k $(ARCH_ROOT)/platform/kubernetes/overlays/local
	@password="$${ELASTIC_PASSWORD:-password}"; \
	test -n "$$password" || { echo 'ELASTIC_PASSWORD absent' >&2; exit 1; }; \
	$(KUBECTL) -n $(K8S_NAMESPACE) create secret generic elasticsearch-es-elastic-user --from-literal=elastic="$$password" --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(MAKE) public-tls-apply
	@$(MAKE) postgresql-credentials-apply
	@$(MAKE) elasticsearch-ready
	@$(MAKE) otel-elasticsearch-credentials-apply
	@$(MAKE) otel-edge-vm-provision
	@$(KUBECTL) -n $(K8S_NAMESPACE) wait --for=condition=complete job/otel-telemetry-topics --timeout=180s
	@$(MAKE) otel-gateway-kubernetes-remove
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-kubernetes-cluster daemonset/otel-kubernetes
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-kubernetes-cluster --timeout=180s
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status daemonset/otel-kubernetes --timeout=180s
	@$(MAKE) kibana-ready
	@SKIP_KUBERNETES_APPLY=1 $(MAKE) kibana-fleet-config-deploy
	@$(MAKE) ilm-deploy
	@$(MAKE) apm-data-view-deploy
	@$(MAKE) business-dashboard-deploy
	@$(MAKE) observability-policies-deploy

apm-data-view-deploy: ## Importer le data view APM versionné
	@kibana_password="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/deploy-kibana-dashboard.sh $(ARCH_ROOT)/platform/elk/dashboards/apm-data-view.ndjson

business-dashboard-deploy: ## Importer le dashboard des métriques métier
	@kibana_password="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/replace-kibana-dashboard.sh $(ARCH_ROOT)/platform/elk/dashboards/business-metrics-dashboard.json

business-dashboard-replace: business-dashboard-deploy ## Supprimer puis réimporter le dashboard métier

observability-policies-validate: ## Vérifier le manifeste versionné des SLO et alertes
	@jq -e '(.slos | type == "array" and length > 0) and (.rules | type == "array" and length > 0) and ([.slos[].id, .rules[].id] | all(type == "string" and length > 0)) and ([.slos[] | select(.indicator.type == "sli.metric.timeslice") | ((.budgetingMethod == "timeslices") and (.objective.target > 0 and .objective.target < 1) and (.objective.timesliceTarget > 0 and .objective.timesliceTarget < 1) and (.objective.timesliceWindow | type == "string" and length > 0) and (.indicator.params.metric.metrics | type == "array" and length > 0))] | all) and ([.rules[].body | select(.rule_type_id == ".es-query" and .params.searchType == "esQuery") | .params.esQuery | fromjson] | all(type == "object")) and ([.rules[].body | select(.rule_type_id == ".es-query" and .params.searchType == "esqlQuery") | .params.esqlQuery.esql] | all(type == "string" and length > 0))' $(ARCH_ROOT)/platform/elk/alerts/observability-policies.json >/dev/null
	@bash -n $(ARCH_ROOT)/platform/elk/scripts/sync-observability-policies.sh

observability-policies-deploy: observability-policies-validate ## Réconcilier les SLO et alertes de l’architecture dans Kibana
	@kibana_password="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/sync-observability-policies.sh $(ARCH_ROOT)/platform/elk/alerts/observability-policies.json

apm-kibana-role-apply: ## Accorder au compte APM les droits Kibana APM/Fleet en lecture
	@elasticsearch_password="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode )"; \
	test -n "$$elasticsearch_password" || { echo "Impossible de lire le mot de passe Elasticsearch" >&2; exit 1; }; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' \
		ELASTICSEARCH_PASSWORD="$$elasticsearch_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/apply-apm-kibana-role.sh

apm-logstash-credentials-apply: ## Compatibilité historique (aucun Logstash)
	@echo "Aucun secret Logstash n'est utilisé par l'architecture active (OTLP/Fleet)."

apm-logstash-deploy: ## Compatibilité historique : Logstash n'est pas déployé
	@echo "Aucun Logstash ni APM Server n'est déployé par l'architecture active."

##@ Déploiement et recette de l'application

apm-token-sync: ## Copier dans le namespace applicatif les secrets APM requis par order-service
	@set -euo pipefail; \
	$(KUBECTL) apply -f ../kubernetes/apps/supermarket-demo/base/namespace.yaml; \
	token="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret apm-server-apm-token -o jsonpath='{.data.secret-token}' | base64 --decode)"; \
	ca_file="$$(mktemp)"; \
	trap 'rm -f "$$ca_file"' EXIT; \
	$(KUBECTL) -n $(K8S_NAMESPACE) get secret apm-server-apm-http-certs-public -o jsonpath='{.data.ca\.crt}' | base64 --decode > "$$ca_file"; \
	$(KUBECTL) -n $(APP_NAMESPACE) create secret generic order-service-apm-token --from-literal=secret-token="$$token" --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	$(KUBECTL) -n $(APP_NAMESPACE) create secret generic order-service-apm-server-ca --from-file=ca.crt="$$ca_file" --dry-run=client -o yaml | $(KUBECTL) apply -f -

apps-deploy: ## Déployer uniquement l'application de démonstration
	@test '$(DEPLOYMENT_PROFILE)' = minimal || { echo "Profil Kubernetes inconnu : $(DEPLOYMENT_PROFILE) (seul minimal est supporté)" >&2; exit 1; }
	@$(KUBECTL) apply -k ../kubernetes/apps/supermarket-demo/default
	@$(KUBECTL) -n $(APP_NAMESPACE) set image deployment/order-service \
		order-service=order-service:$(APP_IMAGE_TAG)
	@$(KUBECTL) -n $(APP_NAMESPACE) set image deployment/inventory-service \
		inventory-service=inventory-service:$(APP_IMAGE_TAG)
	@$(KUBECTL) -n $(APP_NAMESPACE) set image deployment/restock-service \
		restock-service=restock-service:$(APP_IMAGE_TAG)
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/order-service --timeout=180s
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/inventory-service --timeout=180s
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/restock-service --timeout=180s

order-service-command: ## Envoyer une commande REST (ORDER_PRODUCT_ID, ORDER_QUANTITY) à order-service
	@pod_name="order-service-command-$$(date +%s)"; \
	$(KUBECTL) -n $(APP_NAMESPACE) run "$$pod_name" --image=curlimages/curl:8.12.1 \
		--restart=Never --rm --attach -i --command -- \
		curl --fail --silent --show-error -X POST http://order-service:3000/api/orders \
		-H 'Content-Type: application/json' \
		--data '{"productId":"$(ORDER_PRODUCT_ID)","quantity":$(ORDER_QUANTITY)}'

##@ Déploiement complet et validation

slides: ## Démarrer le support Slidev de l'architecture
	@npm --prefix slides run dev

vms-up: ## Démarrer et provisionner les quatre VM, sans déployer Kubernetes ni l'application
	@set -euo pipefail; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$${POSTGRESQL_PASSWORD:-password}" $(VAGRANT) up poc-01 otel-backend-01 otel-edge-01 elk-01 --provision-with ansible

elastic-agent-vm-provision: ## Déployer la configuration EDOT standalone des agents VM
	@set -euo pipefail; \
	for node in poc-01 otel-backend-01 otel-edge-01 elk-01; do \
	  echo "Provisionnement Elastic Agent EDOT : $$node"; \
	  DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$${POSTGRESQL_PASSWORD:-password}" $(VAGRANT) provision "$$node" --provision-with ansible; \
	done

deploy: ## Déployer Elastic, Fleet, Kubernetes et les applications après vms-up
	@set -euo pipefail; \
	SKIP_ELK_VM_PROVISION=1 $(MAKE) elk-deploy; \
	$(MAKE) apps-build; \
	$(MAKE) images-import; \
	$(MAKE) apps-deploy

kubernetes-validate: ## Générer les manifests Kustomize sans les appliquer
	@$(KUBECTL) kustomize $(ARCH_ROOT)/platform/kubernetes/overlays/local >/dev/null
	@$(KUBECTL) kustomize ../kubernetes/apps/supermarket-demo/default >/dev/null

ansible-validate: ## Vérifier la syntaxe du playbook Ansible sans provisionner
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/vagrant.yml $(ARCH_ROOT)/ansible/site.yml
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/vagrant.yml $(ARCH_ROOT)/ansible/deploy-all.yml

ansible-deploy: ## Déployer toute l'architecture via un seul orchestrateur Ansible
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i ansible/inventory/vagrant.yml $(ARCH_ROOT)/ansible/deploy-all.yml

otel-validation: ## Valider OTLP (VALIDATION_TAGS=host|direct ; vide = les deux)
	@inventory="$${INVENTORY:-validation/otel/inventory/hosts.yml}"; \
	validation_tags="$${VALIDATION_TAGS:-}"; \
	case "$$inventory" in /*|../*) ;; *) inventory="../$$inventory";; esac; \
	if [ -n "$$validation_tags" ]; then tag_args=(--tags "$$validation_tags"); else tag_args=(); fi; \
	ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook "$${tag_args[@]}" -i "$$inventory" ../validation/otel/playbook.yml

ci: kubernetes-validate ansible-validate apps-test ## Exécuter les validations reproductibles du dépôt

##@ Provisionnement des VM et Fleet

fleet-sync: ## Synchroniser les pipelines et la policy Fleet
	@KIBANA_URL='$(KIBANA_URL)' KIBANA_HOST='$(KIBANA_HOST)' DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' \
		ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ./$(ARCH_ROOT)/platform/elk/scripts/sync-fleet-policies.sh

kafka-jolokia-verify: ## Vérifier les MBeans Kafka exposés par Jolokia sur poc-01
	@$(VAGRANT) ssh poc-01 -c 'curl --fail --silent http://127.0.0.1:8778/jolokia >/dev/null'

mongodb-workload: ## Générer une charge MongoDB courte pour valider la collecte
	@$(VAGRANT) ssh poc-01 -c 'sudo podman exec -i observability-mongodb mongosh --quiet' < ../scripts/mongodb-elk-workload.js

fleet-vm-monitoring: elastic-stack-deploy ## Activer le monitoring Fleet OpAMP des agents EDOT des VM
	@$(MAKE) kibana-ready
	@set -euo pipefail; kibana_password="$${KIBANA_PASSWORD:-password}"; postgresql_password="$${POSTGRESQL_PASSWORD:-password}"; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" POSTGRESQL_PASSWORD="$$postgresql_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/bootstrap-fleet-policies.sh; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/provision-fleet-vms.sh

fleet-vms-provision: fleet-vm-monitoring ## Alias historique du monitoring Fleet des VM

vm-provision: fleet-vm-monitoring ## Provisionner le monitoring Fleet des agents EDOT des VM

otel-gateway-vm-provision: ## Provisionner les gateways OTEL sur otel-backend-01 avec la clé API Kubernetes existante
	@$(VAGRANT) up otel-backend-01 --no-provision
	@api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	password="$${ELASTIC_PASSWORD:-password}"; \
	test -n "$$api_key" || { echo 'Clé API OTel absente : exécuter d’abord make otel-elasticsearch-credentials-apply.' >&2; exit 1; }; \
	test -n "$$password" || { echo 'ELASTIC_PASSWORD absent.' >&2; exit 1; }; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' ELASTIC_PASSWORD="$$password" OTEL_ELASTICSEARCH_API_KEY="$$api_key" $(VAGRANT) provision otel-backend-01 --provision-with ansible

otel-edge-vm-provision: ## Provisionner le Collecteur EDOT Edge sur otel-edge-01
	@$(VAGRANT) up otel-edge-01 --no-provision
	@DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$${POSTGRESQL_PASSWORD:-password}" $(VAGRANT) provision otel-edge-01 --provision-with ansible

otel-gateway-vm-status: ## Vérifier HAProxy et le Collecteur EDOT Edge
	@set -euo pipefail; $(VAGRANT) ssh otel-edge-01 -c 'sudo systemctl is-active haproxy && sudo systemctl is-active observability-otel-edge && curl --fail --silent http://127.0.0.1:13135/'; $(VAGRANT) ssh otel-backend-01 -c 'sudo systemctl is-active observability-otel-kafka-exporter && curl --fail --silent http://127.0.0.1:13134/'

otel-gateway-kubernetes-remove: ## Supprimer les anciens objets de la gateway OTLP Kubernetes
	@$(KUBECTL) -n $(K8S_NAMESPACE) delete deployment,service,serviceaccount,configmap otel-gateway --ignore-not-found

otel-gateway-kubernetes-bascule: otel-gateway-kubernetes-remove ## Déployer les collecteurs Kubernetes et les applications avec Edge comme endpoint OTLP
	@$(KUBECTL) apply -k $(ARCH_ROOT)/platform/kubernetes/overlays/local
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-kubernetes-cluster daemonset/otel-kubernetes
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-kubernetes-cluster --timeout=180s
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status daemonset/otel-kubernetes --timeout=180s
	@$(KUBECTL) apply -k ../kubernetes/apps/supermarket-demo/default
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout restart deployment/order-service deployment/inventory-service deployment/restock-service
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/order-service deployment/inventory-service deployment/restock-service --timeout=180s

kubernetes-observability-deploy: otel-gateway-kubernetes-remove ## Appliquer et vérifier les Collectors Kubernetes déclarés par Kustomize
	@$(KUBECTL) apply -k $(ARCH_ROOT)/platform/kubernetes/overlays/local
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-kubernetes-cluster daemonset/otel-kubernetes
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-kubernetes-cluster --timeout=180s
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status daemonset/otel-kubernetes --timeout=180s

otel-gateway-relocate: otel-gateway-vm-provision otel-gateway-kubernetes-bascule ## Basculer le Gateway OTLP de Kubernetes vers le backend OTEL

otel-kafka-exporter-vm-provision: ## Provisionner l'exporteur Kafka OTel sur otel-backend-01 avec la clé API Kubernetes existante
	@$(VAGRANT) up otel-backend-01 --no-provision
	@api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	password="$${ELASTIC_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	test -n "$$api_key" || { echo 'Clé API OTel absente : exécuter d’abord make otel-elasticsearch-credentials-apply.' >&2; exit 1; }; \
	test -n "$$password" || { echo 'ELASTIC_PASSWORD absent.' >&2; exit 1; }; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' ELASTIC_PASSWORD="$$password" OTEL_ELASTICSEARCH_API_KEY="$$api_key" $(VAGRANT) provision otel-backend-01
	@set -euo pipefail; { printf '%s' 'ELASTICSEARCH_API_KEY='; $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' | base64 --decode; printf '\n'; } | \
		$(VAGRANT) ssh otel-backend-01 -c 'sudo tee /etc/observability/otel-kafka-exporter.env >/dev/null && sudo chmod 600 /etc/observability/otel-kafka-exporter.env && sudo systemctl restart observability-otel-kafka-exporter'

otel-kafka-exporter-vm-status: ## Vérifier l'exporteur Kafka OTel exécuté sur otel-backend-01
	@$(VAGRANT) ssh otel-backend-01 -c 'sudo systemctl is-active observability-otel-kafka-exporter && curl --fail --silent http://127.0.0.1:13134/'

otel-kafka-exporter-kubernetes-bascule: ## Retirer l'exporteur Kubernetes après validation du backend OTEL
	@$(KUBECTL) apply -k $(ARCH_ROOT)/platform/kubernetes/overlays/local
	@$(KUBECTL) -n $(K8S_NAMESPACE) delete deployment,service otel-kafka-exporter --ignore-not-found
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status daemonset/otel-kubernetes --timeout=180s
	@$(MAKE) otel-kafka-exporter-vm-status

otel-kafka-exporter-relocate: otel-kafka-exporter-vm-provision otel-kafka-exporter-kubernetes-bascule ## Basculer l'exporteur Kafka OTel vers le backend OTEL

##@ Dashboards et consultation

dashboards-backup: ## Sauvegarder tous les dashboards Kibana et leurs références
	@kibana_password="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )"; \
	test -n "$$kibana_password" || { echo 'Mot de passe Kibana requis pour la sauvegarde.' >&2; exit 1; }; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/backup-kibana-dashboards.sh

dashboards-verify: ## Vérifier que les jeux de données alimentant les dashboards sont récents
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
		test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour la stack Elastic Quadlet.' >&2; exit 1; }; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/verify-dashboard-data.sh; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$es_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/verify-postgresql-otel-dashboards.sh; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$es_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/verify-kubernetes-otel-dashboards.sh

postgresql-otel-dashboards-verify: ## Vérifier les métriques et requêtes des dashboards PostgreSQL OTel
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
		test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour la vérification.' >&2; exit 1; }; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$es_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/verify-postgresql-otel-dashboards.sh

kubernetes-otel-dashboards-verify: ## Vérifier les requêtes des dashboards Kubernetes OTel
	@kibana_password="$${KIBANA_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$kibana_password" || { echo 'KIBANA_PASSWORD ou le secret ECK est requis' >&2; exit 1; }; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ./$(ARCH_ROOT)/platform/elk/scripts/verify-kubernetes-otel-dashboards.sh

##@ Identifiants et clés d'accès

apm-report-api-key-create: ## Créer une clé de lecture brute pour les rapports APM SystemLens
	@test -n "$$ELASTICSEARCH_PASSWORD" || { echo "Définir ELASTICSEARCH_PASSWORD (source $(ARCH_ROOT)/platform/elk/scripts/load-credentials.sh)" >&2; exit 1; }
	@curl --fail --silent --show-error --insecure \
		--resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
		-u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-H 'Content-Type: application/json' \
		-X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
		--data "{\"name\":\"systemlens-apm-report-$$(date +%Y%m%d%H%M%S)\",\"role_descriptors\":{\"systemlens_apm_report_reader\":{\"cluster\":[\"monitor\"],\"indices\":[{\"names\":[\"traces-*\",\"metrics-*\"],\"privileges\":[\"read\",\"view_index_metadata\"]}]}}}" \
		| jq -er '.id + ":" + .api_key'

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

##@ Logs applicatifs

stock-view: ## Afficher le stock courant du catalogue PostgreSQL
	@$(VAGRANT) ssh poc-01 -c 'sudo podman exec observability-postgresql psql -U observability -d observability_test -P pager=off -c "SELECT id, name, stock_quantity AS stock FROM products ORDER BY id;"'

order-service-logs-follow: ## Suivre les logs de order-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/order-service

inventory-service-logs-follow: ## Suivre les logs de inventory-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/inventory-service

restock-service-logs-follow: ## Suivre les logs de restock-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/restock-service

.PHONY: retention-validate retention-plan retention-deploy retention-verify ilm-deploy

retention-validate: ## Valider les règles de rétention sans les appliquer
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/vagrant.yml ansible/retention.yml
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/vagrant.yml ansible/retention-verify.yml
	@python3 -c 'import ast,json,pathlib; ast.parse(pathlib.Path("platform/elk/scripts/retention.py").read_text()); ast.parse(pathlib.Path("ansible/roles/retention/files/purge-logs.py").read_text()); json.loads(pathlib.Path("platform/elk/ilm/retention.json").read_text())'

retention-plan: ## Lire le périmètre et les politiques ILM sans mutation
	@python3 platform/elk/scripts/retention.py plan

ilm-deploy: ## Réconcilier les politiques ILM et les indices existants
	@python3 platform/elk/scripts/retention.py apply

retention-deploy: retention-validate ## Déployer uniquement la rétention VM, Kafka et ILM
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i ansible/inventory/vagrant.yml ansible/retention.yml
	@$(MAKE) ilm-deploy
	@$(MAKE) retention-verify

retention-verify: ## Contrôler les timers, Kafka et ILM effectivement déployés
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i ansible/inventory/vagrant.yml ansible/retention-verify.yml
	@python3 platform/elk/scripts/retention.py verify
