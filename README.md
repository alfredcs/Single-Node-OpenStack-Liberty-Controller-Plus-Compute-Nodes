Utility to stand up an OpenStack controller node plus multiple compute nodes based on Liberty code release.
The tools were developed adn tested on Ubuntu 14.04 and repository configuration should have approperiate 
entries for trusty packages.

root@liberty3:/etc/apt/sources.list.d# uname -a
Linux liberty3 3.13.0-63-generic #103-Ubuntu SMP Fri Aug 14 21:42:59 UTC 2015 x86_64 x86_64 x86_64 GNU/Linux

root@liberty3:/etc/apt/sources.list.d# more cloudarchive-kilo.list
deb-src http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/liberty main

#./liberty.bsx -a <admin_passsword> -d
