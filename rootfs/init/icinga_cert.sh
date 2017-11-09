

ICINGA_API_PORT=${ICINGA_API_PORT:-5665}
ICINGA_CERT_SERVICE=${ICINGA_CERT_SERVICE:-false}

# wait for the Icinga2 Master
#
wait_for_icinga_master() {

#   if [ ${ICINGA_CLUSTER} == false ]
#   then
#     return
#   fi

  RETRY=50

  until [ ${RETRY} -le 0 ]
  do
    nc -z ${ICINGA_HOST} 5665 < /dev/null > /dev/null

    [ $? -eq 0 ] && break

    echo " [i] Waiting for icinga master '${ICINGA_HOST}' to come up"

    sleep 5s
    RETRY=$(expr ${RETRY} - 1)
  done

  if [ $RETRY -le 0 ]
  then
    echo " [E] could not connect to the icinga2 master instance '${ICINGA_HOST}'"
    exit 1
  fi

  sleep 10s
}


# wait for the Certificate Service
#
wait_for_icinga_cert_service() {

  # the CERT-Service API use an Basic-Auth as first Authentication *AND*
  # use an own API Userr
  if [ ${ICINGA_CERT_SERVICE} ]
  then

    # use the new Cert Service to create and get a valide certificat for distributed icinga services
    if (
      [ ! -z ${ICINGA_CERT_SERVICE_BA_USER} ] && [ ! -z ${ICINGA_CERT_SERVICE_BA_PASSWORD} ] &&
      [ ! -z ${ICINGA_CERT_SERVICE_API_USER} ] && [ ! -z ${ICINGA_CERT_SERVICE_API_PASSWORD} ]
    )
    then

      RETRY=30
      # wait for the running cert-service
      #
      until [ ${RETRY} -le 0 ]
      do
        nc -z ${ICINGA_CERT_SERVICE_SERVER} ${ICINGA_CERT_SERVICE_PORT} < /dev/null > /dev/null

        [ $? -eq 0 ] && break

        echo " [i] wait for the cert-service on '${ICINGA_CERT_SERVICE_SERVER}'"

        sleep 15s
        RETRY=$(expr ${RETRY} - 1)
      done

      if [ $RETRY -le 0 ]
      then
        echo " [E] Could not connect to the Certificate-Service '${ICINGA_CERT_SERVICE_SERVER}'"
        exit 1
      fi

      # okay, the web service is available
      # but, we have a problem, when he runs behind a proxy ...
      # eg.: https://monitoring-proxy.tld/cert-cert-service
      #

      RETRY=30
      # wait for the cert-service health check behind a proxy
      #
      until [ ${RETRY} -le 0 ]
      do

        health=$(curl \
          --silent \
          --request GET \
          --write-out "%{http_code}\n" \
          --request GET \
          http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}v2/health-check)

        if ( [ $? -eq 0 ] && [ "${health}" == "healthy200" ] )
        then
          break
        fi

        health=

        echo " [i] wait for the health check for the cert-service on '${ICINGA_CERT_SERVICE_SERVER}'"
        sleep 15s
        RETRY=$(expr ${RETRY} - 1)
      done

      if [ $RETRY -le 0 ]
      then
        echo " [E] Could not a Health Check from the Certificate-Service '${ICINGA_CERT_SERVICE_SERVER}'"
        exit 1
      fi

      sleep 5s
    fi
  fi
}

get_certificate() {

  if [ ${ICINGA_CERT_SERVICE} ]
  then
    echo ""
    echo " [i] we ask our cert-service for a certificate .."

    # generate a certificate request
    #
    code=$(curl \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --request GET \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-KEY: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --write-out "%{http_code}\n" \
      --output /tmp/request_${HOSTNAME}.json \
      http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}v2/request/${HOSTNAME})

    if ( [ $? -eq 0 ] && [ ${code} -eq 200 ] )
    then

      echo " [i] certifiacte request was successful"
      echo " [i] download and install the certificate"

      masterName=$(jq --raw-output .master_name /tmp/request_${HOSTNAME}.json)
      checksum=$(jq --raw-output .checksum /tmp/request_${HOSTNAME}.json)

