
ICINGA_API_PORT=${ICINGA_API_PORT:-5665}
USE_CERT_SERVICE=${USE_CERT_SERVICE:-'false'}

# ICINGA_CERT_SERVICE_SERVER=
# ICINGA_CERT_SERVICE_PORT=
# ICINGA_CERT_SERVICE_BA_USER=
# ICINGA_CERT_SERVICE_BA_PASSWORD=
# ICINGA_CERT_SERVICE_API_USER=
# ICINGA_CERT_SERVICE_API_PASSWORD=

# get a new icinga certificate from our icinga-master
#
#
get_certificate() {

  validate_local_ca

  if [ -f ${WORK_DIR}/pki/${HOSTNAME}/${HOSTNAME}.key ]
  then
    return
  fi

  if [ "${USE_CERT_SERVICE}" == "true" ]
  then
    log_info "we ask our cert-service for a certificate .."

    . /init/wait_for/cert_service.sh

    # generate a certificate request
    #
    code=$(curl \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --request GET \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-PASSWORD: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --write-out "%{http_code}\n" \
      --output /tmp/request_${HOSTNAME}.json \
      http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}/v2/request/${HOSTNAME})

    if ( [ $? -eq 0 ] && [ ${code} -eq 200 ] )
    then

      sleep 4s

      log_info "certifiacte request was successful"
      log_info "download and install the certificate"

      master_name=$(jq --raw-output .master_name /tmp/request_${HOSTNAME}.json)
      checksum=$(jq --raw-output .checksum /tmp/request_${HOSTNAME}.json)

#      rm -f /tmp/request_${HOSTNAME}.json

      mkdir -p ${WORK_DIR}/pki/${HOSTNAME}

      cp -a /tmp/request_${HOSTNAME}.json ${WORK_DIR}/pki/${HOSTNAME}/

      sleep 4s

      . /init/wait_for/cert_service.sh

      # get our created cert
      #
      code=$(curl \
        --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
        --silent \
        --request GET \
        --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
        --header "X-API-PASSWORD: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
        --header "X-CHECKSUM: ${checksum}" \
        --write-out "%{http_code}\n" \
        --request GET \
        --output ${WORK_DIR}/pki/${HOSTNAME}/${HOSTNAME}.tgz \
        http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}/v2/cert/${HOSTNAME})

      if ( [ $? -eq 0 ] && [ ${code} -eq 200 ] )
      then

        cd ${WORK_DIR}/pki/${HOSTNAME}

        # the download has not working
        #
        if [ ! -f ${HOSTNAME}.tgz ]
        then
          log_error "Cert File '${HOSTNAME}.tgz' not found!"
          exit 1
        fi

        tar -xzf ${HOSTNAME}.tgz

        if [ ! -f ${HOSTNAME}.pem ]
        then
          cat ${HOSTNAME}.crt ${HOSTNAME}.key >> ${HOSTNAME}.pem
        fi

        # store the master for later restart
        #
        echo "${master_name}" > ${WORK_DIR}/pki/${HOSTNAME}/master

        sleep 10s

        restart_master

      else
        log_error "can't download out certificate!"

        rm -rf ${WORK_DIR}/pki/${HOSTNAME} 2> /dev/null

        unset ICINGA_API_PKI_PATH

        exit 1
      fi
    else

      if [ -f /tmp/request_${HOSTNAME}.json ]
      then
        error=$(cat /tmp/request_${HOSTNAME}.json)

        log_error "${code} - the cert-service tell us a problem: '${error}'"
        log_error "exit ..."

        rm -f /tmp/request_${HOSTNAME}.json
      else
        log_error "${code} - the cert-service has an unknown problem."
      fi
      exit 1
    fi
  fi
}

# validate our lokal certificate against our certificate service
# with an API Request against
# http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}/v2/validate/${checksum})
#
# if this failed, the PKI schould be removed
#
validate_local_ca() {

  if [[ -f ${WORK_DIR}/pki/${HOSTNAME}/ca.crt ]]
  then
    checksum=$(sha256sum ${WORK_DIR}/pki/${HOSTNAME}/ca.crt | cut -f 1 -d ' ')

    # validate our ca file
    #
    code=$(curl \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --request GET \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-PASSWORD: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --write-out "%{http_code}\n" \
      --output /tmp/validate_ca_${HOSTNAME}.json \
      http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}/v2/validate/${checksum})

    if ( [[ $? -eq 0 ]] && [[ ${code} == 200 ]] )
    then
      rm -f /tmp/validate_ca_${HOSTNAME}.json
    else

      status=$(echo "${code}" | jq --raw-output .status 2> /dev/null)
      message=$(echo "${code}" | jq --raw-output .message 2> /dev/null)

      log_warn "our master has a new CA"

      rm -f /tmp/validate_ca_${HOSTNAME}.json
      rm -rf ${WORK_DIR}/pki
    fi
  else
    # we have no local cert file ..
    :
  fi
}

