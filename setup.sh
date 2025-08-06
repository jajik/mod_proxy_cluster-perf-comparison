#!/usr/bin/sh

export HTTPD_IMG_1_3=${HTTPD_IMG_1_3:-httpd-mod_proxy_cluster-1.3.x}
export HTTPD_IMG_2_0=${HTTPD_IMG_2_0:-httpd-mod_proxy_cluster-2.x}
export IMG=${IMG:-mod_proxy_cluster-testsuite-tomcat}

echo "Setting up dependencies"

echo -n "Replacing tests from mod_proxy_cluster 1.3.x with tests from 2.x..."
rm -rf mod_cluster-1.3.x/test/
cp -r mod_proxy_cluster/test/ mod_cluster-1.3.x/test/
cp Containerfile mod_cluster-1.3.x/test/httpd/

sed -i 's|slotmem_shm_module.*modules/mod_slotmem_shm.so|cluster_slotmem_module modules/mod_cluster_slotmem.so|' mod_cluster-1.3.x/test/httpd/mod_proxy_cluster.conf
sed -i '8s|^|LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so\n|' mod_cluster-1.3.x/test/httpd/mod_proxy_cluster.conf
echo " Done"

# Increase MaxNode to 50
for conf_file in mod_proxy_cluster/test/httpd/mod_proxy_cluster.conf mod_cluster-1.3.x/test/httpd/mod_proxy_cluster.conf
do
    echo "Maxnode 50"          >> $conf_file
    echo "ServerLimit 32"      >> $conf_file
    echo "StartServers 8"      >> $conf_file
    echo "MaxKeepAliveRequests 0" >> $conf_file
    if [ $HTTPD_LOG_LEVEL ]; then
        echo "Setting log level to $HTTPD_LOG_LEVEL"
        echo "LogLevel $HTTPD_LOG_LEVEL" >> $conf_file
    fi
done

echo -n "Running maven installs... "
for m in httpd_websocket-testsuite/ mod_cluster-testsuite/ mod_proxy_cluster/test/ mod_cluster-1.3.x/test/ demo-webapp/
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
# First we'll change the default tomcat port from 8080 to 9000 so that we avoid conflicts
# with the mod_proxy_cluster's port 8090 in case of 10 or more tomcat containers...
sed -i -e 's/8080/9000/g' mod_proxy_cluster/test/includes/common.sh
sed -i -e 's/8080/9000/g' mod_proxy_cluster/test/tomcat/server.xml

# tomcat and httpd with mod_proxy_cluster 2.x
cd mod_proxy_cluster/test/
# load helper functions
. includes/common.sh
# tomcat
tomcat_create
if [ $? -ne 0 ]; then
    echo "Error occurred during tomcat image creation"
    exit 1
fi

rm -rf httpd/mod_proxy_cluster /tmp/mod_proxy_cluster
mkdir /tmp/mod_proxy_cluster
cp -r ../native ../test /tmp/mod_proxy_cluster/
mv /tmp/mod_proxy_cluster httpd/
docker build -t $HTTPD_IMG_2_0 -f httpd/Containerfile httpd/
if [ $? -ne 0 ]; then
    echo "Error occurred during $HTTPD_IMG_2_0 creation"
    exit 1
fi

# httpd with mod_proxy_cluster 1.3.x
cd ../..
cd mod_cluster-1.3.x/test/
rm -rf /tmp/mod_proxy_cluster
mkdir /tmp/mod_proxy_cluster/
cp -r ../native ../test /tmp/mod_proxy_cluster
cp -r /tmp/mod_proxy_cluster httpd/
docker build -t $HTTPD_IMG_1_3 -f httpd/Containerfile httpd/
if [ $? -ne 0 ]; then
    echo "Error occurred during $HTTPD_IMG_1_3 creation"
    exit 1
fi
cd ../..

cd client
cmake . && make
if [ $? -ne 0 ]; then
    echo "client compilation failed"
    exit 1
fi
cd ..

echo "Done"

