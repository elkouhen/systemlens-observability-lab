SHELL := /bin/bash
.DEFAULT_GOAL := help

KUBECTL ?= kubectl
VAGRANT ?= vagrant
K3D_CLUSTER ?= elastic
DEPLOYMENT_PROFILE := minimal
ARCH_VERSION := v2
ARCH_NAME := OpenTelemetry + Kafka
ARCH_ROOT := .
K8S_NAMESPACE ?= elastic-stack
APP_NAMESPACE ?= h0tl-supermarche-app
APP_IMAGE_TAG ?= 1.1.1
ORDER_PRODUCT_ID ?= PASTA-500G
ORDER_QUANTITY ?= 1
ELASTIC_STACK_VERSION ?= 9.4.3
ECK_VERSION ?= 3.5.0
ECK_HELM_REPOSITORY ?= https://helm.elastic.co
ECK_STACK_CHART_VERSION ?= 0.20.0
ELASTICSEARCH_URL ?= https://elasticsearch.observability.test:443
KIBANA_URL ?= https://kibana.observability.test
KIBANA_HOST ?= kibana.observability.test
KIBANA_CURL_RESOLVE ?= kibana.observability.test:443:127.0.0.1
ELASTICSEARCH_CURL_RESOLVE ?= elasticsearch.observability.test:443:127.0.0.1
# Certificat racine Zscaler (ou proxy TLS d'entreprise équivalent) au format
# PEM. Laisser vide sur une machine sans interception TLS : voir certs/README.md.
ZSCALER_CA_CERT ?=
K3D_CA_DEST ?= /usr/local/share/ca-certificates/zscaler-root-ca.crt

.PHONY: help architecture-switch architecture-status credentials-show cluster-info platform-status kubernetes-status apps-build apps-test images-import kubernetes-validate ansible-validate eck-deploy elastic-stack-deploy otel-elasticsearch-credentials-apply \
	elk-deploy kibana-fleet-config-deploy apm-data-view-deploy apm-logstash-credentials-apply apm-logstash-deploy apps-deploy apm-token-sync fleet-sync fleet-vms-provision vm-provision \
	postgresql-credentials-apply kafka-jolokia-verify mongodb-workload \
	deploy elasticsearch-ready kibana-ready apm-kibana-role-apply \
	dashboards-verify apm-report-api-key-create \
	elastic-password-show kibana-password-show apm-token-show elasticsearch-api-key-create \
	beats-api-key-create stock-view order-service-command order-service-logs-follow inventory-service-logs-follow restock-service-logs-follow k3d-ca-import public-tls-apply ci

##@ Informations et diagnostic

help: ## Afficher les tâches disponibles
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <cible>\n"} \
		/^##@/ {printf "\n%s\n", substr($$0, 5); next} \
		/^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-32s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

architecture-status: ## Afficher l'architecture sélectionnée
	@printf 'ARCH_VERSION=%s\nARCH_NAME=%s\nELASTIC_STACK_VERSION=%s\nARCH_ROOT=%s\n' '$(ARCH_VERSION)' '$(ARCH_NAME)' '$(ELASTIC_STACK_VERSION)' '$(ARCH_ROOT)'

architecture-switch: ## Sélectionner une architecture persistante (VERSION=v1|v2)
	@test '$(VERSION)' = v1 -o '$(VERSION)' = v2 || { echo 'VERSION doit valoir v1 ou v2' >&2; exit 1; }
	@printf '%s\n' '$(VERSION)' > .architecture-version
	@echo "Architecture sélectionnée : $(VERSION)"

credentials-show: ## Indiquer comment charger les identifiants dans le shell courant
	@printf 'source ./$(ARCH_ROOT)/platform/elk/scripts/load-credentials.sh\n'

cluster-info: ## Afficher les URL et identifiants de l'environnement ELK local
	@printf 'KIBANA_URL=%s\nELASTICSEARCH_URL=%s\nFLEET_URL=%s\nUSER=elastic\n' \
		'$(KIBANA_URL)' '$(ELASTICSEARCH_URL)' 'https://fleet.observability.test'

platform-status: kubernetes-status vm-status ## Vérifier Kubernetes et les VM

kubernetes-status: ## Afficher l’état Elastic et applications
	@$(KUBECTL) -n $(K8S_NAMESPACE) get elasticsearch,kibana,agent
	@$(KUBECTL) -n $(APP_NAMESPACE) get deployment,pods

vm-status: ## Vérifier les conteneurs MongoDB, Kafka et PostgreSQL des VM
	@DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' ../scripts/cluster-status.sh

##@ Construction et préparation locale

apps-build: ## Construire les images applicatives (tag APP_IMAGE_TAG ; option ZSCALER_CA_CERT)
	@zscaler_ca_b64=""; \
	if [ -n "$(ZSCALER_CA_CERT)" ]; then \
	  test -f "$(ZSCALER_CA_CERT)" || { echo "Certificat Zscaler introuvable : $(ZSCALER_CA_CERT)" >&2; exit 1; }; \
	  zscaler_ca_b64="$$(base64 < "$(ZSCALER_CA_CERT)" | tr -d '\n')"; \
	fi; \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --target order-service -t order-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo && \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --target inventory-service -t inventory-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo && \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --target restock-service -t restock-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo

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