create_certificate_pem() {

  if ( [[ -d ${WORK_DIR}/pki/${HOSTNAME} ]] && [[ ! -f ${WORK_DIR}/pki/${HOSTNAME}/${HOSTNAME}.pem ]] )
  then
    cd ${WORK_DIR}/pki/${HOSTNAME}

    cat ${HOSTNAME}.crt ${HOSTNAME}.key >> ${HOSTNAME}.pem
  fi
}


validate_cert() {

  . /init/wait_for/icinga_master.sh

  if [[ -d ${WORK_DIR}/pki/${HOSTNAME} ]]
  then
    cd ${WORK_DIR}/pki/${HOSTNAME}

    log_info "validate our certifiacte"
set -x
    code=$(curl \
      --silent \
      --insecure \
      --user ${ICINGA_CERT_SERVICE_API_USER}:${ICINGA_CERT_SERVICE_API_PASSWORD} \
      --capath . \
      --cert ./${HOSTNAME}.pem \
      --cacert ./ca.crt \
      https://${ICINGA_MASTER}:5665/v1/status/IcingaApplication)

    if [[ $? -eq 0 ]]
    then
      log_info "certifiacte is valid"
    else
      log_error ${code}
      log_error "certifiacte is invalid"
      log_info "unset PKI Variables to use Fallback"

      unset ICINGA_API_PKI_PATH
      unset ICINGA_API_NODE_NAME
    fi
set +x
  fi
}


extract_vars() {

  if [[ ! -z "${ICINGA_CERT_SERVICE}" ]]
  then

      ICINGA_CERT_SERVICE_SERVER=${ICINGA_CERT_SERVICE_SERVER:-}
      ICINGA_CERT_SERVICE_PORT=${ICINGA_CERT_SERVICE_PORT:-8080}
      ICINGA_CERT_SERVICE_PATH=${ICINGA_CERT_SERVICE_PATH:-'/'}
      ICINGA_CERT_SERVICE_API_USER=${ICINGA_CERT_SERVICE_API_USER:-''}
      ICINGA_CERT_SERVICE_API_PASSWORD=${ICINGA_CERT_SERVICE_API_PASSWORD:-''}
      ICINGA_CERT_SERVICE_BA_USER=${ICINGA_CERT_SERVICE_BA_USER:-"admin"}
      ICINGA_CERT_SERVICE_BA_PASSWORD=${ICINGA_CERT_SERVICE_BA_PASSWORD:-"admin"}

      ICINGA_CERT_SERVICE_PATH=$(echo "${ICINGA_CERT_SERVICE_PATH}" | cut -d "/" -f 2)


    USE_FALLBACK="false"

    if ( [[ "${ICINGA_CERT_SERVICE}" != "true" ]] && [[ "${ICINGA_CERT_SERVICE}" != "false" ]] )
    then
      echo "${ICINGA_CERT_SERVICE}" | json_verify -q 2> /dev/null

      if [[ $? -gt 0 ]]
      then
        log_warn "the ICINGA_CERT_SERVICE Environment is not an json"
        log_warn "use fallback strategy."
        USE_FALLBACK="true"
      fi
    else
      log_warn "the ICINGA_CERT_SERVICE Environment is not an json"
      log_warn "use fallback strategy."
      USE_FALLBACK="true"
    fi


    if [[ "${USE_FALLBACK}" == "false" ]]
    then

      if ( [[ "${ICINGA_CERT_SERVICE}" == "true" ]] || [[ "${ICINGA_CERT_SERVICE}" == "false" ]] )
      then
        log_error "the ICINGA_CERT_SERVICE Environment must be an json, not true or false!"
        exit 1
      fi

      ICINGA_CERT_SERVICE_SERVER=$(echo "${ICINGA_CERT_SERVICE}" | jq --raw-output .server)
      ICINGA_CERT_SERVICE_PORT=$(echo "${ICINGA_CERT_SERVICE}" | jq --raw-output .port)
      ICINGA_CERT_SERVICE_PATH=$(echo "${ICINGA_CERT_SERVICE}" | jq --raw-output .path)
      ICINGA_CERT_SERVICE_API_USER=$(echo "${ICINGA_CERT_SERVICE}" | jq --raw-output .api.user)
      ICINGA_CERT_SERVICE_API_PASSWORD=$(echo "${ICINGA_CERT_SERVICE}" | jq --raw-output .api.password)
      ICINGA_CERT_SERVICE_BA_USER=$(echo "${ICINGA_CERT_SERVICE}" | jq --raw-output .ba.user)
      ICINGA_CERT_SERVICE_BA_PASSWORD=$(echo "${ICINGA_CERT_SERVICE}" | jq --raw-output .ba.password)

      [[ "${ICINGA_CERT_SERVICE_SERVER}" == null ]] && ICINGA_CERT_SERVICE_SERVER=
      [[ "${ICINGA_CERT_SERVICE_PORT}" == null ]] && ICINGA_CERT_SERVICE_PORT=8080
      [[ "${ICINGA_CERT_SERVICE_PATH}" == null ]] && ICINGA_CERT_SERVICE_PATH="/"
      [[ "${ICINGA_CERT_SERVICE_API_USER}" == null ]] && ICINGA_CERT_SERVICE_API_USER=
      [[ "${ICINGA_CERT_SERVICE_API_PASSWORD}" == null ]] && ICINGA_CERT_SERVICE_API_PASSWORD=
      [[ "${ICINGA_CERT_SERVICE_BA_USER}" == null ]] && ICINGA_CERT_SERVICE_BA_USER=
      [[ "${ICINGA_CERT_SERVICE_BA_PASSWORD}" == null ]] && ICINGA_CERT_SERVICE_BA_PASSWORD=

    else

      ICINGA_CERT_SERVICE_SERVER=${ICINGA_CERT_SERVICE_SERVER:-}
      ICINGA_CERT_SERVICE_PORT=${ICINGA_CERT_SERVICE_PORT:-8080}
      ICINGA_CERT_SERVICE_PATH=${ICINGA_CERT_SERVICE_PATH:-'/'}
      ICINGA_CERT_SERVICE_API_USER=${ICINGA_CERT_SERVICE_API_USER:-''}
      ICINGA_CERT_SERVICE_API_PASSWORD=${ICINGA_CERT_SERVICE_API_PASSWORD:-''}
      ICINGA_CERT_SERVICE_BA_USER=${ICINGA_CERT_SERVICE_BA_USER:-"admin"}
      ICINGA_CERT_SERVICE_BA_PASSWORD=${ICINGA_CERT_SERVICE_BA_PASSWORD:-"admin"}

      ICINGA_CERT_SERVICE_PATH=$(echo "${ICINGA_CERT_SERVICE_PATH}" | cut -d "/" -f 2)
    fi
  fi


  if (
    [ ! -z ${ICINGA_CERT_SERVICE_SERVER} ] &&
    [ ! -z ${ICINGA_CERT_SERVICE_PORT} ] &&
    [ ! -z ${ICINGA_CERT_SERVICE_BA_USER} ] &&
    [ ! -z ${ICINGA_CERT_SERVICE_BA_PASSWORD} ] &&
    [ ! -z ${ICINGA_CERT_SERVICE_API_USER} ] &&
    [ ! -z ${ICINGA_CERT_SERVICE_API_PASSWORD} ]
  )
  then
    USE_CERT_SERVICE="true"
  else
    USE_CERT_SERVICE="false"
  fi
}



restart_master() {

  sleep $(shuf -i 5-30 -n 1)s

  . /init/wait_for/icinga_master.sh

  # restart the master to activate the zone
  #
  log_info "restart the master '${ICINGA_MASTER}' to activate our certificate"
  code=$(curl \
    --user ${ICINGA_CERT_SERVICE_API_USER}:${ICINGA_CERT_SERVICE_API_PASSWORD} \
    --silent \
    --header 'Accept: application/json' \
    --request POST \
    --insecure \
    https://${ICINGA_MASTER}:5665/v1/actions/restart-process )

  if [[ $? -gt 0 ]]
  then
    status=$(echo "${code}" | jq --raw-output '.results[].code' 2> /dev/null)
    message=$(echo "${code}" | jq --raw-output '.results[].status' 2> /dev/null)

    log_error "${code}"
    log_error "${message}"
  fi
}


extract_vars
. /init/wait_for/cert_service.sh
get_certificate
validate_cert


if [ -d ${WORK_DIR}/pki/${HOSTNAME} ]
then
  log_info "export PKI vars"

  export ICINGA_HOST=${ICINGA_MASTER}

  export ICINGA_API_USER=${ICINGA_CERT_SERVICE_API_USER}
  export ICINGA_API_PASSWORD=${ICINGA_CERT_SERVICE_API_PASSWORD}

  export ICINGA_API_PKI_PATH=${WORK_DIR}/pki/${HOSTNAME}
  export ICINGA_API_NODE_NAME=${HOSTNAME}
fi
