INSTALL_LOC := $(HOME)/dam

WIFI_SSID ?= R3C-DEMO
WIFI_PSWD ?= DEMO&R3C

SUDO := sudo
USER := $(shell whoami)
UBUNTU_NAME := bionic
UNAME_R := $(shell uname -r)

DOCKER_COMPOSE_VER := 1.25.0
DOCKER_COMPOSE_LOC := /usr/local/bin/docker-compose

SGX_INSTALL_LOC := /opt/intel
SOURCE_CMD := "source $(SGX_INSTALL_LOC)/sgxsdk/environment"

DOCKER_COMPOSE_FILE := $(INSTALL_LOC)/docker-compose.yml
SETTINGS_FILE := $(INSTALL_LOC)/settings.json
RUN_FILE := $(INSTALL_LOC)/run.sh
SERVICE_FILE := /etc/systemd/system/dam.service

RUST_ENV := $(HOME)/.cargo/env

.PHONY: default
default: help

.PHONY: default
help:
	@echo "TARGETS"
	@echo ""
	@echo "help               -> show this message"
	@echo ""
	@echo "apt-deps           -> install ubuntu package dependencies with 'apt-get'"
	@echo "docker             -> install docker"
	@echo "docker-compose     -> install docker-compose"
	@echo "install-sgx-driver -> build/install the SGX driver"
	@echo "linux-sgx-all      -> build/install SGX SDK and PSW"
	@echo "dam-files          -> create the docker-compose, settings.json and run script for DAM"
	@echo "update-dam-images  -> pull the newest images for the docke compose file"
	@echo "service            -> create the systemd service and enable/start it"
	@echo "all                -> do all of the above"
	@echo ""
	@echo "connect-wifi       -> connect to a wifi by WIFI_SSID and WIFI_PSWD"

.PHONY: all
all: apt-deps docker docker-compose install-sgx-driver linux-sgx-all dam-files update-dam-images service

.PHONY: update-dam-images
update-dam-images: $(DOCKER_COMPOSE_FILE) $(DOCKER_COMPOSE_LOC)
	docker login
	docker-compose -f $(DOCKER_COMPOSE_FILE) pull
	# docker logout

.PHONY: dam-files
dam-files: $(SETTINGS_FILE) $(DOCKER_COMPOSE_FILE) dam-scripts

.PHONY: dam-files
dam-scripts: $(RUN_FILE)

$(RUN_FILE): $(INSTALL_LOC)
	cat templates/run.sh | \
		sed "s/%DOCKER_COMPOSE_LOC%/$(subst /,\/,$(DOCKER_COMPOSE_LOC))/g" | \
	       	sed "s/%DOCKER_COMPOSE_FILE%/$(subst /,\/,$(DOCKER_COMPOSE_FILE))/g" > \
		$(RUN_FILE)
	$(SUDO) chmod +x $(RUN_FILE)

$(SETTINGS_FILE): $(INSTALL_LOC) custodian-solution
	cp custodian-solution/settings.json $(SETTINGS_FILE)

$(DOCKER_COMPOSE_FILE): $(RUST_ENV) $(INSTALL_LOC) custodian-solution
	. $(RUST_ENV) && \
		make -C custodian-solution compose
	cp custodian-solution/docker-compose.yml $(DOCKER_COMPOSE_FILE)

$(INSTALL_LOC):
	mkdir -p $(INSTALL_LOC)

.PHONY: clean-dam
clean-dam:
	if [ -d "$(INSTALL_LOC)" ]; then \
		rm -rf $(INSTALL_LOC); \
	fi

.PHONY: rebuild-dam
rebuild-dam: clean-dam clean-custodian-solution dam-files


custodian-solution:
	git clone -b release --recurse-submodules git@github.com:RiddleAndCode/custodian-solution.git

.PHONY: clean-custodian-solution
clean-custodian-solution:
	if [ -d custodian-solution ]; then \
		rm -rf custodian-solution; \
	fi

.PHONY: service
service: dam-scripts $(SERVICE_FILE)
	$(SUDO) systemctl start dam
	$(SUDO) systemctl enable dam

$(SERVICE_FILE):
	cat templates/dam.service | \
		sed "s/%USER%/$(USER)/g" | \
		sed "s/%RUN_FILE%/$(subst /,\/,$(RUN_FILE))/g" > \
		dam.service.tmp
	$(SUDO) mv dam.service.tmp $(SERVICE_FILE)

.PHONY: clean-service
clean-service:
	$(SUDO) systemctl stop dam
	$(SUDO) systemctl disable dam
	$(SUDO) rm $(SERVICE_FILE)

.PHONY: rebuild-service
rebuild-service: clean-service service

.PHONY: linux-sgx-all
linux-sgx-all: linux-sgx-sdk install-linux-sgx-sdk linux-sgx-psw install-linux-sgx-psw

