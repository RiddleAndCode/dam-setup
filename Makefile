help:
	@echo "View README for more info"
.PHONY: help

# SGX Driver

sgx-driver: install-sgx-driver sign-sgx-driver

install-sgx-driver:
	curl -s https://download.01.org/intel-sgx/latest/linux-latest/distro/ubuntu20.04-server/driver_readme.txt | awk '{ print $$3 }' |  grep -v "^#\|^$$" | head -n 1 | awk '{print "https://download.01.org/intel-sgx/latest/linux-latest/distro/ubuntu20.04-server/"$$1}' | xargs curl -o /tmp/install-sgx-driver
	sudo chmod +x /tmp/install-sgx-driver
	sudo /tmp/install-sgx-driver
.PHONY: install-sgx-driver

sign-sgx-driver:
	sudo /usr/src/linux-headers-$$(uname -r)/scripts/sign-file sha256 /usr/modules/MOK.priv /usr/modules/MOK.der $$(modinfo -n isgx)
	sudo modprobe isgx
.PHONY: sign-sgx-driver

# MOK key

mok-key: /usr/modules/MOK.der
	sudo mokutil --import /usr/modules/MOK.der
.PHONY: create-mok-key

/usr/modules/MOK.der:
	openssl req -new -x509 -newkey rsa:4096 -keyout MOK.priv -outform DER -out MOK.der -nodes -days 36500 -subj "/CN=Driver Signer/"
	sudo mkdir -p /usr/modules
	sudo mv MOK.der /usr/modules
	sudo mv MOK.priv /usr/modules
	sudo chown -R root:root /usr/modules

# PSW / aesmd service / SGX SDK

sgx-sdk: apt-repos apt-get

apt-repos:
	curl -s https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | sudo apt-key add -
	echo 'deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu $(shell lsb_release -cs) main' | sudo tee /etc/apt/sources.list.d/intel-sgx.list
.PHONY: apt-repos

apt-get:
	sudo apt-get update
	sudo apt-get install -y \
		build-essential \
		libsgx-enclave-common-dev \
		libsgx-headers \
		libssl-dev \
		sgx-aesm-service
.PHONY: apt-get


.PHONY: rebuild-sgx-driver
rebuild-sgx-driver: uninstall-sgx-driver clean-sgx-driver sgx-driver install-sgx-driver

.PHONY: uninstall-sgx-driver
uninstall-sgx-driver:
	-$(SUDO) /sbin/modprobe -r isgx
	-$(SUDO) rm -rf "/lib/modules/$(UNAME_R)/kernel/drivers/intel/sgx"
	-$(SUDO) /sbin/depmod
	-$(SUDO) /bin/sed -i '/^isgx$$/d' /etc/modules

.PHONY: clean-sgx-driver
clean-sgx-driver:
	-make -C linux-sgx-driver clean

.PHONY: sgx-driver
sgx-driver: linux-sgx-driver/isgx.ko

linux-sgx-driver/isgx.ko: linux-sgx-driver MOK.der
	make -C linux-sgx-driver
	kmodsign sha512 MOK.priv MOK.der linux-sgx-driver/isgx.ko

linux-sgx-driver:
	git clone https://github.com/01org/linux-sgx-driver

MOK.der:
	openssl req -config ./openssl.cnf \
		-new -x509 -newkey rsa:2048 \
		-nodes -days 36500 -outform DER \
		-keyout "MOK.priv" \
		-out "MOK.der"
