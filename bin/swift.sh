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

openstack user show swift 
if [[ $? -ne 0 ]]; then
	openstack user create --domain default --password ${ADMIN_PASS} swift
	 openstack role add --project service --user swift admin
	openstack service create --name swift --description "OpenStack Object Storage" object-store
	openstack endpoint create --region RegionOne object-store public http://${controller}:8080/v1/AUTH_%\(tenant_id\)s
	openstack endpoint create --region RegionOne object-store internal http://${controller}:8080/v1/AUTH_%\(tenant_id\)s
	openstack endpoint create --region RegionOne object-store admin http://${controller}:8080/v1/AUTH_%\(tenant_id\)s
fi
[[ ! -d /etc/swift  ]] && mkdir -p /etc/swift
#curl -o /etc/swift/proxy-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/liberty
cat >> /etc/swift/proxy-server.conf << EOF
[DEFAULT]
bind_ip = 0.0.0.0
bind_port = 8080
swift_dir = /etc/swift
user = swift
[pipeline:main]
pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk tempurl ratelimit tempauth container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server
[app:proxy-server]
use = egg:swift#proxy
account_autocreate = true
[filter:tempauth]
use = egg:swift#tempauth
user_admin_admin = admin .admin .reseller_admin
user_test_tester = testing .admin
user_test2_tester2 = testing2 .admin
user_test_tester3 = testing3
user_test5_tester5 = testing5 service
[filter:authtoken]
paste.filter_factory = keystonemiddleware.auth_token:filter_factory
auth_uri = http://${controller}:5000
auth_url = http://${controller}:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = swift
password = ${ADMIN_PASS}
delay_auth_decision = true
[filter:keystoneauth]
use = egg:swift#keystoneauth
operator_roles = admin, user, ResellerAdmin
[filter:healthcheck]
use = egg:swift#healthcheck
[filter:ceilometer]
paste.filter_factory = ceilometermiddleware.swift:filter_factory
control_exchange = swift
url = rabbit://openstack:${ADMIN_PASS}@${controller}:5672/
driver = messagingv2
topic = notifications
log_level = WARN
[filter:cache]
use = egg:swift#memcache
memcache_servers = 127.0.0.1:11211
[filter:ratelimit]
use = egg:swift#ratelimit
[filter:domain_remap]
use = egg:swift#domain_remap
[filter:catch_errors]
use = egg:swift#catch_errors
[filter:cname_lookup]
use = egg:swift#cname_lookup
[filter:staticweb]
use = egg:swift#staticweb
[filter:tempurl]
use = egg:swift#tempurl
[filter:formpost]
use = egg:swift#formpost
[filter:name_check]
use = egg:swift#name_check
[filter:list-endpoints]
use = egg:swift#list_endpoints
[filter:proxy-logging]
use = egg:swift#proxy_logging
[filter:bulk]
use = egg:swift#bulk
[filter:slo]
use = egg:swift#slo
[filter:dlo]
use = egg:swift#dlo
[filter:container-quotas]
use = egg:swift#container_quotas
[filter:account-quotas]
use = egg:swift#account_quotas
[filter:gatekeeper]
use = egg:swift#gatekeeper
[filter:container_sync]
use = egg:swift#container_sync
[filter:xprofile]
use = egg:swift#xprofile
[filter:versioned_writes]
use = egg:swift#versioned_writes
EOF

[[ -f /etc/swift/swift.conf ]] && mv /etc/swift/swift.conf /etc/swift/swift.conf.save
#curl -o /etc/swift/swift.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/swift.conf-sample?h=stable/liberty
cat >> /etc/swift/swift.conf << EOF
[swift-hash]
swift_hash_path_suffix = suf_${ADMIN_PASS}
swift_hash_path_prefix = pre_${ADMIN_PASS}
[storage-policy:0]
name = Policy-0
default = yes
[swift-constraints]
EOF
chown -R root:swift /etc/swift
cd /etc/swift
if [[ ! -f /etc/swift/account.ring.gz ]]; then
	swift-ring-builder account.builder create 10 3 1
	swift-ring-builder account.builder add --region 1 --zone 1 --ip 10.11.2.200 --port 6002 --device sdb --weight 100
	swift-ring-builder account.builder add --region 1 --zone 2 --ip 10.11.2.200 --port 6002 --device sdc --weight 100
	swift-ring-builder account.builder
	swift-ring-builder account.builder rebalance
fi
if [[ ! -f /etc/swift/container.ring.gz ]]; then
	swift-ring-builder container.builder create 10 3 1
	swift-ring-builder container.builder add  --region 1 --zone 1 --ip 10.11.2.200 --port 6001 --device sdb --weight 100
	swift-ring-builder container.builder 
	swift-ring-builder container.builder rebalance
fi
if [[ ! -f /etc/swift/object.ring.gz ]]; then
	swift-ring-builder object.builder create 10 3 1
	swift-ring-builder object.builder --region 1 --zone 1 --ip 10.11.2.200 --port 6000 --device sdb --weight 100
	swift-ring-builder object.builder add --region 1 --zone 1 --ip 10.11.2.200 --port 6000 --device sdb --weight 100
	swift-ring-builder object.builder
	swift-ring-builder object.builder rebalance
fi
#service memcached restart
service swift-proxy restart