.PHONY: install-linux-sgx-psw
install-linux-sgx-psw:
	$(SUDO) dpkg -i ./linux-sgx/linux/installer/deb/*.deb

.PHONY: install-linux-sgx-sdk
install-linux-sgx-sdk:
	$(SUDO) mkdir -p $(SGX_INSTALL_LOC)
	$(SUDO) ./linux-sgx/linux/installer/bin/*.bin --prefix $(SGX_INSTALL_LOC)
	cat ~/.bashrc | grep $(SOURCE_CMD) || echo $(SOURCE_CMD) >> ~/.bashrc

.PHONY: linux-sgx-sdk
linux-sgx-sdk: linux-sgx
	make -C linux-sgx sdk
	make -C linux-sgx sdk_install_pkg

.PHONY: linux-sgx-psw
linux-sgx-psw: linux-sgx
	make -C linux-sgx psw
	make -C linux-sgx deb_pkg

linux-sgx:
	git clone https://github.com/intel/linux-sgx.git
	linux-sgx/download_prebuilt.sh

.PHONY: install-sgx-driver
install-sgx-driver: sgx-driver 
	$(SUDO) mkdir -p "/lib/modules/$(UNAME_R)/kernel/drivers/intel/sgx"    
	$(SUDO) cp linux-sgx-driver/isgx.ko "/lib/modules/$(UNAME_R)/kernel/drivers/intel/sgx"    
	$(SUDO) sh -c "cat /etc/modules | grep -Fxq isgx || echo isgx >> /etc/modules"    
	$(SUDO) /sbin/depmod
	$(SUDO) /sbin/modprobe isgx

.PHONY: uninstall-sgx-driver
uninstall-sgx-driver:
	-$(SUDO) /sbin/modprobe -r isgx
	-$(SUDO) rm -rf "/lib/modules/$(UNAME_R)/kernel/drivers/intel/sgx"
	-$(SUDO) /sbin/depmod
	-$(SUDO) /bin/sed -i '/^isgx$$/d' /etc/modules

.PHONY: clean-sgx-driver
clean-sgx-driver:
	-make -C linux-sgx-driver clean

.PHONY: rebuild-sgx-driver
rebuild-sgx-driver: uninstall-sgx-driver clean-sgx-driver sgx-driver install-sgx-driver

sgx-driver: linux-sgx-driver/isgx.ko

linux-sgx-driver/isgx.ko: linux-sgx-driver MOK.der
	make -C linux-sgx-driver
	kmodsign sha512 MOK.priv MOK.der linux-sgx-driver/isgx.ko

linux-sgx-driver:
	git clone https://github.com/intel/linux-sgx-driver.git
	# checkout sgx2 here if desired (not recommended for SCONE)

.PHONY: docker-compose
docker-compose: $(DOCKER_COMPOSE_LOC)

$(DOCKER_COMPOSE_LOC):
	$(SUDO) curl -L "https://github.com/docker/compose/releases/download/$(DOCKER_COMPOSE_VER)/docker-compose-$(shell uname -s)-$(shell uname -m)" \
		-o $(DOCKER_COMPOSE_LOC)
	$(SUDO) chmod +x $(DOCKER_COMPOSE_LOC)

.PHONY: docker
docker: docker-repo
	$(SUDO) apt-get -y install docker-ce
	$(SUDO) usermod -aG docker $(USER)
	newgrp docker

.PHONY: docker-repo
docker-repo:
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $(SUDO) apt-key add -
	$(SUDO) add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(UBUNTU_NAME) stable"

MOK.der:
	openssl req -config ./openssl.cnf \
		-new -x509 -newkey rsa:2048 \
		-nodes -days 36500 -outform DER \
		-keyout "MOK.priv" \
		-out "MOK.der"

.PHONY: apt-deps
apt-deps:
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y \
		linux-headers-$(UNAME_R) \
		build-essential \
		git \
		apt-transport-https \
		ca-certificates \
		curl \
		software-properties-common \
		ocaml \
		ocamlbuild \
		automake \
		autoconf \
		libtool \
		wget \
		python \
		libssl-dev \
		libcurl4-openssl-dev \
		libprotobuf-dev \
		protobuf-compiler \
		debhelper \
		mokutil \
		cmake

$(RUST_ENV):
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

.PHONY: connect-wifi
connect-wifi: connect-wifi-deps
	$(SUDO) systemctl enable NetworkManager
	$(SUDO) systemctl start NetworkManager
	$(SUDO) nmcli device wifi rescan
	$(SUDO) nmcli device wifi connect $(WIFI_SSID) password '$(WIFI_PSWD)'

.PHONY: connect-wifi-deps
connect-wifi-deps:
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y network-manager
