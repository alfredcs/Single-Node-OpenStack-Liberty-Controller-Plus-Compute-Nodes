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
export OS_TOKEN=$(openssl rand -hex 10)
export OS_URL=http://${controller}:35357/v3
export OS_IDENTITY_API_VERSION=3
export DEBIAN_FRONTEND=noninteractive
debconf-set-selections <<< "mysql-server mysql-server/root_password password ${ADMIN_PASS}"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${ADMIN_PASS}"
apt-get install -y --force-yes mariadb-server mariadb-client \
	rabbitmq-server keystone apache2 libapache2-mod-wsgi memcached python-memcache glance python-glanceclient \
	nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient \
	neutron-server neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent python-neutronclient conntrack \
	openstack-dashboard cinder-api cinder-scheduler python-cinderclient swift swift-proxy python-swiftclient python-keystoneclient python-keystonemiddleware \
	heat-api heat-api-cfn heat-engine python-heatclient \
	ceilometer-api ceilometer-collector ceilometer-agent-central ceilometer-agent-notification ceilometer-alarm-evaluator ceilometer-alarm-notifier python-ceilometerclient \
	ceilometer-agent-compute python-ceilometermiddleware haproxy keepalived mongodb-server mongodb-clients python-pymongo
[[ $? -ne 0 ]] && { echo "pkgs installation failed"; exit 1; }
[[ -f /etc/mysql/my.cnf ]] && mv /etc/mysql/my.cnf /etc/mysql/my.cnf.save
cat >> /etc/mysql/my.cnf << EOF
[client]
port		= 3306
socket		= /var/run/mysqld/mysqld.sock
[mysqld_safe]
socket		= /var/run/mysqld/mysqld.sock
nice		= 0
[mysqld]
user		= mysql
pid-file	= /var/run/mysqld/mysqld.pid
socket		= /var/run/mysqld/mysqld.sock
port		= 3306
basedir		= /usr
datadir		= /var/lib/mysql
tmpdir		= /tmp
lc-messages-dir	= /usr/share/mysql
skip-external-locking
bind-address		= 0.0.0.0
key_buffer		= 16M
max_allowed_packet	= 16M
thread_stack		= 192K
thread_cache_size       = 8
myisam-recover         = BACKUP
query_cache_limit	= 8M
query_cache_size        = 32M
log_error = /var/log/mysql/error.log
expire_logs_days	= 10
max_binlog_size         = 100M
[mysqldump]
quick
quote-names
max_allowed_packet	= 64M
[mysql]
[isamchk]
key_buffer		= 64M
!includedir /etc/mysql/conf.d/
EOF
service mysql restart
[[ -f /etc/keystone/keystone.conf ]] && mv /etc/keystone/keystone.conf /etc/keystone/keystone.conf.save
cat >> /etc/keystone/keystone.conf << EOF
[DEFAULT]
admin_token = ${OS_TOKEN}
debug = true
verbose = true
log_dir = /var/log/keystone
max_token_size = 16384
logging_exception_prefix = %(process)d TRACE %(name)s %(instance)s
logging_debug_format_suffix = %(funcName)s %(pathname)s:%(lineno)d
logging_default_format_string = %(process)d %(levelname)s %(name)s [-] %(instance)s%(message)s
logging_context_format_string = %(process)d %(levelname)s %(name)s [%(request_id)s %(user_identity)s] %(instance)s%(message)s
use_syslog = false
[assignment]
[auth]
[cache]
[catalog]
[cors]
[cors.subdomain]
[credential]
[database]
connection = mysql+pymysql://keystone:${ADMIN_PASS}@${controller}/keystone
[domain_config]
[endpoint_filter]
[endpoint_policy]
[eventlet_server]
public_workers = 4
admin_workers = 4
public_bind_host = 0.0.0.0
public_port = 5000
admin_bind_host = 0.0.0.0
admin_port = 35357
wsgi_keep_alive = true
client_socket_timeout = 900
tcp_keepalive = false
tcp_keepidle = 600
[eventlet_server_ssl]
[federation]
[fernet_tokens]
[identity]
[identity_mapping]
[kvs]
[ldap]
[matchmaker_redis]
[matchmaker_ring]
[memcache]
servers = localhost:11211
[oauth1]
[os_inherit]
[oslo_messaging_amqp]
[oslo_messaging_qpid]
[oslo_messaging_rabbit]
rabbit_host = localhost
rabbit_port = 5672
rabbit_hosts = $rabbit_host:$rabbit_port
rabbit_userid = openstack
rabbit_password = ${ADMIN_PASS}
rabbit_virtual_host = /
rabbit_retry_backoff = 2
[oslo_middleware]
[oslo_policy]
[paste_deploy]
[policy]
[resource]
[revoke]
[role]
[saml]
[signing]
[ssl]
[token]
provider = uuid
driver = memcache
caching = true
[tokenless_auth]
[trust]
[extra_headers]
Distribution = Ubuntu
EOF

