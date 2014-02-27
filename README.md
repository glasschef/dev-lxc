# dev-lxc

A tool for creating Chef server clusters using LXC containers.

Using [ruby-lxc](https://github.com/lxc/ruby-lxc) it builds a standalone server or
tier cluster composed of a backend and multiple frontends with round-robin DNS resolution.

The dev-lxc tool is well suited as a tool for support related work, customized
cluster builds for demo purposes, as well as general experimentation and exploration.

### Features

1. LXC 1.0 Containers - Resource efficient servers with fast start/stop times and standard init
2. Btrfs - Storage efficient container backend provides fast container cloning
3. Dnsmasq - DHCP networking and DNS resolution
4. Base platforms - Containers that are built to resemble a traditional server
5. ruby-lxc - Ruby bindings for LXC
6. YAML - Simple, customizable definition of clusters
7. Build process closely models the docs instructions

Its containers, standard init, networking and build process are designed to be similar
to what you would build if you follow the product installation documentation so the end
result is a cluster that is relatively similar to a more traditionally built cluster.

The Btrfs backed clones provides a quick clean slate which is so helpful especially
for experimenting and troubleshooting. Or it can be used to build a customized cluster
for demo purposes and be able to bring it up quickly and reliably.

While most of the plumbing is already in place for an HA cluster it actually can't be
used since I haven't been able to get DRBD working inside containers yet.

If you aren't familiar with using containers please read this introduction.

[LXC 1.0 Introduction](https://www.stgraber.org/2013/12/20/lxc-1-0-blog-post-series/)

## Requirements

The dev-lxc tool is designed to be used in platform built by the
[dev-lxc-platform cookbook](https://github.com/jeremiahsnapp/dev-lxc-platform).

Please follow the dev-lxc-platform usage instructions to create a suitable platform.

The cookbook will automatically install this dev-lxc tool.

## Usage

### Base Servers

One of the key things this tool uses is the concept of "base" servers.
It creates servers with "b-" prepended to the name to signify it as a base server.
Base servers are then snapshot cloned using the btrfs filesystem to provide very
quick, lightweight duplicates of the base server that are either used to build
another base server or a usable server.

The initial creation of base servers for the various platforms can take awhile so
let's go ahead and start creating an Ubuntu 12.04 base server now.

    dev-lxc create b-ubuntu-1204

You can see a menu of base servers this tool can create by using the following command.

    dev-lxc create

### Cluster Config Files

dev-lxc uses a yaml configuration file to define a cluster.

You can get sample config files for various cluster topologies by using the following command.

	dev-lxc cluster init

You can specify a particular config file as an option for most dev-lxc commands
or let dev-lxc look for a dev-lxc.yaml file in the present working directory by default.

The following instructions will use a tier cluster for demonstration purposes.
The size of this cluster uses about 3GB ram and takes a longer time for the first
build of the servers. Feel free to try the standalone config first.

The following command saves a predefined config to dev-lxc.yaml.

	dev-lxc cluster init tier > dev-lxc.yaml

The file looks like this:

    base_platform: b-ubuntu-1204
    topology: tier
    api_fqdn: chef-tier.lxc
    mount:
      - /oc oc
      - /dev-shared dev-shared
    package:
      server: /dev-shared/chef-packages/ec/private-chef_11.1.1-1.ubuntu.12.04_amd64.deb
      reporting: /dev-shared/chef-packages/ec/reporting/opscode-reporting_1.1.0-1.ubuntu.12.04_amd64.deb
      push-jobs-server: /dev-shared/chef-packages/ec/push-jobs-server/opscode-push-jobs-server_1.1.0-1.ubuntu.12.04_amd64.deb
      manage: /dev-shared/chef-packages/ec/manage/opscode-manage_1.1.1-1.ubuntu.12.04_amd64.deb
    server:
      be-tier.lxc:
        role: backend
        ipaddress: 10.0.3.202
        bootstrap: true
      fe1-tier.lxc:
        role: frontend
        ipaddress: 10.0.3.203
    #  fe2-tier.lxc:
    #    role: frontend
    #    ipaddress: 10.0.3.204

This config defines a tier cluster consisting of a single backend and a single frontend.
A second frontend is commented out to conserve resources.

If you uncomment the second frontend then both frontends will be created and dnsmasq will
resolve the api_fqdn chef-tier.lxc to both frontends using a round-robin policy.

The config file is very customizable. You can add or remove mounts, packages or servers,
change ip addresses, change server names, change the base_platform and more.

Make sure the mounts and packages represent paths that are available in your environment.

### Managing a Cluster

Starting the cluster the first time takes awhile since it has a lot to build.

The tool automatically creates snapshot clones at appropriate times so future
creation of the cluster's servers is very quick.

	dev-lxc cluster start

https://chef-tier.lxc resolves to the frontend.

Typical ponyville and wonderbolts orgs, users, knife.rb and keys are automatically created in
the bootstrap backend server in /srv/piab/users.

Show the status of the cluster.

    dev-cluster status

Stop the cluster's servers.

	dev-lxc cluster stop

Clones of the servers as they existed immediately after initial installation and configuration
are available so you can destroy the cluster and "rebuild" it within seconds effectively starting
with a clean slate.

    dev-lxc cluster destroy
	dev-lxc cluster start

The abspath subcommand can be used to prepend each server's rootfs path to a particular file.

For example, to edit each server's private-chef.rb file you can use the following command.

    emacs $(dev-lxc cluster abspath /etc/opscode/private-chef.rb)

After modifying the private-chef.rb you could use the run_command subcommand to tell each server
to run `private-chef-ctl reconfigure`.

    dev-lxc cluster run_command 'private-chef-ctl reconfigure'

Use the following command to destroy the cluster's servers and also destroy their corresponding
base servers so you can build them from scratch.

    dev-lxc cluster destroy -b

You can also run most of these commands against individual servers by using the server subcommand.

    dev-lxc server ...

### Using the dev-lxc library

dev-lxc can also be used as a library if preferred.

    irb(main):001:0> require 'yaml'
	irb(main):002:0> require 'dev-lxc'
	irb(main):003:0> cluster = DevLXC::ChefCluster.new(YAML.load(IO.read('dev-lxc.yaml')))
	irb(main):004:0> cluster.start
	irb(main):005:0> server = DevLXC::ChefServer.new("fe1-tier.lxc", YAML.load(IO.read('dev-lxc.yaml')))
	irb(main):006:0> server.stop
	irb(main):007:0> server.start
	irb(main):008:0> server.run_command("private-chef-ctl reconfigure")
	irb(main):009:0> cluster.destroy

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
