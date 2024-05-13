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
    for t in $v/client-run-*; do
        cat $t
        echo ""
    done
    echo ""
done
