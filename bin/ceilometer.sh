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

if [[ -f /etc/mongodb.conf ]]; then
	sed -i "/^bind_ip/ s/bind_ip.*$/bind_ip=${controller}/" /etc/mongodb.conf
	[[ `grep ^smallfiles  /etc/mongodb.conf |wc -l` -lt 1 ]] && sed -i '/^bind_ip/a smallfiles=true' /etc/mongodb.conf 
fi
service mongodb stop
rm /var/lib/mongodb/journal/prealloc.*
service mongodb start
sleep 5
mongo --host ${controller} --eval "
  db = db.getSiblingDB('ceilometer');
  db.addUser({user: 'ceilometer',
  pwd: '${ADMIN_PASS}',
  roles: [ 'readWrite', 'dbAdmin' ]})"
#mongo --host liberty1 ceilometer --eval 'db.changeUserPassword("ceilomater", "${ADMIN_PASS}")'

openstack user show ceilometer
if [[ $? -ne 0 ]]; then
	openstack user create --domain default --password ${ADMIN_PASS} ceilometer
	openstack role add --project service --user ceilometer admin
	openstack service create --name ceilometer --description "Telemetry" metering
	openstack endpoint create --region RegionOne metering public http://${controller}:8777
	openstack endpoint create --region RegionOne metering internal http://${controller}:8777
	openstack endpoint create --region RegionOne metering admin http://${controller}:8777
	openstack role create ResellerAdmin
	openstack role add --project service --user ceilometer ResellerAdmin
fi
[[ -f /etc/ceilometer/ceilometer.conf ]] && mv /etc/ceilometer/ceilometer.conf /etc/ceilometer/ceilometer.conf.save
cat >> /etc/ceilometer/ceilometer.conf << EOF
[DEFAULT]
rpc_backend = rabbit
auth_strategy = keystone
verbose = True
debug = True
[database]
connection = mongodb://ceilometer:${ADMIN_PASS}@${controller}:27017/ceilometer
[keystone_authtoken]
auth_uri = http://${controller}:5000
auth_url = http://${controller}:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = ceilometer
password = ${ADMIN_PASS}
[matchmaker_redis]
[matchmaker_ring]
[oslo_concurrency]
[oslo_messaging_amqp]
[oslo_messaging_qpid]
[oslo_messaging_rabbit]
rabbit_host = ${controller}
rabbit_userid = openstack
rabbit_password = ${ADMIN_PASS}
[oslo_policy]
[service_credentials]
os_auth_url = http://${controller}:5000/v2.0
os_username = ceilometer
os_tenant_name = service
os_password = ${ADMIN_PASS}
os_endpoint_type = internalURL
os_region_name = RegionOne
EOF

mkdir -p /var/cache/ceilometer
chwon -R ceilometer:ceilometer /var/cache/ceilometer
service ceilometer-agent-central restart
service ceilometer-agent-notification restart
service ceilometer-api restart
service ceilometer-collector restart
service ceilometer-alarm-evaluator restart
service ceilometer-alarm-notifier restart
service ceilometer-agent-compute restart
service swift-proxy restart
