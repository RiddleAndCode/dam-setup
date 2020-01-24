INSTALL_LOC ?= $(HOME)/dam

PCCS_API_KEY ?= PCCS_API_KEY

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
SGX_PCCS_LOC := $(SGX_INSTALL_LOC)/libsgx-dcap-pccs
SGX_1_COMMIT := 5d6abcc3fed7bb7e6aff09814d9f692999abd4dc

DOCKER_COMPOSE_FILE := $(INSTALL_LOC)/docker-compose.yml
SETTINGS_FILE := $(INSTALL_LOC)/settings.json
RUN_FILE := $(INSTALL_LOC)/run.sh
UPDATE_FILE := $(INSTALL_LOC)/update.sh
SERVICE_FILE := /etc/systemd/system/dam.service

RUST_ENV := $(HOME)/.cargo/env

SGX_DCAP_VERSION := 1.3
INTEL_DOWNLOAD_URL := https://download.01.org/intel-sgx/sgx-dcap/$(SGX_DCAP_VERSION)/linux
INTEL_DOWNLOAD_CHECKSUM := SHA256SUM_dcap_$(SGX_DCAP_VERSION)

OUT_DIR := .out

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
	@echo "sgx-driver         -> build/install the SGX driver (may require reboot for Secure Boot Keys)"
	@echo "sgx-sdk            -> build/install SGX SDK"
	@echo "sgx-dcap           -> build install SGX PSW / DCAP resources"
	@echo "dcap-pccs          -> build install DCAP PCCS service using PCCS_API_KEY"
	@echo "dam-files          -> create the DAM docker-compose file and scripts"
	@echo "update-dam-images  -> downlaod the DAM docker images"
	@echo "service            -> create the DAM systemd service and enable/start it"
	@echo ""
	@echo "part1              -> install process part 1 (do reboot afterwards)"
	@echo "part2              -> install process part 2"
	@echo ""
	@echo "connect-wifi       -> connect to a wifi by WIFI_SSID and WIFI_PSWD"

.PHONY: part1
part1: apt-deps docker docker-compose sgx-driver

.PHONY: part2
part2: sgx-driver sgx-sdk sgx-dcap dcap-pccs dam-files update-dam-images service

.PHONY: update-dam-images
update-dam-images: $(DOCKER_COMPOSE_FILE) $(DOCKER_COMPOSE_LOC)
	docker login
	docker-compose -f $(DOCKER_COMPOSE_FILE) pull
	docker logout

.PHONY: dam-files
dam-files: $(SETTINGS_FILE) $(DOCKER_COMPOSE_FILE) dam-scripts

.PHONY: dam-scripts
dam-scripts: $(RUN_FILE) $(UPDATE_FILE)

$(RUN_FILE): $(INSTALL_LOC)
	cat templates/run.sh | \
		sed "s/%DOCKER_COMPOSE_LOC%/$(subst /,\/,$(DOCKER_COMPOSE_LOC))/g" | \
	       	sed "s/%DOCKER_COMPOSE_FILE%/$(subst /,\/,$(DOCKER_COMPOSE_FILE))/g" > \
		$(RUN_FILE)
	$(SUDO) chmod +x $(RUN_FILE)

$(UPDATE_FILE): $(INSTALL_LOC)
	cat templates/update.sh | \
		sed "s/%DOCKER_COMPOSE_LOC%/$(subst /,\/,$(DOCKER_COMPOSE_LOC))/g" | \
	       	sed "s/%DOCKER_COMPOSE_FILE%/$(subst /,\/,$(DOCKER_COMPOSE_FILE))/g" > \
		$(UPDATE_FILE)
	$(SUDO) chmod +x $(UPDATE_FILE)

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

.PHONY: dcap-pccs
dcap-pccs: $(SGX_PCCS_LOC)/file.crt update-pccs-api-key qcnl-conf
	$(SUDO) $(SGX_PCCS_LOC)/install.sh

.PHONY: update-pccs-api-key
update-pccs-api-key:
	cat $(SGX_PCCS_LOC)/config/default.json | jq '.ApiKey = "$(PCCS_API_KEY)"' > default.json.tmp
	-$(SUDO) rm $(SGX_PCCS_LOC)/config/default.json
	$(SUDO) mv default.json.tmp $(SGX_PCCS_LOC)/config/default.json