elasticsearch-ready: ## Attendre qu'ECK rende Elasticsearch joignable
	@$(KUBECTL) -n $(K8S_NAMESPACE) wait \
		--for=condition=ElasticsearchIsReachable=True \
		elasticsearch/elasticsearch --timeout=300s

kibana-ready: ## Attendre que Kibana soit prêt avant l'import de ses objets
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status \
		deployment/elastic-stack-eck-kibana-kb --timeout=300s
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
	@$(KUBECTL) apply -k $(ARCH_ROOT)/platform/kubernetes/overlays/local

eck-deploy: ## Installer ou mettre à jour l'opérateur ECK 3.5.0
	@helm repo add elastic $(ECK_HELM_REPOSITORY) --force-update
	@helm repo update elastic
	@helm upgrade --install elastic-operator elastic/eck-operator \
		--namespace elastic-system --create-namespace --version $(ECK_VERSION)
	@$(KUBECTL) -n elastic-system rollout status statefulset/elastic-operator --timeout=300s

elastic-stack-deploy: ## Déployer Elasticsearch et Kibana de l'architecture sélectionnée avec ECK
	@helm repo add elastic $(ECK_HELM_REPOSITORY) --force-update
	@helm repo update elastic
	# ECK devient propriétaire de nodeSets après la première réconciliation :
	# Helm ne doit plus tenter de les réappliquer sur une release existante.
	@if helm status elastic-stack --namespace $(K8S_NAMESPACE) >/dev/null 2>&1; then \
		helm upgrade elastic-stack elastic/eck-stack \
			--namespace $(K8S_NAMESPACE) --version $(ECK_STACK_CHART_VERSION) \
			--force-conflicts \
			--set eck-elasticsearch.version=$(ELASTIC_STACK_VERSION) \
			--set eck-kibana.version=$(ELASTIC_STACK_VERSION) \
			-f $(ARCH_ROOT)/platform/helm/eck-stack-values.yaml; \
	else \
		helm install elastic-stack elastic/eck-stack \
			--namespace $(K8S_NAMESPACE) --create-namespace --version $(ECK_STACK_CHART_VERSION) \
			--set eck-elasticsearch.version=$(ELASTIC_STACK_VERSION) \
			--set eck-kibana.version=$(ELASTIC_STACK_VERSION) \
		-f $(ARCH_ROOT)/platform/helm/eck-stack-values.yaml; \
	fi

postgresql-credentials-apply: ## Créer ou mettre à jour le secret PostgreSQL Fleet (requiert POSTGRESQL_PASSWORD)
	@$(KUBECTL) apply -f ../kubernetes/apps/supermarket-demo/base/namespace.yaml
	@postgresql_password="$${POSTGRESQL_PASSWORD:-$$( $(KUBECTL) -n $(APP_NAMESPACE) get secret postgresql-credentials -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode )}"; \
	test -n "$$postgresql_password" || { echo "Définir POSTGRESQL_PASSWORD hors Git (requis au premier déploiement)" >&2; exit 1; }; \
	$(KUBECTL) -n $(K8S_NAMESPACE) create secret generic postgresql-fleet-credentials \
		--from-literal=password="$$postgresql_password" --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	$(KUBECTL) -n $(APP_NAMESPACE) create secret generic postgresql-credentials \
		--from-literal=password="$$postgresql_password" --dry-run=client -o yaml | $(KUBECTL) apply -f -

otel-elasticsearch-credentials-apply: elasticsearch-ready ## Créer ou réconcilier la clé API Elasticsearch du Collector OTel
	@current_api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials \
		-o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	if test -n "$$current_api_key" && curl --fail --silent --show-error --insecure \
		--resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
		-H "Authorization: ApiKey $$current_api_key" \
		'$(ELASTICSEARCH_URL)/_security/_authenticate' >/dev/null; then \
		echo "Clé API otel-elasticsearch-credentials valide"; \
	else \
		password="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
		api_key="$$(curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
			-u "elastic:$$password" -H 'Content-Type: application/json' -X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
			--data '{"name":"otel-collector-writer","role_descriptors":{"otel_writer":{"cluster":["monitor"],"indices":[{"names":["traces-*","metrics-*","logs-*"],"privileges":["auto_configure","create_doc"]}]}}}' \
			| jq -er '.encoded')"; \
		$(KUBECTL) -n $(K8S_NAMESPACE) create secret generic otel-elasticsearch-credentials \
			--from-literal=api-key="$$api_key" --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
		echo "Clé API otel-elasticsearch-credentials réconciliée"; \
	fi

