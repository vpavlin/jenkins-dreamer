#!/usr/bin/bash

CACERT=""
HOST=""
TOKEN=""
NAMESPACE=""
IDLE_AFTER="30 sec"
WAIT=1
DEBUG=false

function help() {
  echo "
$0 is a script which watches builds and Jenkins in given OpenShift namespace
and idles/wakes Jenkins based on running builds.

-h                        Print help
-H|--host                 Openshift host URI
-t|--token                OpenShift token for auth
-n|--jenkins-namespace    OpenShift namespace to operate in
-b|--build-namespace      OpenShift namespace to operate in
--idle-after              Time to wait between finished (or cancelled or failed) 
                          build and idling Jenkins
--wait                    Value passed to sleep in main loop
--cacert                  Path to CA cert for OpenShift host
--insecure                Will use --insecure with curl in case you don't have 
                          CA cert for OpenShift host
  "  

}

while [ -n "$1" ]; do
  case "$1" in
    -h) help    
        exit
        ;;
    --idle-after) 
        shift
        IDLE_AFTER="$1 min"
        ;;
    --wait)
        shift
        WAIT=$1
        ;;
    --insecure)
        CACERT="--insecure"
        ;;
    --cacert)
        shift
        CACERT="--cacert $1"
        ;;
    -H|--host)
        shift
        HOST=$1
        ;;
    -t|--token)
        shift
        TOKEN=$1
        ;;
    -n|--jenkins-namespace)
        shift
        NAMESPACE=$1
        ;;
    -b|--build-namespace)
        shift
        BUILD_NAMESPACE=$1
        ;;
    *) echo "Unknown parameter $1"
       exit 1
       ;;
  esac
  shift
done

