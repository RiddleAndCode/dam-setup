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

RUST_ENV := $(HOME)/.cargo/env

.PHONY: all
all: default

.PHONY: default
default: apt-deps docker docker-compose install-sgx-driver linux-sgx-all dam-files

.PHONY: dam-images
dam-images: $(DOCKER_COMPOSE_FILE) $(DOCKER_COMPOSE_LOC)
	docker login
	docker-compose -f $(DOCKER_COMPOSE_FILE) pull

.PHONY: dam-files
dam-files: $(SETTINGS_FILE) $(DOCKER_COMPOSE_FILE) $(RUN_FILE)

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

custodian-solution:
	git clone -b release --recurse-submodules git@github.com:RiddleAndCode/custodian-solution.git

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

linux-sgx-driver/isgx.ko: linux-sgx-driver
	make -C linux-sgx-driver

linux-sgx-driver:
	git clone https://github.com/intel/linux-sgx-driver.git
	# checkout sgx2 here if desired (not recommended for SCONE)

.PHONY: docker-compose
docker-compose: $(DOCKER_INSTALL_LOC)

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
