
FROM bodsch/docker-dashing:1712-r1

ENV \
  BUILD_DATE="2017-12-22" \
  DASHBOARD="icinga2" \
  ICINGA2_GEM_VERSION="0.9"

EXPOSE 3030

LABEL \
  version="1712" \
  maintainer="Bodo Schulz <bodo@boone-schulz.de>" \
  org.label-schema.build-date=${BUILD_DATE} \
  org.label-schema.name="Dashing Icinga2 Docker Image" \
  org.label-schema.description="Inofficial Dashing Icinga2 Docker Image" \
  org.label-schema.url="https://github.com/Smashing/smashing" \
  org.label-schema.vcs-url="https://github.com/bodsch/docker-dashing-icinga2" \
  org.label-schema.vendor="Bodo Schulz" \
  org.label-schema.version=${ICINGA_VERSION} \
  org.label-schema.schema-version="1.0" \
  com.microscaling.docker.dockerfile="/Dockerfile" \
  com.microscaling.license="GNU General Public License v3.0"

# ---------------------------------------------------------------------------------------

COPY build /build

RUN \
  apk update  --quiet --no-cache && \
  apk upgrade --quiet --no-cache && \
  apk add --quiet --virtual .build-deps \
    build-base git ruby-dev openssl-dev && \
  apk add --quiet --no-cache \
    jq \
    supervisor && \
  cd /opt && \
  smashing new ${DASHBOARD} && \
  rm -f /opt/${DASHBOARD}/jobs/twitter* && \
  rm -f /opt/${DASHBOARD}/dashboards/* && \
  cd ${DASHBOARD} && \
  bundle config local.icinga2 /build && \
  sed -i "/gem 'twitter'/d" Gemfile && \
  cd /opt/${DASHBOARD} && \
  count=$(ls -1 /build/*.gem 2> /dev/null | tail -n1) && \
  if [ ! -z ${count} ] ; then \
    gem install --no-rdoc --no-ri ${count} ; \
  else \
    echo "gem 'icinga2', '~> ${ICINGA2_GEM_VERSION}'" >> Gemfile ; \
  fi && \
  bundle update && \
  apk del --quiet --purge .build-deps && \
  rm -rf \
    /tmp/* \
    /build \
    /var/cache/apk/* \
    /usr/lib/ruby/gems/current/cache/* \
    /root/.gem \
    /root/.bundle

COPY rootfs/ /

WORKDIR /opt/${DASHBOARD}

CMD [ "/init/run.sh" ]

# ---------------------------------------------------------------------------------------
