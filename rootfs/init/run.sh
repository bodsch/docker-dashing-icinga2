#!/bin/sh

AUTH_TOKEN=${AUTH_TOKEN:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)}

# ICINGAWEB_URL=${ICINGAWEB_URL:-"http://localhost/icingaweb2"}
# PROXY_PATH=${PROXY_PATH:-""}
#
# DASHBOARD=${DASHBOARD:-icinga2}
#
# DASHING_PATH="/opt/${DASHBOARD}"
# CONFIG_FILE="${DASHING_PATH}/config.ru"

. /init/output.sh

export WORK_DIR=/srv

# -------------------------------------------------------------------------------------------------

. /init/configure_smashing.sh
. /init/icinga_cert.sh

log_info "==================================================================="
log_info " Dashing AUTH_TOKEN set to '${AUTH_TOKEN}'"
log_info "==================================================================="

# -------------------------------------------------------------------------------------------------

log_info "Starting Supervisor."

if [ -f /etc/supervisord.conf ]
then
  :
  /usr/bin/supervisord -c /etc/supervisord.conf >> /dev/null
fi


# EOF
