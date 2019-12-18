# dam-setup

Run `make` for more info

## Setting up NUC

* Update BIOS (F7)
    * Download `.bio` update and put on Flash drive with FAT formatting
    * Start NUC
    * Hit F7
    * Select Flash Update
* Select BIOS config (F2)
    * Boot -> UEFI Boot -> OS Selection -> Linux
    * Boot -> Secure Boot -> Install Intel Platform Key
* Install Ubuntu (F10)
    * Select all defaults
    * Enter info
        * name: dam
        * host: r3c-dam-<CUSTOMER>-<NUM (2 digits)>
        * user: dam
        * password: r3cpresetup
    * Install OpenSSH server
* Login / ssh into box
* `sudo apt install make`
* `git clone git@github.com:RiddleAndCode/dam-setup.git`
* `cd dam-setup`
* `make apt-deps`
* Install docker and docker-compose:
    * `make docker`
    * `make docker-compose`
    * Log in and out for good measure
    * `docker run hello-world` to test
* Enroll Secure boot keys
    * `make import-mok-key` (will reboot system)
    * Select *Enroll*
    * Select *Continue*
    * Enter password
    * Reboot
    * `sudo cat /proc/keys | grep riddle` to test
* Install SGX
    * `make install-sgx-driver`
    * `make sgx-psw`
* Install DAM
    * `make dam-files`
    * `make update-dam-images`
    * `make service`
