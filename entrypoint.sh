#!/usr/bin/bash

TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

/opt/jenkins-dreamer/dreamer.sh --cacert ${CACERT} -H "openshift.default.svc.cluster.local" -t ${TOKEN} -n ${DREAMER_NAMESPACE} --idle-after ${IDLE_AFTER} --wait ${WAIT_TIME}