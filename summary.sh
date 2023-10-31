#!/usr/bin/sh

if [ ! -d output ]; then
    echo "Please run the suite first"
    exit 1
fi

for v in output/*; do
    echo "Summary for $(filename $v)"
    echo "-------------------------------------------"
    # print also the header
    echo "              min  mean[+/-sd] median   max"
    grep -h "Total:" $v/ab-*
    echo ""
done

