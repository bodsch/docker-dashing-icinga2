
FROM bodsch/docker-smashing:1707-27.1

MAINTAINER Bodo Schulz <bodo@boone-schulz.de>

ENV \
  BUILD_DATE="2017-07-27" \
  DASHBOARD="icinga2"

EXPOSE 3030

LABEL \
  version="1707-30" \
  org.label-schema.build-date=${BUILD_DATE} \
  org.label-schema.name="Smashing Icinga2 Docker Image" \
  org.label-schema.description="Inofficial Smashing Icinga2 Docker Image" \
  org.label-schema.url="https://github.com/Smashing/smashing" \
  org.label-schema.vcs-url="https://github.com/bodsch/docker-smashing-icinga2" \
  org.label-schema.vendor="Bodo Schulz" \
  org.label-schema.version=${ICINGA_VERSION} \
  org.label-schema.schema-version="1.0" \
  com.microscaling.docker.dockerfile="/Dockerfile" \
  com.microscaling.license="GNU General Public License v3.0"

# ---------------------------------------------------------------------------------------

RUN \
  apk --no-cache update && \
  apk --no-cache upgrade && \
  apk --no-cache add \
    build-base \
    git \
    openssl-dev \
    ruby-dev \
    openssl-dev \
    supervisor && \
  cd /opt && \
  smashing new ${DASHBOARD} && \
  rm -f /opt/${DASHBOARD}/jobs/twitter* && \
  rm -f /opt/${DASHBOARD}/dashboards/* && \
  cd ${DASHBOARD} && \
  bundle config local.icinga2 /build && \
  sed -i "/gem 'twitter'/d" Gemfile && \
  echo "gem 'icinga2', '~> 0.7'" >> Gemfile && \
  bundle update && \
  apk del --purge \
    build-base \
    git \
    ruby-dev \
    openssl-dev && \
  rm -rf \
    /tmp/* \
    /build \
    /var/cache/apk/* \
    /usr/lib/ruby/gems/current/cache/*

COPY rootfs/ /

WORKDIR /opt/${DASHBOARD}

CMD [ "/init/run.sh" ]

# ---------------------------------------------------------------------------------------

#
