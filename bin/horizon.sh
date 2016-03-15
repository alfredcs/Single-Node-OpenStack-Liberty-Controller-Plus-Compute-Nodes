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

if [[ -f /etc/openstack-dashboard/local_settings.py ]]; then
	sed -i "/^OPENSTACK_HOST/ s/127.0.0.1/${controller}/" /etc/openstack-dashboard/local_settings.py
	sed -i "/^ALLOWED_HOSTS/ s/ALLOWED_HOSTS.*$/ALLOWED_HOSTS = ['*', ]/" /etc/openstack-dashboard/local_settings.py
	sed -i "/^OPENSTACK_KEYSTONE_DEFAULT_ROLE/ s/_member_/user/" /etc/openstack-dashboard/local_settings.py
	sed -i "/^TIME_ZONE/ s/UTC/${T_ZONE}/" /etc/openstack-dashboard/local_settings.py
	sed -i "/^#OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT/ s/#OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT.*$/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True/" /etc/openstack-dashboard/local_settings.py
fi

service apache2 reload
