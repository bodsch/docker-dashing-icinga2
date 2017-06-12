#!/bin/sh

AUTH_TOKEN=${AUTH_TOKEN:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)}

# ICINGA_HOST=${ICINGA2_HOST:-""}
# ICINGA_PORT=${ICINGA2_PORT:-"5665"}
# ICINGA_API_USER=${ICINGA_API_USER:-"dashing"}
# ICINGA_API_PASSWORD=${ICINGA_API_PASSWORD:-"icinga"}
# ICINGAWEB_HOST=${ICINGAWEB_HOST:-"icingaweb2"}
# ICINGAWEB_PATH=${ICINGAWEB_PATH:-"/icingaweb2"}
ICINGAWEB_URL=${ICINGAWEB_URL:-"http://localhost/icingaweb2"}
PROXY_PATH=${PROXY_PATH:-""}


#GRAPHITE_HOST=${GRAPHITE_HOST:-""}
#GRAPHITE_PORT=${GRAPHITE_PORT:-8080}

DASHBOARD=${DASHBOARD:-icinga2}


DASHING_PATH="/opt/${DASHBOARD}"
CONFIG_FILE="${DASHING_PATH}/config.ru"

# -------------------------------------------------------------------------------------------------


  if [ -f ${CONFIG_FILE} ]
  then
    sed -i 's|%AUTH_TOKEN%|'${AUTH_TOKEN}'|g' ${CONFIG_FILE}
  fi

  icinga_dashboard="${DASHING_PATH}/dashboards/icinga2.erb"

  if [ -f ${icinga_dashboard} ]
  then
    sed -i \
      -e 's|%ICINGAWEB_URL%|'${ICINGAWEB_URL}'|g' \
      -e 's|%PROXY_PATH%|'${PROXY_PATH}'|g' \
      ${icinga_dashboard}
  fi

  if [ ! -z ${PROXY_PATH} ]
  then

    layout="${DASHING_PATH}/dashboards/layout.erb"

    if [ -f ${layout} ]
    then
      sed -i \
        -e 's|%PROXY_PATH%|'${PROXY_PATH}'|g' \
        ${layout}
    fi

    sed -i \
      -e 's|%DASHBOARD%|'${DASHBOARD}'|g' \
      -e 's|%PROXY_PATH%|'${PROXY_PATH}'|g' \
        ${CONFIG_FILE}
  fi

  echo -e "\n"
  echo " ==================================================================="
  echo " Dashing AUTH_TOKEN set to '${AUTH_TOKEN}'"
  echo " ==================================================================="
  echo ""



# -------------------------------------------------------------------------------------------------

echo -e "\n Starting Supervisor.\n\n"

if [ -f /etc/supervisord.conf ]
then
  /usr/bin/supervisord -c /etc/supervisord.conf >> /dev/null
fi


# EOF
