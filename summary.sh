#!/usr/bin/sh

folder=${1:-output}

if [ ! -d $folder ]; then
    echo "Please run the suite first"
    exit 1
fi

for v in $folder/*; do
    echo "Summary for $(filename $v)"
    echo "-------------------------------------------"
    # print also the header
    echo "              min  mean[+/-sd] median   max"
    for t in $v/ab-*; do
        if [ $(grep -c "Total:" $t) -eq 0 ]; then
            echo "Failed run (ab did not finished)"
        else
            grep -h "Total:" $t | tr -d '\n'
            echo -n "    ("
            if [ $(grep -c "Non-2xx responses" $t) -eq 0 ]; then
                echo -n "All responses were 2xx   "
            else
                grep -h "Non-2xx responses:" $t | tr -d '\n'
            fi
            echo ")"
        fi
    done
    echo ""
done
