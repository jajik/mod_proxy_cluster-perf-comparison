## Simple performance comparison testsuite

> [!NOTE]
> Clone this repository with `--recurse-submodules`.

To get some basic performance comparison between mod\_proxy\_cluster 1.3.x and 2.x, run:

```
sh setup.sh
sh run.sh
```

These two files use several variables which you can tweak to influence tests parameters such
as number of tomcats, iterations count, etc. See their content for more information.

This suite uses docker and runs everything on a single machine, so take the results with
a grain of salt (especially if you run it on your workstation).

You can then print out summary of all runs by executing `summary.sh`.

To test additional versions, you can create a directory with `mod_proxy_cluster-` prefix
followed by a version (e.g. `mod_proxy_cluster-testing` will show up as `testing` version).
Keep the structure the same as is in the already existing folders (mainly a `native/` subdirectory
with a `cmake` for an easy compilation).

### Running the suite in GitHub Actions

The repository has a pipeline setup for execution on pull requests and pushes, so you'll get some
idea everytime a push happens.

To ease basic testing there's an additional workflow that can be triggered manually from the GitHub
interface without any code change. You can even provide additional mod\_proxy\_cluster sources
to test. See the `Manual` workflow in the `Actions` tab.

### Tools needed

* filename
* sed
* docker
* git
* maven
* ab (optional)

