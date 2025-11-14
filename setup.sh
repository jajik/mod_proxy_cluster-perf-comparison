#!/usr/bin/sh

# we'll build the tomcat image under our own name
export IMG=${IMG:-mpc-perfsuite-tomcat}

echo "Setting up dependencies"

# First build all the dependencies,
# then go through all mod_proxy_cluster* directories
# and build a container image for each of them

#############################
####  M I S C   A P P S  ####
#############################
# Maven installs for the applications used there
echo -n "Running maven installs... "
for m in ci.modcluster.io/websocket-hello/ mod_cluster-testsuite/ demo-webapp/
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

###########################
####    T O M C A T    ####
###########################
# Create a tomcat container from the mod_proxy_cluster upstream testsuite
echo -n "Creating httpd and tomcat images... "
# First we'll change the default tomcat port from 8080 to 9000 so that we avoid conflicts
# with the mod_proxy_cluster's port 8090 in case of 10 or more tomcat containers...
cd mod_proxy_cluster/test/
sh setup-dependencies.sh
sed -i -e 's/8080/9000/g' includes/common.sh
sed -i -e 's/8080/9000/g' tomcat/server.xml
# load helper functions
. includes/common.sh
tomcat_create
if [ $? -ne 0 ]; then
    echo "Error occurred during tomcat image creation"
    exit 1
fi
cd $OLDPWD
echo "Done"

###########################
####    C L I E N T    ####
###########################
echo -n "Compiling a client application... "
cd client
cmake . && make
if [ $? -ne 0 ]; then
    echo "client compilation failed"
    exit 1
fi
cd $OLDPWD
echo "Done"

###########################
###  MOD_PROXY_CLUSTER  ###
###########################
echo "Creating an httpd with mod_proxy_cluster container images from all directories found"
# create a temporary directory in which we'll build the container images
mkdir -p .tempdir
cp Containerfile mod_proxy_cluster.conf httpd-container-run.sh .tempdir/
# set a custom log level if requested
if [ $HTTPD_LOG_LEVEL ]; then
    echo "Setting log level to $HTTPD_LOG_LEVEL"
    echo "LogLevel $HTTPD_LOG_LEVEL" >> .tempdir/mod_proxy_cluster.conf
fi
# now create all the containers
for dir in mod_proxy_cluster*/
do
    cp -r $dir/native .tempdir/
    cd .tempdir
    # \L makes sure the version is lowercase – docker requirement
    version=$(echo $dir | sed -rn 's|mod_proxy_cluster-(.*)/|\L\1|p')
    # if version is empty, it's our `mod_proxy_cluster` == 2.x version
    version=${version:-2.x}
    containername="mpc-perfsuite-mod_proxy_cluster-$version"
    docker build -t $containername  -f Containerfile .
    if [ $? -ne 0 ]; then
        echo "Compilation of mod_proxy_cluster in $dir failed!"
        exit 1;
    fi
    echo "    - $containername built from $dir"
    cd $OLDPWD
done
rm -rf .tempdir
echo "Done"

