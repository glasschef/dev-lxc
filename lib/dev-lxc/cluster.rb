require "dev-lxc/server"

module DevLXC
  class Cluster
    attr_reader :api_fqdn, :analytics_fqdn, :chef_server_bootstrap_backend, :analytics_bootstrap_backend

    def initialize(cluster_config)
      @cluster_config = cluster_config

      if @cluster_config["chef-server"]
        @chef_server_topology = @cluster_config["chef-server"]["topology"]
        @api_fqdn = @cluster_config["chef-server"]["api_fqdn"]
        @chef_server_servers = @cluster_config["chef-server"]["servers"]
        @chef_server_frontends = Array.new
        @chef_server_servers.each do |name, config|
          case @chef_server_topology
          when 'open-source', 'standalone'
            @chef_server_bootstrap_backend = name if config["role"].nil?
          when 'tier'
            @chef_server_bootstrap_backend = name if config["role"] == "backend" && config["bootstrap"] == true
            @chef_server_frontends << name if config["role"] == "frontend"
          end
        end
      end

      if @cluster_config["analytics"]
        @analytics_topology = @cluster_config["analytics"]["topology"]
        @analytics_fqdn = @cluster_config["analytics"]["analytics_fqdn"]
        @analytics_servers = @cluster_config["analytics"]["servers"]
        @analytics_frontends = Array.new
        @analytics_servers.each do |name, config|
          case @analytics_topology
          when 'standalone'
            @analytics_bootstrap_backend = name if config["role"].nil?
          when 'tier'
            @analytics_bootstrap_backend = name if config["role"] == "backend" && config["bootstrap"] == true
            @analytics_frontends << name if config["role"] == "frontend"
          end
        end
      end
    end

    def servers
      chef_servers = Array.new
      chef_servers << Server.new(@chef_server_bootstrap_backend, 'chef-server', @cluster_config) if @chef_server_bootstrap_backend
      if @chef_server_topology == "tier"
        @chef_server_frontends.each do |frontend_name|
          chef_servers << Server.new(frontend_name, 'chef-server', @cluster_config)
        end
      end
      analytics_servers = Array.new
      analytics_servers << Server.new(@analytics_bootstrap_backend, 'analytics', @cluster_config) if @analytics_bootstrap_backend
      if @analytics_topology == "tier"
        @analytics_frontends.each do |frontend_name|
          analytics_servers << Server.new(frontend_name, 'analytics', @cluster_config)
        end
      end
      servers = chef_servers + analytics_servers
    end

    def chef_repo
      if @chef_server_bootstrap_backend.nil?
        puts "A bootstrap backend Chef Server is not defined in the cluster's config. Please define it first."
        exit 1
      end
      chef_server = Server.new(@chef_server_bootstrap_backend, 'chef-server', @cluster_config)
      if ! chef_server.server.defined?
        puts "The '#{chef_server.server.name}' Chef Server does not exist. Please create it first."
        exit 1
      end

      puts "Creating chef-repo with pem files and knife.rb in the current directory"
      FileUtils.mkdir_p("./chef-repo/.chef")

      pem_files = Dir.glob("#{chef_server.abspath('/root/chef-repo/.chef')}/*.pem")
      if pem_files.empty?
        puts "The pem files can not be copied because they do not exist in '#{chef_server.server.name}' Chef Server's `/root/chef-repo/.chef` directory"
      else
        FileUtils.cp( pem_files, "./chef-repo/.chef" )
      end

      if @chef_server_topology == "open-source"
        chef_server_url = "https://#{@api_fqdn}"
        username = "admin"
        validator_name = "chef-validator"
      else
        chef_server_url = "https://#{@api_fqdn}/organizations/ponyville"
        username = "rainbowdash"
        validator_name = "ponyville-validator"
      end

      knife_rb = %Q(
current_dir = File.dirname(__FILE__)

chef_server_url "#{chef_server_url}"

node_name "#{username}"
client_key "\#{current_dir}/#{username}.pem"

validation_client_name "#{validator_name}"
validation_key "\#{current_dir}/#{validator_name}.pem"

cookbook_path Dir.pwd + "/cookbooks"
knife[:chef_repo_path] = Dir.pwd
)
      IO.write("./chef-repo/.chef/knife.rb", knife_rb)

      bootstrap_node = %Q(#!/bin/bash

if [[ -z $1 ]]; then
  echo "Please provide the name of the node to be bootstrapped"
  return 1
fi

xc-start $1

xc-chef-config -s #{chef_server_url} \\
               -u #{validator_name} \\
               -k ./chef-repo/.chef/#{validator_name}.pem

if [[ -n $2 ]]; then
  xc-attach chef-client -r $2
else
  xc-attach chef-client
fi
)
      IO.write("./bootstrap-node", bootstrap_node)
      FileUtils.chmod("u+x", "./bootstrap-node")
    end

    def chef_server_config
      chef_server_config = %Q(api_fqdn "#{@api_fqdn}"\n)
      if @chef_server_topology == 'tier'
        chef_server_config += %Q(
topology "#{@chef_server_topology}"

server "#{@chef_server_bootstrap_backend}",
  :ipaddress => "#{@chef_server_servers[@chef_server_bootstrap_backend]["ipaddress"]}",
  :role => "backend",
  :bootstrap => true

backend_vip "#{@chef_server_bootstrap_backend}",
  :ipaddress => "#{@chef_server_servers[@chef_server_bootstrap_backend]["ipaddress"]}"
)
        @chef_server_frontends.each do |frontend_name|
          chef_server_config += %Q(
server "#{frontend_name}",
  :ipaddress => "#{@chef_server_servers[frontend_name]["ipaddress"]}",
  :role => "frontend"
)
        end
      end
      return chef_server_config
    end

    def analytics_config
      analytics_config = %Q(analytics_fqdn "#{@analytics_fqdn}"
topology "#{@analytics_topology}"
)
      if @analytics_topology == 'tier'
        analytics_config += %Q(
server "#{@analytics_bootstrap_backend}",
  :ipaddress => "#{@analytics_servers[@analytics_bootstrap_backend]["ipaddress"]}",
  :role => "backend",
  :bootstrap => true

backend_vip "#{@analytics_bootstrap_backend}",
  :ipaddress => "#{@analytics_servers[@analytics_bootstrap_backend]["ipaddress"]}"
)
        @analytics_frontends.each do |frontend_name|
          analytics_config += %Q(
server "#{frontend_name}",
  :ipaddress => "#{@analytics_servers[frontend_name]["ipaddress"]}",
  :role => "frontend"
)
        end
      end
      return analytics_config
    end

  end
end