#      rm -f /tmp/request_${HOSTNAME}.json

      mkdir -p ${WORK_DIR}/pki/${HOSTNAME}

      # get our created cert
      #
      code=$(curl \
        --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
        --silent \
        --request GET \
        --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
        --header "X-API-KEY: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
        --header "X-CHECKSUM: ${checksum}" \
        --write-out "%{http_code}\n" \
        --request GET \
        --output ${WORK_DIR}/pki/${HOSTNAME}/${HOSTNAME}.tgz \
        http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}v2/cert/${HOSTNAME})

      if ( [ $? -eq 0 ] && [ ${code} -eq 200 ] )
      then

      cd ${WORK_DIR}/pki/${HOSTNAME}

      # the download has not working
      #
      if [ ! -f ${HOSTNAME}.tgz ]
      then
        echo " [E] Cert File '${HOSTNAME}.tgz' not found!"
        exit 1
      fi

      tar -xzf ${HOSTNAME}.tgz

      # store the master for later restart
      #
      echo "${masterName}" > ${WORK_DIR}/pki/${HOSTNAME}/master
      else
        echo " [E] can't download out certificate!"

        rm -rf ${WORK_DIR}/pki 2> /dev/null

        unset ICINGA_API_PKI_PATH
      fi
    else

      echo " [E] ${code} - the cert-service has an error."
      cat /tmp/request_${HOSTNAME}.json

      rm -f /tmp/request_${HOSTNAME}.json
      exit 1
    fi
  fi
}


validate_local_ca() {

  if [ -f ${WORK_DIR}/pki/${HOSTNAME}/ca.crt ]
  then
    CHECKSUM=$(sha256sum ${WORK_DIR}/pki/${HOSTNAME}/ca.crt | cut -f 1 -d ' ')

    # generate a certificate request
    #
    code=$(curl \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --request GET \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-KEY: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --write-out "%{http_code}\n" \
      --output /tmp/validate_ca_${HOSTNAME}.json \
      http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}v2/validate/${CHECKSUM})

    if ( [ $? -eq 0 ] && [ ${code} == 200 ] )
    then
      rm -f /tmp/validate_ca_${HOSTNAME}.json
    else

      status=$(echo "${code}" | jq --raw-output .status 2> /dev/null)
      message=$(echo "${code}" | jq --raw-output '.message' 2> /dev/null)

      echo " [w] our master has a new CA"
      echo -n "     "
      echo "${message}"

      rm -rf ${WORK_DIR}/pki
      rm -rf /etc/icinga2/pki/*

      rm -f /etc/icinga2/features-available/api.conf
      touch /etc/icinga2/features-available/api.conf
    fi
  else
    :
  fi
}


validate_cert() {

  if [ -d ${WORK_DIR}/pki/${HOSTNAME} ]
  then
    cd ${WORK_DIR}/pki/${HOSTNAME}

    if [ ! -f ${HOSTNAME}.pem ]
    then
      cat ${HOSTNAME}.crt ${HOSTNAME}.key >> ${HOSTNAME}.pem
    fi

    curl \
      --silent \
      --insecure \
      --user ${ICINGA_CERT_SERVICE_API_USER}:${ICINGA_CERT_SERVICE_API_PASSWORD} \
      --capath . \
      --cert ./dashing.pem \
      --cacert ./ca.crt \
      https://${ICINGA_HOST}:${ICINGA_API_PORT}/v1/status/CIB

    if [[ $? -gt 0 ]]
    then
      rm -rf ${WORK_DIR}/pki
    fi
  fi
}

wait_for_icinga_master
validate_cert

wait_for_icinga_cert_service
validate_local_ca
get_certificate

if [ -d ${WORK_DIR}/pki/${HOSTNAME} ]
then
  echo " [i] export PKI vars"

  export ICINGA_API_PKI_PATH=${WORK_DIR}/pki/${HOSTNAME}
  export ICINGA_API_NODE_NAME=${HOSTNAME}
fi
