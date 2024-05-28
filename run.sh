#!/usr/bin/sh

HTTPD_IMG_1_3=${HTTPD_IMG_1_3:-httpd-mod_proxy_cluster-1.3.x}
HTTPD_IMG_2_0=${HTTPD_IMG_2_0:-httpd-mod_proxy_cluster-2.x}
IMG=${IMG:-mod_proxy_cluster-testsuite-tomcat}

TOMCAT_COUNT=${TOMCAT_COUNT:-2}
CONC_COUNT=${CONC_COUNT:-100}
REQ_COUNT=${REQ_COUNT:-1000000}
REPETITIONS=${REPETITIONS:-10}

echo "Running with following options:"
echo "                  TOMCAT_COUNT=$TOMCAT_COUNT"
echo "                  CONC_COUNT=$CONC_COUNT"
echo "                  REQ_COUNT=$REQ_COUNT"
echo "                  REPETITIONS=$REPETITIONS"
echo "                  SHUTDOWN_RANDOMLY=${SHUTDOWN_RANDOMLY:-0}"

. mod_proxy_cluster/test/includes/common.sh

get_output_folder() {
    if [ "$1" = $HTTPD_IMG_1_3 ]; then
        echo "output/1.3/"
    else
        echo "output/2.0/"
    fi
}

tomcat_upload_contexts() {
    if [ -z "$1" ]; then
        echo "tomcat_upload_contexts got no argument"
        exit 1
    fi

    # here you should specify all contexts for each node
    docker cp mod_proxy_cluster/test/testapp tomcat$1:/usr/local/tomcat/webapps/legacy
    docker cp tomcat-openshift/demo-webapp/target/demo-1.0.war tomcat$1:/usr/local/tomcat/webapps/
    docker cp mod_proxy_cluster/test/testapp tomcat$1:/usr/local/tomcat/webapps/stub
}

# $1 equals to number of ciphers
random_number() {
    expr $(tr -cd 0-9 < /dev/random | head -c${1:-2}) + 0
}

shutdown_tomcats_randomly() {
    ciphers=$(expr length "$TOMCAT_COUNT")
    while true; do
        rn=$(random_number $ciphers)
        i=$(expr $rn % $TOMCAT_COUNT + 1)
        seed=$(random_number 2)
        tomcat_shutdown $i
        sleep $(expr 10 + $seed)
        tomcat_remove $i > /dev/null 2>&1
        tomcat_start $i  > /dev/null 2>&1
        sleep 10
        tomcat_upload_contexts $i > /dev/null 2>&1
        echo "tomcat$i is back online"
        sleep $seed
    done
}

run_abtest_for() {
    if [ -z "$1" ]; then
        echo "run_abtest_for requires httpd container name"
        exit 1
    fi
    # start httpd
    HTTPD_IMG=$1 httpd_run

    # start tomcats
    for i in $(seq 1 $TOMCAT_COUNT)
    do
        tomcat_start $i
    done

    sleep 1

    for i in $(seq 1 $TOMCAT_COUNT)
    do
        # add multiple contexts but use the same app
        tomcat_upload_contexts $i
    done

    # let everything settle...
    sleep 120

    for i in $(seq 1 $SHUTDOWN_RANDOMLY);
    do
        shutdown_tomcats_randomly $TOMCAT_COUNT &
        # save the spawn process id into $@ variable
        pid=$!
        echo "tomcats will be shutdown randomly and then brough back by process $pid"
        set -- $@ $pid
    done

    OUTPUT_FOLDER=$(get_output_folder $1)
    c=$(ls -l $OUTPUT_FOLDER/ab-* | wc -l)
    # run ab
    for i in $(seq 1 $REPETITIONS)
    do
        echo "Running $i/$REPETITIONS run for $1     ($(date))"
        # ab -c $CONC_COUNT -n $REQ_COUNT http://localhost:8000/demo-1.0/ > $OUTPUT_FOLDER/ab-run-$c
        ./client/client localhost:8000/demo-1.0/ 100 5000 > $OUTPUT_FOLDER/client-run-$c
        c=$(expr $c + 1)
    done

    for p in $@
    do
        echo "Killing shutdowning process $p"
        kill $p
    done

    # clean
    for i in $(seq 1 $TOMCAT_COUNT)
    do
        tomcat_remove $i &
    done
    sleep 1

    # first preserve the error_log
    docker cp httpd-mod_proxy_cluster:/usr/local/apache2/logs/error_log $OUTPUT_FOLDER/error_log
    docker cp httpd-mod_proxy_cluster:/usr/local/apache2/logs/access_log $OUTPUT_FOLDER/access_log
    # and now we can remove it
    HTTPD_IMG=$1 httpd_all_clean
}

tomcat_all_remove
httpd_all_clean

mkdir -p output/1.3/
mkdir -p output/2.0/

run_abtest_for $HTTPD_IMG_2_0
run_abtest_for $HTTPD_IMG_1_3

