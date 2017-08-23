#!/usr/bin/bash

TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

JENKINS_NAMESPACE=${NAMESPACE}
BUILD_NAMESPACE=${NAMESPACE%-*}

echo "======================RUNNING DREAMER========================="
/opt/jenkins-dreamer/dreamer.sh --cacert ${CACERT} -H "openshift.default.svc.cluster.local" -t ${TOKEN} -n ${JENKINS_NAMESPACE} -b ${BUILD_NAMESPACE} --idle-after "${IDLE_AFTER}" --wait ${WAIT_TIME} &


echo "======================RUNNING NGINX==========================="
echo "----"
id
echo "----"

ls -al /var/lib/nginx/
ls -al /var/log/nginx/

nginx -c /etc/nginx/nginx.conf