elk-deploy: eck-deploy elastic-stack-deploy postgresql-credentials-apply public-tls-apply otel-elasticsearch-credentials-apply ## Déployer la plateforme d'observabilité Elastic
	@$(KUBECTL) -n $(K8S_NAMESPACE) delete job otel-telemetry-topics-v3 --ignore-not-found
	@$(KUBECTL) apply -k $(ARCH_ROOT)/platform/kubernetes/overlays/local
	@$(KUBECTL) -n $(K8S_NAMESPACE) wait --for=condition=complete job/otel-telemetry-topics-v3 --timeout=180s
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-gateway deployment/otel-kafka-exporter
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart daemonset/otel-kubernetes
	@$(MAKE) kibana-ready
	@$(MAKE) apm-data-view-deploy

apm-data-view-deploy: ## Importer le data view APM versionné
	@kibana_password="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/deploy-kibana-dashboard.sh $(ARCH_ROOT)/platform/elk/dashboards/apm-data-view.ndjson

apm-kibana-role-apply: ## Accorder au compte APM les droits Kibana APM/Fleet en lecture
	@elasticsearch_password="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode )"; \
	test -n "$$elasticsearch_password" || { echo "Impossible de lire le mot de passe Elasticsearch" >&2; exit 1; }; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' \
		ELASTICSEARCH_PASSWORD="$$elasticsearch_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/apply-apm-kibana-role.sh

apm-logstash-credentials-apply: ## Compatibilité historique (aucun Logstash v2)
	@echo "Aucun secret Logstash n'est utilisé par l'architecture v2 (EDOT/Kafka)."

apm-logstash-deploy: ## Compatibilité historique : Logstash n'est pas déployé en v2
	@echo "Aucun Logstash ni APM Server n'est déployé par l'architecture v2."

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
	@$(KUBECTL) apply -k ../kubernetes/apps/supermarket-demo/v2
	@$(KUBECTL) -n $(APP_NAMESPACE) set image deployment/order-service \
		order-service=order-service:$(APP_IMAGE_TAG)
	@$(KUBECTL) -n $(APP_NAMESPACE) set image deployment/inventory-service \
		inventory-service=inventory-service:$(APP_IMAGE_TAG)
	@$(KUBECTL) -n $(APP_NAMESPACE) set image deployment/restock-service \
		restock-service=restock-service:$(APP_IMAGE_TAG)
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout restart deployment/order-service deployment/inventory-service deployment/restock-service
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

deploy: ## Déployer l'architecture complète : Kubernetes, VM et applications
	@set -euo pipefail; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$$POSTGRESQL_PASSWORD" $(VAGRANT) up; \
	$(MAKE) elk-deploy; \
	$(MAKE) apps-build; \
	$(MAKE) images-import; \
	$(MAKE) apps-deploy

kubernetes-validate: ## Générer les manifests Kustomize sans les appliquer
	@$(KUBECTL) kustomize $(ARCH_ROOT)/platform/kubernetes/overlays/local >/dev/null
	@$(KUBECTL) kustomize ../kubernetes/apps/supermarket-demo/v2 >/dev/null

ansible-validate: ## Vérifier la syntaxe du playbook Ansible sans provisionner
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/vagrant.yml $(ARCH_ROOT)/ansible/site.yml

ci: kubernetes-validate ansible-validate apps-test ## Exécuter les validations reproductibles du dépôt

##@ Provisionnement des VM et Fleet

fleet-sync: ## Synchroniser les pipelines, la policy Fleet et la compatibilité Kafka
	@KIBANA_URL='$(KIBANA_URL)' KIBANA_HOST='$(KIBANA_HOST)' DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' \
		ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ./$(ARCH_ROOT)/platform/elk/scripts/sync-fleet-policies.sh

kafka-jolokia-verify: ## Vérifier les MBeans Kafka exposés par Jolokia sur data-01
	@../scripts/check-kafka-jolokia.sh --url http://127.0.0.1:18781/jolokia

mongodb-workload: ## Générer une charge MongoDB courte pour valider la collecte
	@$(VAGRANT) ssh data-01 -c 'sudo podman exec -i observability-mongodb mongosh --quiet' < ../scripts/mongodb-elk-workload.js

vm-provision: ## Provisionner les VM avec EDOT (requiert POSTGRESQL_PASSWORD)
	@test -n "$$POSTGRESQL_PASSWORD" || { echo "Définir POSTGRESQL_PASSWORD hors Git" >&2; exit 1; }
	@DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$$POSTGRESQL_PASSWORD" $(VAGRANT) provision

##@ Dashboards et consultation

dashboards-verify: ## Vérifier que les jeux de données alimentant les dashboards sont récents
	@es_password="$$($(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode)"; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/verify-dashboard-data.sh

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
	@$(VAGRANT) ssh data-01 -c 'sudo podman exec observability-postgresql psql -U observability -d observability_test -P pager=off -c "SELECT id, name, stock_quantity AS stock FROM products ORDER BY id;"'

order-service-logs-follow: ## Suivre les logs de order-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/order-service

inventory-service-logs-follow: ## Suivre les logs de inventory-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/inventory-service

restock-service-logs-follow: ## Suivre les logs de restock-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/restock-service
