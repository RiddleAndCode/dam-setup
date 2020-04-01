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
* `git clone -b dcap https://github.com/RiddleAndCode/dam-setup.git`
* `cd dam-setup`
* Copy in the `settings.json` and the `docker-compose.yml` sent to you into `~/dam-setup/settings.json` and `~/dam-setup/docker-compose.yml` respectively
* Part 1
    * `make part1`
    * May ask you to enter a MOK password for the Secure Boot configuration
    * Enroll Secure boot keys if above step happened
        * Reboot system (should enter into MOK screen)
        * Select *Enroll*
        * Select *Continue*
        * Enter password
        * Select *Reboot*
* Part 2
    * Get the PCCS API key from `https://api.portal.trustedservices.intel.com/`
    * `PCCS_API_KEY=<API_KEY> make part2`
* Verify Installation
    * Reboot system
    * Check DAM service status and logs
        * `sudo service dam status`
        * `journalctl -u dam.service`
