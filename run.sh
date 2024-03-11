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

. mod_proxy_cluster/test/includes/common.sh

get_output_folder() {
    if [ "$1" = $HTTPD_IMG_1_3 ]; then
        echo "output/1.3/"
    else
        echo "output/2.0/"
    fi
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
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/app/
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/test/
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/test2/
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/test/
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/production/
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/testapp
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/legacy
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/demo/
        docker cp mod_proxy_cluster/test/testapp tomcat$i:/usr/local/tomcat/webapps/sample/
    done

    sleep 10

    OUTPUT_FOLDER=$(get_output_folder $1)
    c=$(ls -l $OUTPUT_FOLDER/ab-* | wc -l)
    # run ab
    for i in $(seq 1 $REPETITIONS)
    do
        echo "Running $i/$REPETITIONS run for $1     ($(date))"
        ab -c $CONC_COUNT -n $REQ_COUNT http://localhost:8000/testapp/test.jsp > $OUTPUT_FOLDER/ab-run-$c
        c=$(expr $c + 1)
    done

    # clean
    for i in $(seq 1 $TOMCAT_COUNT)
    do
        tomcat_remove $i &
    done
    sleep 1

    # first preserve the error_log
    docker cp httpd-mod_proxy_cluster:/usr/local/apache2/logs/error_log $OUTPUT_FOLDER/error_log
    # and now we can remove it
    HTTPD_IMG=$1 httpd_all_clean
}


mkdir -p output/1.3/
mkdir -p output/2.0/

run_abtest_for $HTTPD_IMG_2_0
run_abtest_for $HTTPD_IMG_1_3

