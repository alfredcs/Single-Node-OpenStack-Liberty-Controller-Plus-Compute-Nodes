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
T_ZONE=$(cat  /etc/timezone)
[[ -f /root/.adminrc ]] && source  /root/.adminrc
openstack user create --domain default --password ${ADMIN_PASS} cinder
openstack role add --project service --user cinder admin
openstack service create --name cinder  --description "OpenStack Block Storage" volume
openstack service create --name cinderv2  --description "OpenStack Block Storage" volumev2
openstack endpoint create --region RegionOne  volume public http://${controller}:8776/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne  volume internal http://${controller}:8776/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne  volume admin http://${controller}:8776/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne volumev2 public http://${controller}:8776/v2/%\(tenant_id\)s
openstack endpoint create --region RegionOne volumev2 internal http://${controller}:8776/v2/%\(tenant_id\)s
openstack endpoint create --region RegionOne volumev2 admin http://${controller}:8776/v2/%\(tenant_id\)s

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
my_ip=${controller}
notification_driver = messagingv2
[database]
connection = mysql://cinder:${ADMIN_PASS}@127.0.0.1/cinder?charset=utf8
[oslo_concurrency]
lock_path = /var/lock/cinder
[oslo_messaging_rabbit]
rabbit_host=${controller}
rabbit_port=5672
rabbit_hosts=${controller}:5672
rabbit_use_ssl=False
rabbit_virtual_host=/
rabbit_ha_queues=False
rabbit_userid=openstack
rabbit_password=${ADMIN_PASS}
EOF

su -s /bin/sh -c "cinder-manage db sync" cinder
mkdir -p /var/cache/cinder
chown -R cinder:cinder /var/cache/cinder
[[ `grep  ^cinder /etc/sudoers | wc -l ` -lt 1 ]] && sed -i '/^root/a cinder ALL=(ALL) NOPASSWD:ALL' /etc/sudoers
service nova-api restart
service cinder-scheduler restart
service cinder-api restart
rm -f /var/lib/cinder/cinder.sqlite