.PHONY: qcnl-conf
qcnl-conf:
	-$(SUDO) rm /etc/sgx_default_qcnl.conf
	$(SUDO) cp templates/sgx_default_qcnl.conf /etc/sgx_default_qcnl.conf

.PHONY: sgx-dcap
sgx-dcap: $(OUT_DIR) $(OUT_DIR)/$(INTEL_DOWNLOAD_CHECKSUM)
	for deb in $$(cat $(OUT_DIR)/$(INTEL_DOWNLOAD_CHECKSUM) | grep ubuntuServer18.04 | grep deb | awk '{print $$2}'); do \
		wget $(INTEL_DOWNLOAD_URL)/$$deb -O $(OUT_DIR)/$$(basename $$deb); \
	done
	sudo dpkg -i $(OUT_DIR)/*.deb;
	sudo dpkg -i $(OUT_DIR)/*.ddeb;

.PHONY: sgx-driver
sgx-driver: $(OUT_DIR)/install_driver
	$(SUDO) $(OUT_DIR)/install_driver

.PHONY: sgx-sdk
sgx-sdk: $(OUT_DIR)/install_sdk
	$(SUDO) mkdir -p $(SGX_INSTALL_LOC)
	$(SUDO) $(OUT_DIR)/install_sdk --prefix $(SGX_INSTALL_LOC)
	cat ~/.bashrc | grep $(SOURCE_CMD) || echo $(SOURCE_CMD) >> ~/.bashrc

$(OUT_DIR)/install_driver: $(OUT_DIR) $(OUT_DIR)/$(INTEL_DOWNLOAD_CHECKSUM)
	wget $(INTEL_DOWNLOAD_URL)/$$(cat $(OUT_DIR)/$(INTEL_DOWNLOAD_CHECKSUM) | grep ubuntuServer18.04 | grep bin | grep driver | awk '{print $$2}') \
		-O $(OUT_DIR)/install_driver
	$(SUDO) chmod +x $(OUT_DIR)/install_driver

$(OUT_DIR)/install_sdk: $(OUT_DIR) $(OUT_DIR)/$(INTEL_DOWNLOAD_CHECKSUM)
	wget $(INTEL_DOWNLOAD_URL)/$$(cat $(OUT_DIR)/$(INTEL_DOWNLOAD_CHECKSUM) | grep ubuntuServer18.04 | grep bin | grep sdk | awk '{print $$2}') \
		-O $(OUT_DIR)/install_sdk
	$(SUDO) chmod +x $(OUT_DIR)/install_sdk

$(OUT_DIR)/$(INTEL_DOWNLOAD_CHECKSUM): $(OUT_DIR)
	wget $(INTEL_DOWNLOAD_URL)/$(INTEL_DOWNLOAD_CHECKSUM) -O $(OUT_DIR)/$(INTEL_DOWNLOAD_CHECKSUM)

$(SGX_PCCS_LOC)/file.crt: $(OUT_DIR)/file.crt
	$(SUDO) cp $(OUT_DIR)/private.pem $(SGX_PCCS_LOC)/private.pem
	$(SUDO) cp $(OUT_DIR)/csr.pem $(SGX_PCCS_LOC)/csr.pem
	$(SUDO) cp $(OUT_DIR)/file.crt $(SGX_PCCS_LOC)/file.crt

$(OUT_DIR)/file.crt: $(OUT_DIR)
	openssl genrsa 1024 > $(OUT_DIR)/private.pem
	openssl req -config ./openssl.cnf -new -key $(OUT_DIR)/private.pem -out $(OUT_DIR)/csr.pem
	openssl x509 -req -days 36500 -in $(OUT_DIR)/csr.pem -signkey $(OUT_DIR)/private.pem -out $(OUT_DIR)/file.crt

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
	# newgrp docker

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
		dkms \
		git \
		apt-transport-https \
		ca-certificates \
		npm \
		nodejs \
		jq \
		curl \
		software-properties-common \
		libprotobuf-dev \
		mokutil

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

$(OUT_DIR):
	mkdir -p $(OUT_DIR);
