# -*- mode: ruby -*-
# vi: set ft=ruby :

NODES = [
  { name: "data-01", id: 1, ip: "192.168.33.10" },
  { name: "data-02", id: 2, ip: "192.168.33.11" },
  { name: "data-03", id: 3, ip: "192.168.33.12" }
].freeze

Vagrant.configure("2") do |config|
  config.vm.box = "cloud-image/rocky-10"
  # Secret injecte au provisionnement, jamais versionne dans le depot.
  elasticsearch_api_key = ENV["ELASTICSEARCH_API_KEY"]
  fleet_enrollment_token = ENV["FLEET_ENROLLMENT_TOKEN"]
  redeploy_services = ENV.fetch("POC_REDEPLOY_SERVICES", "false") == "true"

  # Certificat racine Zscaler (ou proxy TLS d'entreprise équivalent), optionnel.
  # Sur une machine sans interception TLS, ne pas définir ZSCALER_CA_CERT :
  # aucune confiance supplémentaire n'est installée sur les VM. Voir certs/README.md.
  zscaler_ca_cert_path = ENV["ZSCALER_CA_CERT"]
  zscaler_ca_cert_content = ""
  if zscaler_ca_cert_path && !zscaler_ca_cert_path.empty?
    abort("ZSCALER_CA_CERT défini mais introuvable : #{zscaler_ca_cert_path}") unless File.exist?(zscaler_ca_cert_path)
    zscaler_ca_cert_content = File.read(zscaler_ca_cert_path)
  end

  NODES.each do |node_config|
    config.vm.define node_config[:name] do |node|
      node.vm.hostname = node_config[:name]
      node.vm.network "private_network", ip: node_config[:ip]

      node.vm.provider "virtualbox" do |vb|
        # Rocky Linux 10 needs an Intel NIC for the host-only interface.
        vb.customize ["modifyvm", :id, "--nictype2", "82540EM"]
        vb.memory = "1536"
        vb.cpus = 1
      end

      # Le playbook est idempotent : il configure le réseau, les conteneurs
      # MongoDB/Kafka, Filebeat et Metricbeat. La clé API Elasticsearch est
      # passée comme extra-var et n'est jamais écrite dans le dépôt.
      node.vm.provision "ansible" do |ansible|
        ansible.playbook = "ansible/site.yml"
        ansible.extra_vars = {
          "poc_node_id" => node_config[:id],
          "poc_node_ip" => node_config[:ip],
          "elasticsearch_api_key" => elasticsearch_api_key || "",
          "fleet_enrollment_token" => fleet_enrollment_token || "",
          "poc_redeploy_services" => redeploy_services,
          "zscaler_ca_cert_content" => zscaler_ca_cert_content
        }
      end
    end
  end
end
