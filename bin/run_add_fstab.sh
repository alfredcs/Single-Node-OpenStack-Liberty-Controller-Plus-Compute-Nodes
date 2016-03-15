[[ `grep cassandra  /etc/fstab|wc -l` -lt 1 ]] && echo '192.168.12.24:/opt/cassandra /opt/cassandra  nfs rw,soft,intr 0 0' >> /etc/fstab
