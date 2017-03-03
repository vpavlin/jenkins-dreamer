# Jenkins Dreamer

This script is an experimental work to see whether we can get auto-(un)idling for Jenkins on top of OpenShift Pipelines. 
It watches builds with type `JenkinsPipeline` and when there is a `New` build, it tries to hit Jenkins URL to wake it up in case it's idled.

For the second part, it watches how long it is since last `Finnished`, `Canceled` or `Failed` build and, based on configuration, it idles Jenkins if the
time surpases the given limit.

There is an OpenShift template available to run it next to the Jenkins instance on top of OpenShift. It requires some privileges regarding `view` and `edit`
of the project it's running under to follow new builds and to update Jenkins configs for idling.

```
oc policy add-role-to-user view system:serviceaccount:${NAMESPACE}:default --namespace ${NAMESPACE}
oc policy add-role-to-user edit system:serviceaccount:${NAMESPACE}:default --namespace ${NAMESPACE}
```

`#FIXME` use different than default service account!

It's implemented in Bash, so it's quite hacky and it would be best to reimplement in Go as that would enable it to use native libraries for OpenShift client.

Please consult `./dreamer.sh -h` for all the parameters