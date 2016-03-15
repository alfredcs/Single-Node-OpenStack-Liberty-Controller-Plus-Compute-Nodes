#!/bin/bash
function usage() {
cat <<EOF
usage: $0 options
This script will install Keystone on a Openstack controller
Example:
       	$0 [-a admin_passwd] [-c controller_node] [-r rabbitmq_user] [-p rabbitmq_password] 
OPTIONS:
	-h -- Help Show this message
  	-a -- Nova/Neutron keystone password
  	-c -- Controller node IPs
	-r -- Rabbitmq user name
	-p -- Rabbitmq password
	-d -- Debug flag
EOF
}
[[ `id -u` -ne 0 ]] && { echo  "Must be root!"; exit 0; }
[[ $# -lt 3 ]] && { usage; exit 1; }
my_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
while getopts "a:c:p:r:hd" OPTION; do
case "$OPTION" in
a)
	ADMIN_PASS="$OPTARG"
	;;
c)
        controller="$OPTARG"
        ;;
d)
        DEBUG_FLAG=True
        ;;
r)
        rabbitmq_username="$OPTARG"
        ;;
p)
        rabbitmq_password="$OPTARG"
        ;;
h)
        usage
        exit 0
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

[[ DEBUG_FLAG ]] && set -x

apt-get install -y --force-yes openvswitch-switch nova-compute neutron-common neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-metadata-agent cinder-volume
[[ $? -ne 0 ]] && { echo "pkgs installation failed"; exit 1; }
[[ -f /etc/nova/nova.conf ]] && mv /etc/nova/nova.conf  /etc/nova/nova.conf.save

