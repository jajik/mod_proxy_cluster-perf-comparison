#!/usr/bin/sh

export HTTPD_IMG_1_3=${HTTPD_IMG_1_3:-httpd-mod_proxy_cluster-1.3.x}
export HTTPD_IMG_2_0=${HTTPD_IMG_2_0:-httpd-mod_proxy_cluster-2.x}
export IMG=${IMG:-mod_proxy_cluster-testsuite-tomcat}

echo "Setting up dependencies"

echo -n "Replacing tests from mod_proxy_cluster 1.3.x with tests from 2.x..."
rm -rf mod_cluster-1.3.x/test/
cp -r mod_proxy_cluster/test/ mod_cluster-1.3.x/test/
cp Dockerfile mod_cluster-1.3.x/test/httpd/
sed -i 's|slotmem_shm_module.*modules/mod_slotmem_shm.so|cluster_slotmem_module modules/mod_cluster_slotmem.so|' mod_cluster-1.3.x/test/httpd/mod_proxy_cluster.conf
sed -i '8s|^|LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so\n|' mod_cluster-1.3.x/test/httpd/mod_proxy_cluster.conf
echo " Done"

# Increase MaxNode to 50
echo "Maxnode 50" >> mod_cluster-1.3.x/test/httpd/mod_proxy_cluster.conf
echo "Maxnode 50" >> mod_proxy_cluster/test/httpd/mod_proxy_cluster.conf

# Change tomcat shutdown port to be able to use more than 75 nodes
sed -i 's|8005|8650|' mod_cluster-1.3.x/test/tomcat/server.xml
sed -i 's|8005|8650|' mod_proxy_cluster/test/tomcat/server.xml
# Change the shutdown port in the helper function as well
sed -i 's|8005|8650|g' mod_proxy_cluster/test/includes/common.sh

# Change tomcat_start check that fails if tomcat id is 75 or bigger
sed -i 's|-gt 75|-gt 150|' mod_cluster-1.3.x/test/includes/common.sh
sed -i 's|-gt 75|-gt 150|' mod_proxy_cluster/test/includes/common.sh
# Change Maxcontext to 1500
echo "Maxcontext 150" >> mod_cluster-1.3.x/test/httpd/mod_proxy_cluster.conf
echo "Maxcontext 150" >> mod_proxy_cluster/test/httpd/mod_proxy_cluster.conf

echo -n "Running maven installs... "
for m in httpd_websocket-testsuite/ mod_cluster-testsuite/ mod_proxy_cluster/test/ mod_cluster-1.3.x/test/
do
    cd $m
    mvn install
    if [ $? -ne 0 ]; then
        echo "mvn install failed for $m"
        exit 1
    fi
    cd $OLDPWD
done

echo "Done"

echo -n "Creating httpd and tomcat images..."
# tomcat and httpd with mod_proxy_cluster 2.x
cd mod_proxy_cluster/test/
# load helper functions
. includes/common.sh
# tomcat
tomcat_create
rm -rf httpd/mod_proxy_cluster /tmp/mod_proxy_cluster
mkdir /tmp/mod_proxy_cluster
cp -r ../native ../test /tmp/mod_proxy_cluster/
mv /tmp/mod_proxy_cluster httpd/
docker build -t $HTTPD_IMG_2_0 httpd/

# httpd with mod_proxy_cluster 1.3.x
cd ../..
cd mod_cluster-1.3.x/test/
rm -rf /tmp/mod_proxy_cluster
mkdir /tmp/mod_proxy_cluster/
cp -r ../native ../test /tmp/mod_proxy_cluster
cp -r /tmp/mod_proxy_cluster httpd/
docker build -t $HTTPD_IMG_1_3 httpd/
cd ../..

echo "Done"

