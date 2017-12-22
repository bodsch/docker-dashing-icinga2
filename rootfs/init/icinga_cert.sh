
ICINGA_API_PORT=${ICINGA_API_PORT:-5665}
ICINGA_CERT_SERVICE=${ICINGA_CERT_SERVICE:-false}

# get a new icinga certificate from our icinga-master
#
#
get_certificate() {

  validate_local_ca

  if [ -f ${WORK_DIR}/pki/${HOSTNAME}.key ]
  then
    return
  fi

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

      master_name=$(jq --raw-output .master_name /tmp/request_${HOSTNAME}.json)
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

        if [ ! -f ${HOSTNAME}.pem ]
        then
          cat ${HOSTNAME}.crt ${HOSTNAME}.key >> ${HOSTNAME}.pem
        fi

        # store the master for later restart
        #
        echo "${master_name}" > ${WORK_DIR}/pki/${HOSTNAME}/master

      else
        echo " [E] can't download out certificate!"

        rm -rf ${WORK_DIR}/pki 2> /dev/null

        unset ICINGA_API_PKI_PATH

        exit 1
      fi
    else

      error=$(cat /tmp/request_${HOSTNAME}.json)

      echo " [E] ${code} - the cert-service tell us a problem: '${error}'"
      echo " [E] exit ..."

      rm -f /tmp/request_${HOSTNAME}.json
      exit 1
    fi

  fi
}

# validate our lokal certificate against our certificate service
# with an API Request against
# http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}v2/validate/${checksum})
#
# if this failed, the PKI schould be removed
#
validate_local_ca() {

  if [ -f ${WORK_DIR}/pki/${HOSTNAME}/ca.crt ]
  then
    checksum=$(sha256sum ${WORK_DIR}/pki/${HOSTNAME}/ca.crt | cut -f 1 -d ' ')

    # validate our ca file
    #
    code=$(curl \
      --user ${ICINGA_CERT_SERVICE_BA_USER}:${ICINGA_CERT_SERVICE_BA_PASSWORD} \
      --silent \
      --request GET \
      --header "X-API-USER: ${ICINGA_CERT_SERVICE_API_USER}" \
      --header "X-API-KEY: ${ICINGA_CERT_SERVICE_API_PASSWORD}" \
      --write-out "%{http_code}\n" \
      --output /tmp/validate_ca_${HOSTNAME}.json \
      http://${ICINGA_CERT_SERVICE_SERVER}:${ICINGA_CERT_SERVICE_PORT}${ICINGA_CERT_SERVICE_PATH}v2/validate/${checksum})

    if ( [ $? -eq 0 ] && [ ${code} == 200 ] )
    then
      rm -f /tmp/validate_ca_${HOSTNAME}.json
    else

      status=$(echo "${code}" | jq --raw-output .status 2> /dev/null)
      message=$(echo "${code}" | jq --raw-output .message 2> /dev/null)

      echo " [w] our master has a new CA"

      rm -f /tmp/validate_ca_${HOSTNAME}.json
      rm -rf ${WORK_DIR}/pki
    fi
  else
    # we have no local cert file ..
    :
  fi
}

. /init/wait_for/cert_service.sh
get_certificate


if [ -d ${WORK_DIR}/pki/${HOSTNAME} ]
then
  echo " [i] export PKI vars"

  export ICINGA_API_PKI_PATH=${WORK_DIR}/pki/${HOSTNAME}
  export ICINGA_API_NODE_NAME=${HOSTNAME}
fi
