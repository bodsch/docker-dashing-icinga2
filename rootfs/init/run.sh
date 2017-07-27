#!/bin/sh

AUTH_TOKEN=${AUTH_TOKEN:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)}

ICINGAWEB_URL=${ICINGAWEB_URL:-"http://localhost/icingaweb2"}
PROXY_PATH=${PROXY_PATH:-""}

DASHBOARD=${DASHBOARD:-icinga2}

DASHING_PATH="/opt/${DASHBOARD}"
CONFIG_FILE="${DASHING_PATH}/config.ru"

export WORK_DIR=/srv

# -------------------------------------------------------------------------------------------------

. /init/configure_smashing.sh
. /init/icinga_cert.sh

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
