CREATE DATABASE keystone; 
CREATE DATABASE glance;
CREATE DATABASE nova;
CREATE DATABASE neutron;
CREATE DATABASE cinder;
CREATE DATABASE heat;
CREATE DATABASE ceilometer;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON ceilometer.* TO 'ceilometer'@'localhost'  IDENTIFIED BY 'passwd123';

 
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%'  IDENTIFIED BY 'passwd123';
GRANT ALL PRIVILEGES ON ceilometer.* TO 'ceilometer'@'%'  IDENTIFIED BY 'passwd123'
