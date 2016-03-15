#!/bin/bash
[[ "$(id -u)" != 0 ]] && { echo "not root"; exit 0; }
export http_proxy=http://sjc1intproxy01.crd.ge.com:8080
export https_proxy=http://sjc1intproxy01.crd.ge.com:8080
if [[ `cat /etc/lsb-release | grep ^DISTRIB_I| cut -d= -f2` == "Ubuntu" ]]; then
	# Setup
	apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 3B4FE6ACC0B21F32 40976EAF437D05B5 0xcbcb082a1bb943db 5EDB1B62EC4926EA 7FCC7D46ACCC4CF8 C2518248EEA14886 D8576A8BA88D21E9
	DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
	CODENAME=$(lsb_release -cs)

	# Add the repository
	echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/kilo main" | tee /etc/apt/sources.list.d/cloudarchive-kilo.list
	apt-get -y update

	#Install OpenStack Components
	[[ `dpkg -l | grep nova-compute | wc -l` -lt 1 ]] && apt-get -y install openvswitch-switch nova-compute neutron-common neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-metadata-agent cinder-volume ntp
	# update  local  opensatck configuration
	[ `grep ^cinder /etc/sudoers|wc -l` -lt 1 ] && sed -i '/^root\.*/i cinder ALL=(ALL) NOPASSWD:ALL'  /etc/sudoers
	[ `grep ^neutron /etc/sudoers|wc -l` -lt 1 ] && sed -i '/^root\.*/i neutron ALL=(ALL) NOPASSWD:ALL'  /etc/sudoers
	[ `grep 192.168.12.20 | wc -l` -lt 1 ] && echo "server 192.168.12.20" > /etc/ntp.conf
	[ `ovs-vsctl show | grep br-em1|wc -l` -lt 2 ] && ovs-vsctl add-br br-em1 
	[ -f ./compute-node-config.tar ] && tar xpf ./compute-node-config.tar -C /etc
	
	#start ntp and mesos-slave
	#[[ `cat /etc/lsb-release | grep ^DISTRIB_RELEASE |cut -d= -f2` =~ "14.0" ]] && { service ntp restart; service nova-compute restart; service neutron-plugin-openvswitch-agent restart; }
	#[[ `cat /etc/lsb-release | grep ^DISTRIB_RELEASE |cut -d= -f2` =~ "15" ]] && { systemctl resatrt ntp ; systemctl restart nova-computer; systemctl restart neutron-plugin-openvswitch-agent; }
elif [[ `cat /etc/os-release | grep ^PRETTY_NAME|cut -d= -f2` =~ "CentOS" ]]; then
	# Add the repository
	rpm -Uvh http://repos.mesosphere.com/el/7/noarch/RPMS/mesosphere-el-repo-7-3.noarch.rpm
	yum –y update;yum –y upgrade
	yum -y install mesos ntp 
	systemctl stop mesos-master.service
	systemctl disable mesos-master.service
	#Config meoss slave
        echo "zk://10.11.1.19:2181,10.11.1.132:2181,10.11.1.133:2181/mesos" > /etc/mesos/zk
        echo "5mins" > /etc/mesos-slave/executor_registration_timeout
        echo "docker,mesos" > /etc/mesos-slave/containerizers
        echo `uname -n` > /etc/mesos-slave/hostname
        echo "server 192.168.12.20" > /etc/ntp.conf
	echo "CentOS" > /etc/mesos-slave/attributes/os
	# Install Docker daemon on the slave
        [[ ! `docker --version` =~ "1.9.1" ]] && { curl -sSL https://test.docker.com/ | sh; }

	# Update local docker repo certificate
	[[ -f ./devdockerCA.crt ]] && { cp -pf ./devdockerCA.crt /etc/pki/ca-trust/source/anchors/; chown root:root /etc/pki/ca-trust/source/anchors/devdockerCA.crt; }
	[[ -f ./docker.tar/gz ]] && { cp -pf ./docker.tar.gz /etc; chown root:root /etc/docker.tar.gz; }
	update-ca-trust

	systemctl enable docker
	systemctl restart docker
	systemctl enable mesos-slave
	systemctl start mesos-slave
fi

