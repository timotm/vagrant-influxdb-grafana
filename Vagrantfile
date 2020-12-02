# -*- mode: ruby -*-
# vi: set ft=ruby :

INFLUXDB_VERSION='2.0.2'


Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  config.vm.network "public_network"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
  end

  config.vm.provision "file", source: "./influxdb.service", destination: "$HOME/"
  config.vm.provision "file", source: "./influxdb-datasource.yaml", destination: "$HOME/"

  config.vm.provision "shell", env: {
      "INFLUXDB_VERSION" => INFLUXDB_VERSION
    }, path: "./provision.sh"
end