cat >> /etc/nova/nova.conf << EOF
[DEFAULT]
vif_plugging_timeout = 300
vif_plugging_is_fatal = True
linuxnet_interface_driver =  nova.network.linux_net.LinuxOVSInterfaceDriver
security_group_api = neutron
network_api_class = nova.network.neutronv2.api.API
firewall_driver = nova.virt.firewall.NoopFirewallDriver
compute_driver = libvirt.LibvirtDriver
default_ephemeral_format = ext4
metadata_workers = 2
ec2_workers = 2
osapi_compute_workers = 2
rpc_backend = rabbit
keystone_ec2_url = http://${controller}:5000/v2.0/ec2tokens
novncproxy_base_url = http://${controller}:6080/vnc_auto.html
logging_exception_prefix = %(color)s%(asctime)s.%(msecs)03d TRACE %(name)s [01;35m%(instance)s[00m
logging_debug_format_suffix = [00;33mfrom (pid=%(process)d) %(funcName)s %(pathname)s:%(lineno)d[00m
logging_default_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [[00;36m-%(color)s] [01;35m%(instance)s%(color)s%(message)s[00m
logging_context_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [[01;36m%(request_id)s [00;36m%(user_name)s %(project_name)s%(color)s] [01;35m(instance)s%(color)s%(message)s[00m
force_config_drive = True
instances_path = /var/lib/nova/instances
state_path = /var/lib/nova
enabled_apis = ec2,osapi_compute,metadata
instance_name_template = instance-%08x
my_ip = ${my_ip}
default_floating_pool = public
force_dhcp_release = True
dhcpbridge_flagfile = /etc/nova/nova.conf
scheduler_driver = nova.scheduler.filter_scheduler.FilterScheduler
rootwrap_config = /etc/nova/rootwrap.conf
api_paste_config = /etc/nova/api-paste.ini
allow_resize_to_same_host = True
debug = True
verbose = True
auth_strategy = keystone
instance_usage_audit = True
instance_usage_audit_period = hour
notify_on_state_change = vm_and_task_state
notification_driver = messagingv2
[vnc]
enabled = True
keymap = en-us
vncserver_proxyclient_address = ${controller}
vncserver_listen = 0.0.0.0
xvpvncproxy_base_url = http://${controller}:6081/console
novncproxy_base_url = http://${controller}:6080/vnc_auto.html
[database]
connection = mysql://nova:${ADMIN_PASS}@${controller}/nova?charset=utf8
[osapi_v3]
enabled = True
[keystone_authtoken]
signing_dir = /var/cache/nova
auth_uri = http://${controller}:5000
project_domain_id = default
project_name = service
user_domain_id = default
password = ${ADMIN_PASS}
username = nova
auth_url = http://${controller}:35357
auth_plugin = password
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[spice]
enabled = false
html5proxy_base_url = http://${controller}:6082/spice_auto.html
[oslo_messaging_rabbit]
rabbit_host=${controller}
rabbit_port=5672
rabbit_hosts=${controller}:5672
rabbit_use_ssl=False
rabbit_virtual_host=/
rabbit_ha_queues=False
rabbit_userid=${rabbitmq_username}
rabbit_password=${rabbitmq_password}
volume_api_class=nova.volume.cinder.API
[glance]
api_servers = http://${controller}:9292
host = ${controller}
[cinder]
os_region_name = RegionOne
[libvirt]
vif_driver = nova.virt.libvirt.vif.LibvirtGenericVIFDriver
inject_partition = -2
live_migration_uri = qemu+ssh://vagrant@%s/system
use_usb_tablet = False
cpu_mode = none
virt_type = kvm
[neutron]
service_metadata_proxy = True
url = http://${controller}:9696
region_name = RegionOne
admin_tenant_name = service
auth_strategy = keystone
admin_auth_url = http://${controller}:35357/v2.0
admin_password = ${ADMIN_PASS}
admin_username = neutron
metadata_proxy_shared_secret = neutronsucks
[keymgr]
fixed_key = 586a5a25c28754e2c0bef3fe71b666e5223196e7b73da307ad9b406e6117d5de
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
rabbit_userid = ${rabbitmq_username}
rabbit_password = ${rabbitmq_password}
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
local_ip = ${my_ip}
[agent]
tunnel_types = vxlan
EOF


[[ -f /etc/cinder/cinder.conf ]] && mv -f /etc/cinder/cinder.conf /etc/cinder/cinder.conf.save
cat >> /etc/cinder/cinder.conf << EOF
[keystone_authtoken]
verbose = True
debug = True
signing_dir = /var/cache/cinder
auth_uri = http://${controller}:5000
project_domain_id = default
project_name = service
user_domain_id = default
password = ${ADMIN_PASS}
username = cinder
auth_url = http://${controller}:35357
auth_plugin = password
notification_driver = messagingv2
[DEFAULT]
os_privileged_user_tenant = service
os_privileged_user_password = ${ADMIN_PASS}
os_privileged_user_name = nova
glance_api_servers = http://${controller}:9292
osapi_volume_workers = 2
logging_exception_prefix = %(color)s%(asctime)s.%(msecs)03d TRACE %(name)s ^[[01;35m%(instance)s
logging_debug_format_suffix = ^[[00;33mfrom (pid=%(process)d) %(funcName)s %(pathname)s:%(lineno)d
logging_default_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [^[[00;36m-%(color)s] ^[[01;35m%(instance)s%(color)s%(message)s
logging_context_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [^[[01;36m%(request_id)s ^[[00;36m%(user_id)s %(project_id)s%(color)s] ^[[01;35m%(instance)s%(color)s%(message)s
volume_clear = zero
rpc_backend = rabbit
os_region_name = RegionOne
enable_v1_api = true
periodic_interval = 60
state_path = /var/lock/cinder
osapi_volume_extension = cinder.api.contrib.standard_extensions
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_config = /etc/cinder/api-paste.ini
iscsi_helper = tgtadm
verbose = True
debug = True
auth_strategy = keystone
nova_catalog_admin_info = compute:nova:adminURL
nova_catalog_info = compute:nova:publicURL
nfs_mount_options = nolock
nfs_mount_point_base = /var/lib/cinder/nfs
nfs_shares_config = /etc/cinder/nfsshares
volume_driver = cinder.volume.drivers.nfs.NfsDriver
nfs_mount_attempts = 3
nfs_oversub_ratio = 1.0
nfs_used_ratio = 0.95
my_ip=${my_ip}
[database]
connection = mysql://cinder:${ADMIN_PASS}d@127.0.0.1/cinder?charset=utf8
[oslo_concurrency]
lock_path = /var/lock/cinder
[oslo_messaging_rabbit]
rabbit_host=${controller}
rabbit_port=5672
rabbit_hosts=${controller}:5672
rabbit_use_ssl=False
rabbit_virtual_host=/
rabbit_ha_queues=False
rabbit_userid=${rabbitmq_username}
rabbit_password=${rabbitmq_password}
EOF

[[ `grep  ^neutron /etc/sudoers | wc -l ` -lt 1 ]] && sed -i '/^root/a neutron ALL=(ALL) NOPASSWD:ALL' /etc/sudoers
[[ `grep  ^neutron /etc/sudoers | wc -l ` -lt 1 ]] && sed -i '/^root/a cinder ALL=(ALL) NOPASSWD:ALL' /etc/sudoers
service openvswitch-switch restart
service nova-compute restart
service neutron-plugin-openvswitch-agent restart
service neutron-metadata-agent restart
service cinder-volume restart
