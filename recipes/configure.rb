# include the install recipe for datastax
include_recipe 'dse::install'

# set up encryption if the attribute is set
if node['cassandra']['dse']['internode_encryption'] != 'none'
  include_recipe 'dse::ssl'
end

# set up the dse default file. This sets up hadoop, etc
template '/etc/default/dse' do
  source "dse/dse_#{node['cassandra']['dse_version']}.erb"
  owner node['cassandra']['user']
  group node['cassandra']['group']
  notifies :restart, "service[#{node['cassandra']['dse']['service_name']}]"
end

# set up log 4j temlate (audit logs, etc)
template "#{node['cassandra']['audit_dir']}/log4j-server.properties" do
  source 'log4j-server.properties.erb'
  owner node['cassandra']['user']
  group node['cassandra']['group']
  notifies :restart, "service[#{node['cassandra']['dse']['service_name']}]"
end

# set up the dse.yaml template for dse
template "#{node['cassandra']['dse']['conf_dir']}/dse.yaml" do
  source "dse_yaml/dse_#{node['cassandra']['dse_version']}.yaml.erb"
  owner node['cassandra']['user']
  group node['cassandra']['group']
  notifies :restart, "service[#{node['cassandra']['dse']['service_name']}]"
end

if node['cassandra']['role_based_seeds']
  list = []
  search(:node, node['cassandra']['seed_role']) do |m|
    list.push(m['ipaddress'])
  end
  list.sort!
  node.default['cassandra']['seeds'] = list.join(',')
end

# set up cassandra.yaml template (contains almost all cassandra tuning properties)
ssl_password_file = "#{node['cassandra']['dse']['cassandra_ssl_dir']}/#{node['cassandra']['dse']['password_file']}"
template "#{node['cassandra']['dse']['conf_dir']}/cassandra/cassandra.yaml" do
  source "cassandra_yaml/cassandra_#{node['cassandra']['dse_version']}.yaml.erb"
  variables(
    :dir => node['cassandra']['data_dir'],
    # lazily get the password, since it will be created for the first time before this. then strip off the newline (this is only for ssl)
    :ssl_password => lazy do
      if File.exist?(ssl_password_file)
        File.open(ssl_password_file, &:readline).chomp
      end
    end
  )
  owner node['cassandra']['user']
  group node['cassandra']['group']
  notifies :restart, "service[#{node['cassandra']['dse']['service_name']}]"
end

# set up the cassandra-env.sh template (this contains java heap settings)
template "#{node['cassandra']['dse']['conf_dir']}/cassandra/cassandra-env.sh" do
  source 'cassandra-env.sh.erb'
  owner node['cassandra']['user']
  group node['cassandra']['group']
  notifies :restart, "service[#{node['cassandra']['dse']['service_name']}]"
end

# check what kind of snitch is set, since it requires different templates.
case node['cassandra']['dse']['delegated_snitch']
# GossipingPropertyFile
when 'org.apache.cassandra.locator.GossipingPropertyFileSnitch'
  template "#{node['cassandra']['dse']['conf_dir']}/cassandra/cassandra-rackdc.properties" do
    source 'cassandra-rackdc.properties.erb'
    owner node['cassandra']['user']
    group node['cassandra']['group']
    notifies :restart, "service[#{node['cassandra']['dse']['service_name']}]"
  end
when 'org.apache.cassandra.locator.PropertyFileSnitch'
  # This requires a variable of cluster to be created.
  # This has been mostly deprecated in the use of this cookbook, but should still work.
  # Requires a chef search or some type of variable so every node knows every other node's datacenter and IP
  if Chef::Config[:solo]
    Chef::Log.warn('This recipe uses search. Chef Solo does not support search. Setting a default for testing.')
    cluster = [{ 'name' => node['hostname'], 'ip' => node['ipaddress'], 'dc' => 'TTC:RAC1' }]
  else
    # Set the cluster to the wrapper attribute if it exists
    cluster = node['cluster']
  end

  # Set up the topology sript
  template "#{node['cassandra']['dse']['conf_dir']}/cassandra/cassandra-topology.properties" do
    source 'cassandra-topology.properties.erb'
    notifies :restart, "service[#{node['cassandra']['dse']['service_name']}]"
    owner node['cassandra']['user']
    group node['cassandra']['group']
    variables :cluster => cluster
  end
end

# metrics?
include_recipe 'dse::metrics' if node['cassandra']['metrics_reporter']['enabled']
