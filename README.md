## Simple performance comparison testsuite

*NOTE: Clone this repository with `--recurse-submodules`.*

To get some basic performance comparison between mod\_proxy\_cluster 1.3.x and 2.x, run:

```
sh setup.sh
sh run.sh
```

The given files use some variables which you can tweak to influence tests parameters such
as number of tomcats, iterations count, etc.

This suite uses docker and runs everything on a single machine, so take the results with
a grain of salt (especially if you run it on your workstation).

You can then print out summary of all runs by executing `summary.sh`.

