# clean previous runs
rm -rf output/* || true
rm -rf nodes-*  || true

for count in 2 10 20 50
do
    echo "#########################################"
    echo "####### Running for $count nodes"
    echo "#########################################"
    TOMCAT_COUNT=$count sh run-suite.sh
    perl summary.pl > summary-for-$count
    mkdir nodes-$count
    mv summary-for-$count output/* nodes-$count/
    echo "Done!"
done

