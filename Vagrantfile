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
  fleet_enrollment_token = ENV["FLEET_ENROLLMENT_TOKEN"]
  redeploy_services = ENV.fetch("POC_REDEPLOY_SERVICES", "false") == "true"
  force_agent_reenroll = ENV.fetch("ELASTIC_AGENT_FORCE_REENROLL", "false") == "true"

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
      # MongoDB/Kafka et l'agent Fleet. Le token est passé comme extra-var et
      # n'est jamais écrit dans le dépôt.
      node.vm.provision "ansible" do |ansible|
        ansible.playbook = "ansible/site.yml"
        ansible.extra_vars = {
          "poc_node_id" => node_config[:id],
          "poc_node_ip" => node_config[:ip],
          "fleet_enrollment_token" => fleet_enrollment_token || "",
          "poc_redeploy_services" => redeploy_services,
          "elastic_agent_force_reenroll" => force_agent_reenroll
        }
      end
    end
  end
end
