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

      # Le réseau prive sert uniquement aux communications inter-VM.  Sans
      # cette configuration, Rocky peut preferer sa passerelle au NAT
      # VirtualBox et perdre l'acces Internet de l'hote.
      node.vm.provision "shell", path: "scripts/configure-private-network.sh",
                          args: [node_config[:ip]]
      # Chaque VM porte un membre MongoDB et un broker/controller Kafka.
      node.vm.provision "shell", path: "scripts/install-mongodb.sh",
                          args: [node_config[:id], node_config[:ip]]
      node.vm.provision "shell", path: "scripts/install-kafka.sh",
                          args: [node_config[:id], node_config[:ip]]
      if fleet_enrollment_token && !fleet_enrollment_token.empty?
        node.vm.provision "shell", path: "scripts/install-elastic-agent.sh",
                            args: [fleet_enrollment_token]
      end
    end
  end
end
