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
openstack user show nova
if [[ $? -ne 0 ]]; then
	openstack user create --domain default --password ${ADMIN_PASS} nova
	openstack role add --project service --user nova admin
	openstack role add --project service --user nova admin
	openstack service create --name nova --description "OpenStack Compute" compute
	openstack endpoint create --region RegionOne  compute public http://${controller}:8774/v2/%\(tenant_id\)s
	openstack endpoint create --region RegionOne  compute internal http://${controller}:8774/v2/%\(tenant_id\)s
	openstack endpoint create --region RegionOne  compute admin http://${controller}:8774/v2/%\(tenant_id\)s
fi
[[ -f /etc/nova/nova.conf ]] && mv -f /etc/nova/nova.conf /etc/nova/nova.conf.saved
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
my_ip = ${controller}
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
rabbit_userid=openstack
rabbit_password=${ADMIN_PASS}
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

su -s /bin/sh -c "nova-manage db sync" nova
[[ ! -d /var/cache/nova ]] && mkdir -p /var/cache/nova
chown -R nova:nova /var/cache/nova
service nova-api restart
service nova-cert restart
service nova-consoleauth restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart
rm -f /var/lib/nova/nova.sqlite
