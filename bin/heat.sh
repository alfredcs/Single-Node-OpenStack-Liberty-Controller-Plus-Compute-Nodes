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

openstack user show heat
if [[ $? -ne 0 ]]; then
	openstack user create --domain default --password ${ADMIN_PASS}  heat
	[[ $? -ne 0 ]] && { echo "Failed to create new user heat"; exit 1; }
	openstack role add --project service --user heat admin
	openstack user create --domain heat --password ${ADMIN_PASS} heat_domain_admin
	openstack role add --domain heat --user heat_domain_admin admin
	openstack role create heat_stack_owner
	openstack role add --project demo --user demoAdmin heat_stack_owner
	openstack role create heat_stack_user
	openstack role add --project demo --user demoUser heat_stack_user
fi
openstack service show heat
[[ $? -ne 0 ]] && { openstack service create --name heat --description "Orchestration" orchestration; openstack service create --name heat-cfn --description "Orchestration" cloudformation; }
if [[ `openstack endpoint list| grep heat|wc -l` -lt 1 ]]; then
	openstack endpoint create --region RegionOne orchestration public http://${controller}:8004/v1/%\(tenant_id\)s
	openstack endpoint create --region RegionOne orchestration internal http://${controller}:8004/v1/%\(tenant_id\)s
	openstack endpoint create --region RegionOne orchestration admin http://${controller}:8004/v1/%\(tenant_id\)s
	openstack endpoint create --region RegionOne  cloudformation public http://${controller}:8000/v1
	openstack endpoint create --region RegionOne  cloudformation internal http://${controller}:8000/v1
	openstack endpoint create --region RegionOne  cloudformation admin http://${controller}:8000/v1
	openstack domain create --description "Stack projects and users" heat
fi
[[ -f /etc/heat/heat.conf  ]] && mv /etc/heat/heat.conf  /etc/heat/heat.conf.save
cat >> /etc/heat/heat.conf  << EOF
[DEFAULT]
heat_metadata_server_url = http://${controller}:8000/
heat_waitcondition_server_url = http://${controller}:8000/v1/waitcondition
stack_domain_admin = heat_domain_admin
stack_domain_admin_password = ${ADMIN_PASS}
stack_user_domain_name = heat
#stack_user_domain_id=fba8dc765b214dc998e0500c58749b5a
debug = True
verbose = True
rpc_backend = rabbit
[database]
connection = mysql://heat:${ADMIN_PASS}@${controller}/heat
[keystone_authtoken]
auth_uri = http://${controller}:5000
auth_url = http://${controller}:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = heat
password = ${ADMIN_PASS}
#[trustee]
#auth_plugin = password
#auth_url = http://${controller}:35357
#username = heat
#password = ${ADMIN_PASS}
#user_domain_id = default
#[clients_keystone]
#auth_uri = http://${controller}:5000
#[ec2authtoken]
#auth_uri = http://${controller}:5000
[matchmaker_redis]
[matchmaker_ring]
[oslo_messaging_amqp]
[oslo_messaging_qpid]
[oslo_messaging_rabbit]
rabbit_host = ${controller}
rabbit_port=5672
rabbit_hosts=${controller}:5672
rabbit_use_ssl=False
rabbit_virtual_host=/
rabbit_ha_queues=False
rabbit_userid=openstack
rabbit_password=${ADMIN_PASS}
EOF
su -s /bin/sh -c "heat-manage db_sync" heat
mkdir -p /var/cache/heat
chown -R heat:heat /var/cache/heat
service heat-api restart
service heat-api-cfn restart
service heat-engine restart
rm -f /var/lib/heat/heat.sqlite