RAW_HOST=$(echo ${HOST} | sed -n 's#\([^:]*\).*#\1#p') #FIXME
[[ "${HOST}" =~ ^http:// ]] || HOST="https://"${HOST}
[[ "${HOST}" =~ /$ ]] || HOST=${HOST}"/"

[ -n "${BUILD_NAMESPACE}" ] || BUILD_NAMESPACE=${NAMESPACE}

LAST_STATE_FILE=./lastState-${NAMESPACE}.txt #Information about changes of jenkins state

function last_state_change() {
  local LAST_STATE_TIME=$(date -u -I'seconds')
  LAST_STATE_TIME=${LAST_STATE_TIME%%+*}Z
  echo ${LAST_STATE_TIME}
}

function get_jenkins_replicas() {
  curl ${CACERT} -XGET -k -H "Authorization: Bearer ${TOKEN}" ${HOST}oapi/v1/namespaces/${NAMESPACE}/deploymentconfigs/jenkins/ 2> /dev/null | jq -r '.spec.replicas'
}

function sheep_counter() {
  local REPLICAS=$(get_jenkins_replicas)
  if [ ${REPLICAS} -eq 0 ]; then
    return
  fi

  local URL=http://${JENKINS_SERVICE_HOST}:${JENKINS_SERVICE_PORT_HTTP}/${NGINX_STATUS_UUID}
  local LAST_REQUESTS_FILE="./lastRequests-${NAMESPACE}.txt"
  local LAST_REQUESTS=$(( $(cat ${LAST_REQUESTS_FILE} 2>/dev/null || echo "0") + 1 ))
  local RESPONSE=$(curl ${URL} 2> /dev/null)
  if [ -z "${RESPONSE}" ]; then
    return
  fi
  local ACTIVE=$(echo ${RESPONSE} | sed -n 's/Active connections: \([0-9]*\) .*/\1/p')
  local REQUESTS=$(echo ${RESPONSE} | sed -n 's/.* requests [0-9]* [0-9]* \([0-9]*\) .*/\1/p')

  if [ ${ACTIVE} -ge 2 ]; then
    echo "running "$(last_state_change) > ${LAST_STATE_FILE}
    return
  fi

  if [ ${REQUESTS} -gt ${LAST_REQUESTS} ]; then
    echo "running "$(last_state_change) > ${LAST_STATE_FILE}
  fi

  echo ${REQUESTS} > ${LAST_REQUESTS_FILE}

}

function waker() {
  local RESPONSE=$1
  if [ -n "${KUBERNETES_SERVICE_HOST}" ]; then
    if [ -z "${JENKINS_SERVICE_HOST}" ]; then
      echo "Cannot ping Jenkins:("
      exit 1
    fi
  fi

  echo "Waking up Jenkins. Good morning."
  if [ -n "${JENKINS_SERVICE_HOST}" ]; then
    curl -q http://${JENKINS_SERVICE_HOST}:${JENKINS_SERVICE_PORT_HTTP}/login &> /dev/null
  else
    curl -q http://jenkins-${NAMESPACE}.${RAW_HOST}/login &> /dev/null
  fi
}

function sleeper() {
  local TIMESTAMP=$1
  local PHASE=$2
  local LAST_BUILD_FILE=./lastBuild-${NAMESPACE}.txt #Information about last build

  local LAST_BUILD_CNT=$(cat $LAST_BUILD_FILE 2>/dev/null || echo   "0")
  local LAST_BUILD=$(date -u -d "${LAST_BUILD_CNT}" +%s)
  local LAST_STATE_DATA=$(cat ${LAST_STATE_FILE} 2>/dev/null || echo "idled 0" )
  local LAST_STATE=${LAST_STATE_DATA%% *}
  local LAST_STATE_TIME=${LAST_STATE_DATA##* }
  
  [ "${TIMESTAMP}" == "null" ] && TIMESTAMP=$(date -u -I'seconds') && TIMESTAMP=${TIMESTAMP%%+*}Z

  TS=$(date -u -d "$TIMESTAMP" +%s)
  if [ "$TS" -gt "$LAST_BUILD" ]; then
    echo "Storing last build timestamp: ${TIMESTAMP}"
    echo "$TIMESTAMP" > $LAST_BUILD_FILE
  fi

  CURRENT_TS=$(date -u +%s)
  TS_IDLE_AFTER=$(date -u -d "${TIMESTAMP} + ${IDLE_AFTER}" +%s)
  LAST_TS_IDLE_AFTER=$(date -u -d "${LAST_STATE_TIME} + ${IDLE_AFTER}" +%s)

  #echo "DIFF=$(( ${CURRENT_TS} - ${TS_IDLE_AFTER} )) LAST_TS_IDLE_AFTER=${LAST_TS_IDLE_AFTER} LAST_STATE_DATA=${LAST_STATE_DATA}"

  if [ "${CURRENT_TS}" -ge "${TS_IDLE_AFTER}" ] && [ "${PHASE}" == "Finished" -o "${PHASE}" == "Complete" -o "${PHASE}" == "Failed" -o "${PHASE}" == "Cancelled" ]; then
    #Check current replicas
    if $DEBUG; then
      echo "curl ${CACERT} -XGET -k -H "Authorization: Bearer ${TOKEN}" ${HOST}oapi/v1/namespaces/${NAMESPACE}/deploymentconfigs/jenkins/"
    fi
    REPLICAS=$(get_jenkins_replicas)
    if [ "${REPLICAS}" -gt 0 ]; then
      if [ "${LAST_STATE}" == "idled" ]; then
        echo "Jenkins has been waken up by user, will let it run for ${IDLE_AFTER}"
        echo "running "$(last_state_change) > ${LAST_STATE_FILE}
        return
      elif [ "${LAST_TS_IDLE_AFTER}" -ge "${CURRENT_TS}" ]; then
        echo "Jenkins has been waken by user, will be idled in "$(( ${LAST_TS_IDLE_AFTER} - ${CURRENT_TS} ))"s"
        return
      fi
      #echo "Jenkins already idled"
      echo "Idling Jenkins. Good night."
      IDLED_AT=$(date -u -I'seconds')
      #Patch endpoint
      echo "{\"metadata\":{\"annotations\":{\"idling.alpha.openshift.io/idled-at\":\"${IDLED_AT%%+*}Z\",\"idling.alpha.openshift.io/unidle-targets\":\"[{\\\"kind\\\":\\\"DeploymentConfig\\\",\\\"name\\\":\\\"jenkins\\\",\\\"replicas\\\":1}]\"}}}" > idle.patch
      curl ${CACERT} -q -k -XPATCH  -H "Accept: application/json, */*" -H "Content-Type: application/strategic-merge-patch+json" -d @idle.patch\
      -H "Authorization: Bearer ${TOKEN}" ${HOST}api/v1/namespaces/${NAMESPACE}/endpoints/jenkins &> /dev/null

      #Get DC
      curl ${CACERT} -XGET -k -H "Authorization: Bearer ${TOKEN}" ${HOST}oapi/v1/namespaces/${NAMESPACE}/deploymentconfigs/jenkins/ > dc.json 2> /dev/null

      #Add idling annotations
      cat dc.json | jq -r '.metadata.annotations."idling.alpha.openshift.io/idled-at"="'${IDLED_AT%%+*}Z'"' | jq -r '.metadata.annotations."idling.alpha.openshift.io/previous-scale"="1"' | jq -r '.spec.replicas=0' > dc-patched.json

      #Put new DC
      curl ${CACERT} -q -k -XPUT  -H "Accept: application/json, */*" -H "Content-Type: application/json" -H "User-Agent: oc/v1.4.1+3f9807a (linux/amd64) openshift/92ef595" -d @dc-patched.json\
      -H "Authorization: Bearer ${TOKEN}" ${HOST}oapi/v1/namespaces/${NAMESPACE}/deploymentconfigs/jenkins &> /dev/null
      
      echo "idled "$(last_state_change) > ${LAST_STATE_FILE}
    else
      if [ $(( ${TS_IDLE_AFTER} - ${CURRENT_TS} )) -ge 0 ]; then
        echo "Jenkins will be idled in "$(( ${TS_IDLE_AFTER} - ${CURRENT_TS} ))"s"
      fi
      return
    fi
  fi

}

RETRY=1
while true; do

  #echo curl -k -H "Authorization: Bearer ${TOKEN}" "${HOST}oapi/v1/namespaces/${NAMESPACE}/builds"
  RESPONSE=$(curl ${CACERT} -k -H "Authorization: Bearer ${TOKEN}" "${HOST}oapi/v1/namespaces/${BUILD_NAMESPACE}/builds" 2> /dev/null)
  if [ $? -ne 0 ]; then
    echo "Could not get builds from namespace ${BUILD_NAMESPACE} (${RETRY})"
    if [ ${RETRY} -ge 5 ]; then
      exit 1
    fi
    RETRY=$(( ${RETRY} + 1 ))
  fi
  PHASE=""
  TYPE=""
  TIMESTAMP=""
  NAME=""
  #Reorder - latest build will be last
  RESPONSE=$(echo ${RESPONSE} | jq '.items|=sort_by(.metadata.annotations."openshift.io/build.number" | tonumber)')
  i=-1
  while [ "${TYPE}" != "JenkinsPipeline" ]; do
    len=$(echo $RESPONSE | jq -r '.items | length')
    diff=$(( $len + $i ))
    if [ "$diff" -lt 0 ]; then
      break
    fi
    PHASE=$(echo $RESPONSE | jq -r .items[$i].status.phase)
    TYPE=$(echo $RESPONSE | jq -r .items[$i].spec.strategy.type)
    if [ "${PHASE}" == "Finished" -o "${PHASE}" == "Complete" -o "${PHASE}" == "Failed" -o "${PHASE}" == "Cancelled" ]; then
      TIMESTAMP=$(echo ${RESPONSE} | jq -r .items[$i].status.completionTimestamp)
    else
      TIMESTAMP=$(echo ${RESPONSE} | jq -r .items[$i].status.startTimestamp)
    fi

    NAME=$(echo $RESPONSE | jq -r .items[$i].metadata.name)
    i=$(( $i - 1 ))
  done

  echo "Last build of $TYPE was $PHASE since $TIMESTAMP"

  sheep_counter

  if [ "${TYPE}" == "JenkinsPipeline" ]; then
    if [ "${PHASE}" == "New" ]; then
      waker $RESPONSE
    else
      sleeper $TIMESTAMP $PHASE
    fi
  fi
  
  sleep ${WAIT}
done