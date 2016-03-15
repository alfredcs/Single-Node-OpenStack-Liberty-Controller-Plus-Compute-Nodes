#!/bin/bash
set -x
function usage() {
cat <<EOF
usage: $0 options
This script will install a single node Openstack controller
Example:
       	$0 [-a admin_passwd] [-c cludter_IP] [-d]
OPTIONS:
  	-h -- Help Show this message
  	-a -- Keystoen service password for nova, neutron, cinder and glance
	-c -- Cluster IP other than the default IP
	-d -- DEbug flag
EOF
}
[[ `id -u` -ne 0 ]] && { echo  "Must be root!"; exit 0; }
[[ $# -lt 2 ]] && { usage; exit 1; }
while getopts "a:c:hd" OPTION; do
case "$OPTION" in
a)
	ADMIN_PASS="$OPTARG"
	;;
c)
        CLUSTER_NODES="$OPTARG"
        ;;
d)
        DEBUG_FLAG=1
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
[[ ! ${ADMIN_PASS} ]] && { echo "Please provide the admin password!"; exit 1; }
CLUSTER_NODES=${CLUSTER_NODES:-$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')}
ADMIN_PASS=${ADMIN_PASS:-$(openssl rand -hex 10)}
dpkg --purge `dpkg -l | egrep 'mongodb|memcached|rabbitmq-server|keystone|mariadb|nova|neutron|heat|ceilometer|cinder|swift|glance'| awk '{print $2}'`
for dirs in memcached rabbitmq mongdb keystone glance mysql nova neutron cinder swift heat ceilometer horison
do
[[ -d /etc/$dirs ]] && rm -rf /etc/$dirs
[[ -d /var/log/$dirs ]] && rm -rf /var/log/$dirs
[[ -d /var/cache/$dirs ]] && rm -rf /var/cache/$dirs
[[ -d /var/lib/$dirs ]] && rm -rf /var/lib/$dirs
done
[[ -f ./keystone.sh ]] && ./keystone.sh -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d ${DEBUG_FLAG}
[[ -f ./glance.sh ]] && ./glance.sh -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d ${DEBUG_FLAG}
[[ -f ./nova.sh ]] && ./nova.sh  -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d${DEBUG_FLAG}
[[ -f ./neutron.sh ]] && ./neutron.sh  -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d ${DEBUG_FLAG}
[[ -f ./horizon.sh ]] && ./horizon.sh  -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d ${DEBUG_FLAG}
[[ -f ./cinder.sh ]] && ./cinder.sh  -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d ${DEBUG_FLAG}
[[ -f ./swift.sh ]] && ./swift.sh  -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d ${DEBUG_FLAG}
[[ -f ./heat.sh ]] && ./heat.sh  -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d ${DEBUG_FLAG}
[[ -f ./ceilometer.sh ]] && ./ceilometer.sh  -a ${ADMIN_PASS} -c ${CLUSTER_NODES} -d ${DEBUG_FLAG}
