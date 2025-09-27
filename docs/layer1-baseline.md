# **Scope:** Manjaro ARM base, first-boot wizard disabled, oneshot provisioner, Wi-Fi auto connect, user `username` (wheel), TZ/locale/keymap/hostname preseeded.

## Makefile knobs
- `IMG_URL` (Manjaro rpi4 minimal)
- `BOOT_LABEL=BOOT_MNJRO`, `ROOT_LABEL=ROOT_MNJRO` (distro defaults)
- `WIFI_SSID`, `WIFI_PASS` (from Makefile or `sysclone.local.mk`)
- `DEVICE` (only runtime override)

***
## Sanity (on Pi)
systemctl status sysclone-first-boot --no-pager
test -f /var/lib/sysclone/first-boot.done && echo stamp:present
hostnamectl; timedatectl | grep "Time zone"; localectl
iw dev; ip -br addr | grep -E 'wl|wlan'
journalctl -u iwd -b --no-pager | tail -n 60
******
Workflow - Download (cache) / Image
- make img-download
* make img-unpack
* make sd-write
******
Workflow - Layer1 (Foundation)
- make ensure-mounted
* make clear-layer1-stamps
* make seed-layer1-disable-first-boot
* make seed-layer1-first-boot-service
* make ensure-unmounted

**************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************
Workflow - Layer2 (Wayland)
- make seed-layer2-wayland
* make seed-layer2-sway
******
Workflow - Layer2.5 (DM)
- make seed-layer2.5-greetd
