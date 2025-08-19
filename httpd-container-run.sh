#!/bin/sh

# if version is 1.3.x then load slotmem and wstunnel
if grep -q "1\.3\." /mpc_version
then
    sed -i 's|slotmem_shm_module.*modules/mod_slotmem_shm.so|cluster_slotmem_module modules/mod_cluster_slotmem.so|' conf/mod_proxy_cluster.conf
    sed -i '8s|^|LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so\n|' conf/mod_proxy_cluster.conf
    # Use the misspelled variant for 1.3.x versions, because the correct spelling was added in 1.3.21.Final
    # and older versions don't support it (and most likely it's not going away in the 1.3.x stream)
    sed -i 's|EnableMCMPReceive|EnableMCPMReceive|' conf/mod_proxy_cluster.conf
fi

# Include our mod_proxy_cluster.conf
echo "Include conf/mod_proxy_cluster.conf" >> conf/httpd.conf

echo "Starting httpd with $(sed -rn 's|.*\"(.*)\"|\1|p' /mpc_version)..."
bin/apachectl start
tail -f logs/error_log

