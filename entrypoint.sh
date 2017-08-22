#!/usr/bin/bash

TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

JENKINS_NAMESPACE=${NAMESPACE}
BUILD_NAMESPACE=${NAMESPACE%-*}

/opt/jenkins-dreamer/dreamer.sh --cacert ${CACERT} -H "openshift.default.svc.cluster.local" -t ${TOKEN} -n ${JENKINS_NAMESPACE} -b ${BUILD_NAMESPACE} --idle-after "${IDLE_AFTER}" --wait ${WAIT_TIME}