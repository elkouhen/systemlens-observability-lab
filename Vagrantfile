# -*- mode: ruby -*-
# vi: set ft=ruby :

NODES = [
  { name: "data-01", id: 1, ip: "192.168.33.10", jolokia_port: 18_781, jmx_port: 19_991 },
  { name: "data-02", id: 2, ip: "192.168.33.11", jolokia_port: 18_782, jmx_port: 19_992 },
  { name: "data-03", id: 3, ip: "192.168.33.12", jolokia_port: 18_783, jmx_port: 19_993 }
].freeze

Vagrant.configure("2") do |config|
  config.vm.box = "cloud-image/rocky-10"
  # Secret injecte au provisionnement, jamais versionne dans le depot.
  elasticsearch_api_key = ENV["ELASTICSEARCH_API_KEY"]
  fleet_enrollment_token = ENV["FLEET_ENROLLMENT_TOKEN"]
  postgresql_password = ENV["POSTGRESQL_PASSWORD"]
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
      # Jolokia est utile pour les requêtes HTTP locales ; JConsole requiert
      # l'endpoint JMX/RMI distinct. Les deux restent accessibles seulement
      # depuis la machine hôte, jamais depuis le réseau local.
      node.vm.network "forwarded_port", guest: 8778, host: node_config[:jolokia_port], host_ip: "127.0.0.1", auto_correct: false
      node.vm.network "forwarded_port", guest: 9999, host: node_config[:jmx_port], host_ip: "127.0.0.1", auto_correct: false

      node.vm.provider "virtualbox" do |vb|
        # Rocky Linux 10 needs an Intel NIC for the host-only interface.
        vb.customize ["modifyvm", :id, "--nictype2", "82540EM"]
        vb.memory = "1536"
        vb.cpus = 1
      end

      # data-01 et data-02 utilisent Elastic Agent/Fleet ; data-03 utilise
      # Filebeat/Metricbeat. Les secrets sont passés comme extra-vars et ne
      # sont jamais écrits dans le dépôt.
      node.vm.provision "ansible" do |ansible|
        ansible.playbook = "ansible/site.yml"
        ansible.extra_vars = {
          "poc_node_id" => node_config[:id],
          "poc_node_ip" => node_config[:ip],
          "elasticsearch_api_key" => elasticsearch_api_key || "",
          "fleet_enrollment_token" => fleet_enrollment_token || "",
          "postgresql_password" => postgresql_password || "",
          "poc_redeploy_services" => redeploy_services,
          "zscaler_ca_cert_content" => zscaler_ca_cert_content
        }
      end
    end
  end
end
