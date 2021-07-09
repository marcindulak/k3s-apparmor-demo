# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  # OpenSUSE
  config.vm.define "opensuse" do |machine|
    machine.vm.box = "opensuse/Leap-15.2.x86_64"
    machine.vm.box_url = machine.vm.box
    machine.vm.provider "virtualbox" do |p|
      p.memory = 1536
      p.cpus = 1
    end
  end
  config.vm.define "opensuse" do |machine|
    machine.vm.provision :shell, :inline => "hostnamectl set-hostname opensuse"
    machine.vm.provision :shell, :inline => "zypper install -y -t pattern apparmor"
    machine.vm.provision :shell, :inline => "zypper install -y apparmor-utils"
    machine.vm.provision :shell, :inline => "systemctl enable apparmor"
    machine.vm.provision :shell, :inline => "systemctl start apparmor"
    machine.vm.provision :shell, :inline => "zypper install -y pv"
  end
  # Ubuntu
  config.vm.define "ubuntu" do |machine|
    machine.vm.box = "ubuntu/focal64"
    machine.vm.box_url = machine.vm.box
    machine.vm.provider "virtualbox" do |p|
      p.memory = 1536
      p.cpus = 2
    end
  end
  config.vm.define "ubuntu" do |machine|
    machine.vm.provision :shell, :inline => "hostnamectl set-hostname ubuntu"
    machine.vm.provision :shell, :inline => "apt-get update"
    machine.vm.provision :shell, :inline => "apt-get install -y apparmor-utils"
    machine.vm.provision :shell, :inline => "systemctl enable apparmor"
    machine.vm.provision :shell, :inline => "systemctl start apparmor"
    machine.vm.provision :shell, :inline => "apt-get install -y pv"
  end
end
