#!/bin/sh
export ZK_HOME=zk://10.11.1.90:2181,10.11.1.91:2181,10.11.1.92:2181
curl -sSL http://repo/install_mesos_slave.sh  | bash