[[ -f /etc/apache2/apache2.conf ]] && cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.save
[[ `grep ServerName /etc/apache2/apache2.conf | grep -v ^# |wc -l` -lt 1 ]] && sed -i "/ServerRoot/a ServerName $(hostname)" /etc/apache2/apache2.conf
[[ -f /etc/apache2/sites-available/wsgi-keystone.conf ]] && rm /etc/apache2/sites-available/wsgi-keystone.conf
cat >> /etc/apache2/sites-available/wsgi-keystone.conf << EOF
Listen 5000
Listen 35357

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>
EOF

##
# Prep MySql
##
[[ -f ./openstack_pre.sql ]] && rm -f ./openstack_pre.sql
cat >> ./openstack_pre.sql << EOF
CREATE DATABASE keystone; 
CREATE DATABASE glance;
CREATE DATABASE nova;
CREATE DATABASE neutron;
CREATE DATABASE cinder;
CREATE DATABASE heat;
CREATE DATABASE ceilometer;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON ceilometer.* TO 'ceilometer'@'localhost'  IDENTIFIED BY '${ADMIN_PASS}';

 
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%'  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON ceilometer.* TO 'ceilometer'@'%'  IDENTIFIED BY '${ADMIN_PASS}'
EOF
mysql -u root -p${ADMIN_PASS} < ./openstack_pre.sql
[[ ! -f /etc/apache2/sites-enabled/wsgi-keystone.conf ]] && ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled
su -s /bin/sh -c "keystone-manage db_sync" keystone
service keystone stop
service apache2 restart
[[ -d /etc/keystone ]] && chown -R keystone:root /etc/keystone
openstack user show admin
if [[ $? -ne 0 ]]; then
	openstack service create --name keystone --description "OpenStack Identity" identity
	openstack endpoint create --region RegionOne identity public http://${controller}:5000/v3
	openstack endpoint create --region RegionOne identity internal http://${controller}:5000/v3
	openstack endpoint create --region RegionOne identity admin http://${controller}:35357/v3
	openstack project create --domain default --description "Admin Project" admin
	openstack user create --domain default --password ${ADMIN_PASS} admin
	openstack role create admin
	openstack role create user
	openstack role add --project admin --user admin admin
	openstack project create --domain default --description "Service Project" service
	openstack project create --domain default --description "Demo Project" demo
	openstack user create --domain default --password ${ADMIN_PASS}  demoAdmin
	openstack user create --domain default --password ${ADMIN_PASS} demoUser
	openstack role add --project demoAdmin --user demoAdmin admin
	openstack role add --project demoUser --user demoUser user
fi
[[ -f /root/.adminrc ]] && rm -f /root/.adminrc 
cat >> /root/.adminrc << EOF
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_AUTH_URL=http://${controller}:35357/v3
export OS_IMAGE_API_VERSION=2
export OS_VOLUME_API_VERSION=2
export OS_IDENTITY_API_VERSION=3
EOF

[[ ! -f /root/.adminrc ]] && exit 1
