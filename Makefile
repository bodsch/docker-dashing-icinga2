
include env_make

NS       = bodsch
VERSION ?= latest

REPO     = docker-dashing-icinga2
NAME     = dashing-icinga2
INSTANCE = default

BUILD_DATE := $(shell date +%Y-%m-%d)
BUILD_VERSION := $(shell date +%y%m)
DASHBOARD ?= "icinga2"
ICINGA2_GEM_TYPE ?= "stable"
ICINGA2_GEM_VERSION ?= "1.0.0"

.PHONY: build push shell run start stop rm release


build:
	docker build \
		--force-rm \
		--compress \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg BUILD_VERSION=$(BUILD_VERSION) \
		--build-arg DASHBOARD=$(DASHBOARD) \
		--build-arg ICINGA2_GEM_TYPE=$(ICINGA2_GEM_TYPE) \
		--build-arg ICINGA2_GEM_VERSION=$(ICINGA2_GEM_VERSION) \
		--tag $(NS)/$(REPO):$(BUILD_VERSION) .

clean:
	docker rmi \
		--force \
		$(NS)/$(REPO):$(BUILD_VERSION)

history:
	docker history \
		$(NS)/$(REPO):$(BUILD_VERSION)

push:
	docker push \
		$(NS)/$(REPO):$(BUILD_VERSION)

shell:
	docker run \
		--rm \
		--name $(NAME)-$(INSTANCE) \
		--interactive \
		--tty \
		$(PORTS) \
		$(VOLUMES) \
		$(ENV) \
		$(NS)/$(REPO):$(BUILD_VERSION) \
		/bin/sh

run:
	docker run \
		--rm \
		--name $(NAME)-$(INSTANCE) \
		$(PORTS) \
		$(VOLUMES) \
		$(ENV) \
		$(NS)/$(REPO):$(BUILD_VERSION)

exec:
	docker exec \
		--interactive \
		--tty \
		$(NAME)-$(INSTANCE) \
		/bin/sh

start:
	docker run \
		--detach \
		--name $(NAME)-$(INSTANCE) \
		$(PORTS) \
		$(VOLUMES) \
		$(ENV) \
		$(NS)/$(REPO):$(BUILD_VERSION)

stop:
	docker stop \
		$(NAME)-$(INSTANCE)

rm:
	docker rm \
		$(NAME)-$(INSTANCE)

release: build
	make push -e VERSION=$(BUILD_VERSION)

default: build
