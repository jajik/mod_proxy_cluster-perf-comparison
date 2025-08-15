# clean previous runs
rm -rf output/* || true
rm -rf nodes-*  || true
sh setup.sh

for count in 2 10 20 50 ## 100 150
do
    echo "Running for $count nodes"
    TOMCAT_COUNT=$count sh run-suite.sh
    sh summary.sh > summary-for-$count
    mkdir nodes-$count
    mv summary-for-$count output/* nodes-$count/
    echo "Done!"
done

