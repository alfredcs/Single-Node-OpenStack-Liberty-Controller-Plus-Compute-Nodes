#!/bin/bash
[[ "$(id -u)" != 0 ]] && { echo "not root"; exit 0; }
export http_proxy=http://sjc1intproxy01.crd.ge.com:8080
export https_proxy=http://sjc1intproxy01.crd.ge.com:8080
if [[ `cat /etc/lsb-release | grep ^DISTRIB_I| cut -d= -f2` == "Ubuntu" ]]; then
	# Setup
	apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF
	DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
	CODENAME=$(lsb_release -cs)

	# Add the repository
	echo "deb http://repos.mesosphere.com/${DISTRO} ${CODENAME} main" | tee /etc/apt/sources.list.d/mesosphere.list
	apt-get -y update

	#Install Mesos
	[[ `dpkg -l | grep mesos | wc -l` -lt 1 ]] && apt-get -y install mesos ntp
	service zookeeper stop
	sh -c "echo manual > /etc/init/zookeeper.override"
	service stop mesos-master
	sh -c "echo manual > /etc/init/mesos-master.override"

	#Config meoss slave
	echo "zk://10.11.1.19:2181,10.11.1.132:2181,10.11.1.133:2181/mesos" > /etc/mesos/zk
	echo "5mins" > /etc/mesos-slave/executor_registration_timeout
	echo "docker,mesos" > /etc/mesos-slave/containerizers
	echo `uname -n` > /etc/mesos-slave/hostname
	echo "server 192.168.12.20" > /etc/ntp.conf
	echo "Ubuntu" > /etc/mesos-slave/attributes/os
	# Install Docker daemon on the slave
	 [[ ! `docker --version` =~ "1.9.1" ]] && { curl -sSL https://test.docker.com/ | sh; }
	# update  local docker repo certificate
	[[ -f ./devdockerCA.crt ]] && { cp -pf ./devdockerCA.crt /usr/local/share/ca-certificates/devdockerCA.crt; chown root:root /usr/local/share/ca-certificates/devdockerCA.crt; }
	[[ ! -f /etc/ssl/certs/devdockerCA.crt ]] && ln -s /usr/local/share/ca-certificates/devdockerCA.crt /etc/ssl/certs/devdockerCA.pem
	[[ -f ./docker.tar/gz ]] && { cp -pf ./docker.tar.gz /etc; chown root:root /etc/docker.tar.gz; }
	update-ca-certificates

	#start ntp and mesos-slave
	[[ `cat /etc/lsb-release | grep ^DISTRIB_RELEASE |cut -d= -f2` =~ "14.0" ]] && { service ntp restart; service docker restart; service mesos-slave restart; }
	[[ `cat /etc/lsb-release | grep ^DISTRIB_RELEASE |cut -d= -f2` =~ "15" ]] && { systemctl resatrt ntp ; systemctl restart docker; systemctl restart mesos-slave; }
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

