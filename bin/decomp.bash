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

echo ""
echo "Install a single node openstack controller based on liberty code release"
echo ""
[[ `id -u` -ne 0 ]] && { echo  "Must be root!"; exit 0; }
[[ $# -lt 2 ]] && { usage; exit 1; }
export TMPDIR=`mktemp -d /tmp/liberty_ctrl_inst.XXXXXX`
ARCHIVE=`awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit 0; }' $0`
tail -n+$ARCHIVE $0 | tar xzv -C $TMPDIR
CDIR=`pwd`
cd $TMPDIR
[[ -f ./liberty_controller.sh ]] && ./liberty_controller.sh $@
cd $CDIR
rm -rf $TMPDIR
exit 0
__ARCHIVE_BELOW__
