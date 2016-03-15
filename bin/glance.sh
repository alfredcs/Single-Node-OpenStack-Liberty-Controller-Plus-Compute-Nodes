#!/bin/bash
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
openstack user show glance
if [[ $? -ne 0 ]]; then
	openstack user create --domain default --password ${ADMIN_PASS} glance
	openstack role add --project service --user glance admin
	openstack service create --name glance  --description "OpenStack Image service" image
	openstack endpoint create --region RegionOne image public http://${controller}:9292
	openstack endpoint create --region RegionOne image internal http://${controller}:9292
	openstack endpoint create --region RegionOne image admin http://${controller}:9292
fi
mv /etc/glance/glance-api.conf /etc/glance/glance-api.conf.orig
cat >> /etc/glance/glance-api.conf << EOF
[DEFAULT]
debug = True
verbose= True
logging_exception_prefix = %(color)s%(asctime)s.%(msecs)03d TRACE %(name)s [01;35m%(instance)s[00m
logging_debug_format_suffix = [00;33mfrom (pid=%(process)d) %(funcName)s %(pathname)s:%(lineno)d[00m
logging_default_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [[00;36m-%(color)s] [01;35m%(instance)s%(color)s%(message)s[00m
logging_context_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [[01;36m%(request_id)s [00;36m%(user)s %(tenant)s%(color)s] [01;35m%(instance)%(color)s%(message)s[00m
workers = 2
rpc_backend = rabbit
notification_driver = messagingv2
use_syslog = False
bind_host = ${controller}
bind_port = 9292
backlog = 4096
registry_host = ${controller}
registry_port = 9191
registry_client_protocol = http
rabbit_host = localhost
rabbit_port = 5672
rabbit_use_ssl = false
rabbit_userid = openstack
rabbit_password = ${ADMIN_PASS}
rabbit_virtual_host = /
rabbit_notification_exchange = glance
rabbit_notification_topic = notifications
rabbit_durable_queues = False
delayed_delete = False
scrub_time = 43200
scrubber_datadir = /var/lib/glance/scrubber
image_cache_dir = /var/lib/glance/cache/
[oslo_policy]
[database]
connection = mysql://glance:${ADMIN_PASS}@${controller}/glance?charset=utf8
[oslo_concurrency]
[keystone_authtoken]
auth_host = ${controller}
auth_protocol = http
signing_dir = /var/cache/glance/api
auth_uri = http://${controller}:5000
project_domain_id = default
project_name = service
user_domain_id = default
password = ${ADMIN_PASS}
username = glance
auth_url = http://${controller}:35357
auth_plugin = password
identity_uri = http://${controller}:35357
admin_tenant_name = admin
admin_user = admin
admin_password = ${ADMIN_PASS}
revocation_cache_time = 10
[paste_deploy]
flavor = keystone
[store_type_location_strategy]
[profiler]
[task]
[taskflow_executor]
[glance_store]
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
[oslo_messaging_rabbit]
rabbit_userid = openstack
rabbit_password = ${ADMIN_PASS}
rabbit_hosts = ${controller}

EOF
if [[ `rabbitmqctl list_users | grep openstack|wc -l` -lt 1 ]]; then
	rabbitmqctl add_user openstack ${ADMIN_PASS}
	rabbitmqctl set_permissions -p / openstack read write conf
	rabbitmqctl set_user_tags openstack administrator
fi

mv /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.save
cat >> /etc/glance/glance-registry.conf << EOF
[DEFAULT]
debug = True
verbose = True
logging_exception_prefix = %(color)s%(asctime)s.%(msecs)03d TRACE %(name)s [01;35m%(instance)s[00m
logging_debug_format_suffix = [00;33mfrom (pid=%(process)d) %(funcName)s %(pathname)s:%(lineno)d[00m
logging_default_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [[00;36m-%(color)s] [01;35m%(instance)s%(color)s%(message)s[00m
logging_context_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [[01;36m%(request_id)s [00;36m%(user)s %(tenant)s%(color)s] [01;35m%(instance)%(color)s%(message)s[00m
rpc_backend = rabbit
notification_driver = messagingv2
workers = 2
use_syslog = False
bind_host = ${controller}
bind_port = 9191
backlog = 4096
api_limit_max = 1000
limit_param_default = 25
rabbit_host = localhost
rabbit_port = 5672
rabbit_use_ssl = false
rabbit_userid = openstack
rabbit_password = ${ADMIN_PASS}
rabbit_virtual_host = /
rabbit_notification_exchange = glance
rabbit_notification_topic = notifications
rabbit_durable_queues = False
[oslo_policy]
[database]
connection = mysql://glance:${ADMIN_PASS}@${controller}/glance?charset=utf8
[keystone_authtoken]
auth_host = ${controller}
auth_protocol = http
signing_dir = /var/cache/glance/registry
auth_uri = http://${controller}:5000
project_domain_id = default
project_name = service
user_domain_id = default
password = ${ADMIN_PASS}
username = glance
auth_url = http://${controller}:35357
auth_plugin = password
identity_uri = http://${controller}:35357
admin_tenant_name = admin
admin_user = admin
admin_password = ${ADMIN_PASS}
[paste_deploy]
flavor = keystone
[profiler]
[oslo_messaging_rabbit]
rabbit_userid = openstack
rabbit_password = ${ADMIN_PASS}
rabbit_hosts = ${controller}
EOF

[[ -f /etc/rabbitmq/rabbitmq.config ]] && mv /etc/rabbitmq/rabbitmq.config /etc/rabbitmq/rabbitmq.config.saved
cat >> /etc/rabbitmq/rabbitmq.config << EOF
[
 {rabbit, [ 
 	{tcp_listeners, [5672]},
	{loopback_users, []},
 	{collect_statistics_interval, 10000},
        {channel_max,5000},
 	{rabbitmq_management, [ {http_log_dir,"/tmp/rabbit-mgmt"},{listener, [{port, 8080}]} ] },
        {vm_memory_high_watermark, 0.4},
        {disk_free_limit,100000000},
        {log_levels,[{connection, info},{mirroring, info}]},
        {delegate_count,32},
        {tcp_listen_options,
          [binary,
        	{packet, raw},
                {reuseaddr, true},
                {backlog, 128},
                {nodelay, true},
                {exit_on_close, false},
                {keepalive, true}
          ]
        },
        {collect_statistics_interval, 60000},
 	{rabbitmq_management_agent, [ {force_fine_statistics, true} ] }
 ]},
 {kernel, [{net_ticktime,  30}]}
].
EOF
service rabbitmq-server restart
rabbitmqctl add_user openstack ${ADMIN_PASS}
rabbitmqctl set_permissions -p / openstack ".*" ".*" ".*"
su -s /bin/sh -c "glance-manage db_sync" glance
mkdir -p /var/cache/glance
chown -R glance:glance /var/cache/glance
service glance-registry restart
service glance-api restart
rm -f /var/lib/glance/glance.sqlite
