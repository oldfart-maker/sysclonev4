# sysclone — Layer 1 Baseline (v0.2.x)

**Scope:** Manjaro ARM base, first-boot wizard disabled, oneshot provisioner, Wi-Fi auto connect, user `username` (wheel), TZ/locale/keymap/hostname preseeded.

## Makefile knobs
- `IMG_URL` (Manjaro rpi4 minimal)
- `BOOT_LABEL=BOOT_MNJRO`, `ROOT_LABEL=ROOT_MNJRO` (distro defaults)
- `WIFI_SSID`, `WIFI_PASS` (from Makefile or `sysclone.local.mk`)
- `DEVICE` (only runtime override)

## Primary targets
- `flash-all DEVICE=/dev/sdX CONFIRM=yes`
- `seed-all`
- `help` / `help TARGET=name`
- `show-config`

## Seeders (host)
- `tools/seed-disable-firstboot.sh`
- `tools/seed-layer1-auto.sh`
- `tools/seed-first-boot-service.sh`

## Payload (Pi)
- `/usr/local/sbin/sysclone-first-boot.sh` (Wi-Fi via iwctl)
- `/usr/local/lib/sysclone/first-boot-provision.sh` (create user, set tz/locale/keymap/hostname, stamp)
- `sysclone-first-boot.service` (oneshot)

## Typical flow
make flash-all DEVICE=/dev/sdX CONFIRM=yes
make seed-all

## Sanity (on Pi)
systemctl status sysclone-first-boot --no-pager
test -f /var/lib/sysclone/first-boot.done && echo stamp:present
hostnamectl; timedatectl | grep "Time zone"; localectl
iw dev; ip -br addr | grep -E 'wl|wlan'
journalctl -u iwd -b --no-pager | tail -n 60
