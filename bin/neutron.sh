#/bin/bash
[[ "$(id -u)" != 0 ]] && { echo "not root"; exit 0; }
while getopts "a:c:d:" OPTION; do
case "$OPTION" in
a)
        ADMIN_PASS="$OPTARG"
        ;;
c)
        CLUSTER_NODES="$OPTARG"
        ;;
d)
        DEBUG_FLAG="$OPTARG"
        ;;
\?)
        echo "Invalid option: -"$OPTARG"" >&2
        usage
        exit 1
        ;;
:)
        usage
        exit 1
        ;;
esac
done
[[ ${DEBUG_FLAG} -eq 1 ]] && set -x
controller=${CLUSTER_NODES}
[[ -f /root/.adminrc ]] && source  /root/.adminrc
openstack user show neutron
if [[ $? -ne 0 ]]; then
	openstack user create --domain default --password ${ADMIN_PASS} neutron
	openstack role add --project service --user neutron admin
	openstack service create --name nova --description "OpenStack Networking Service" network
	openstack endpoint create --region RegionOne network public http://${controller}:9696
	openstack endpoint create --region RegionOne network internal http://${controller}:9696
	openstack endpoint create --region RegionOne network admin http://${controller}:9696
fi
[[ -f /etc/neutron/metadata_agent.ini ]] && mv -f /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.saved
cat >> /etc/neutron/metadata_agent.ini << EOF
[DEFAULT]
auth_uri = http://${controller}:5000/v2.0
auth_url = http://${controller}:35357/v2.0
auth_region = RegionOne
admin_tenant_name = service
admin_user = admin
admin_password = ${ADMIN_PASS}
auth_plugin = password
project_domain_id = default 
user_domain_id = default 
project_name = service
username = neutron
password = ${ADMIN_PASS}
nova_metadata_ip = ${controller}
metadata_proxy_shared_secret = neutronsucks
verbose = True
EOF

[[ -f /etc/neutron/neutron.conf ]] && mv -f /etc/neutron/neutron.conf /etc/neutron/neutron.conf.saved
cat >> /etc/neutron/neutron.conf << EOF
[DEFAULT]
notify_nova_on_port_data_changes = True
notify_nova_on_port_status_changes = True
auth_strategy = keystone
allow_overlapping_ips = True
debug = True
verbose = True
#service_plugins = neutron.services.l3_router.l3_router_plugin.L3RouterPlugin
service_plugins=router
#core_plugin = neutron.plugins.ml2.plugin.Ml2Plugin
core_plugin=ml2
rpc_backend = rabbit
logging_exception_prefix = %(color)s%(asctime)s.%(msecs)03d TRACE %(name)s [01;35m%(instance)s[00m
logging_debug_format_suffix = [00;33mfrom (pid=%(process)d) %(funcName)s %(pathname)s:%(lineno)d[00m
logging_default_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [[00;36m-%(color)s] [01;35m%(instance)s%(color)s%(message)s[00m
logging_context_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [[01;36m%(request_id)s [00;36m%(user_name)s %(project_id)s%(color)s] [01;35m%(instance)s%(color)s%(message)s[00m
use_syslog = False
state_path = /var/lib/neutron
nova_url = http://${controller}:8774/v2
[matchmaker_redis]
[matchmaker_ring]
[quotas]
[agent]
root_helper_daemon = sudo /usr/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf
[keystone_authtoken]
signing_dir = /var/cache/neutron
#cafile = /opt/stack/data/ca-bundle.pem
project_domain_id = default
project_name = service
user_domain_id = default
password = ${ADMIN_PASS}
username = neutron
auth_url = http://${controller}:35357
auth_plugin = password
auth_uri = http://${controller}:5000
identity_uri = http://${controller}:5000
admin_tenant_name = %SERVICE_TENANT_NAME%
admin_user = %SERVICE_USER%
admin_password = %SERVICE_PASSWORD%
[database]
connection = mysql://neutron:${ADMIN_PASS}@${controller}/neutron?charset=utf8
[nova]
region_name = RegionOne
project_domain_id = default
project_name = service
user_domain_id = default
password = ${ADMIN_PASS}
username = nova
auth_url = http://${controller}:35357
auth_plugin = password
[oslo_concurrency]
lock_path = $state_path/lock
[oslo_policy]
policy_file = /etc/neutron/policy.json
[oslo_messaging_amqp]
[oslo_messaging_qpid]
[oslo_messaging_rabbit]
rabbit_userid = openstack
rabbit_password = ${ADMIN_PASS}
rabbit_hosts = ${controller}
EOF
[[ -f /etc/neutron/plugins/ml2/ml2_conf.ini ]] && mv /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.saved
cat >> /etc/neutron/plugins/ml2/ml2_conf.ini << EOF
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = openvswitch
extension_drivers = port_security
[ml2_type_flat]
flat_networks = public
[ml2_type_vlan]
[ml2_type_vxlan]
vni_ranges = 1:1000
[securitygroup]
enable_security_group = True
enable_ipset = True
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
[ovs]
local_ip = ${controller}
bridge_mappings = vlan:br-vlan,external:br-ex
[agent]
tunnel_types = vxlan
EOF
[[ -f /etc/neutron/l3_agent.ini ]] && mv -f /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.orig
cat >> /etc/neutron/l3_agent.ini << EOF
[DEFAULT]
router_id = 
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
external_network_bridge = br-ex
gateway_external_network_id = 
router_delete_namespaces = True
verbose = True
EOF

[[ -f /etc/neutron/dhcp_agent.ini ]] && mv -f /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.orig
cat >> /etc/neutron/dhcp_agent.ini << EOF
[DEFAULT]
dhcp_domain = vms.crd.ge.com
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
dhcp_delete_namespaces = True
verbose = True
dnsmasq_config_file = /etc/neutron/dnsmasq-neutron.conf
EOF

echo "dhcp-option-force=26,1454" >  /etc/neutron/dnsmasq-neutron.conf

[[ -f /etc/neutron/metadata_agent.ini ]] && mv -f /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.orig
cat >> /etc/neutron/metadata_agent.ini << EOF
[DEFAULT]
auth_uri = http://${controller}:5000/v2.0
auth_url = http://${controller}:35357/v2.0
auth_region = RegionOne
admin_tenant_name = service
admin_user = admin
admin_password = ${ADMIN_PASS}
auth_plugin = password
project_domain_id = default 
user_domain_id = default 
project_name = service
username = neutron
password = ${ADMIN_PASS}
nova_metadata_ip = ${controller}
metadata_proxy_shared_secret = neutronsucks
verbose = True
EOF

[[ `grep  ^neutron /etc/sudoers | wc -l ` -lt 1 ]] && sed -i '/^root/a neutron ALL=(ALL) NOPASSWD:ALL' /etc/sudoers
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
[[ ! -d /var/cache/neutron ]] && mkdir -p /var/cache/neutron
chown -R neutron:neutron /var/cache/neutron
service nova-api restart
service neutron-server restart
service neutron-plugin-openvswitch-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service neutron-l3-agent restart
rm -f /var/lib/neutron/neutron.sqlite
