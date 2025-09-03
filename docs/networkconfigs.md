# Network Configuration

This is a guide for connecting to the internet on LnOS.  
It covers both wired (Ethernet) and wireless (Wi-Fi) setups.

---

## 1. See if the device shows up

Run:

```bash
ip link
```

## 2. Bring up the link manually

For wired:
```bash
sudo ip link set enp3s0 up
sudo dhclient enp3s0   # or: sudo dhcpcd enp3s0
```

For wireless:
```bash
sudo ip link set wlp2s0 up
```

## 3. If using Wi-Fi

Check available networks:
```bash
nmcli dev wifi list

# or

nmcli device wifi list
```

Connect:

```bash
nmcli dev wifi connect "SSID" password "PASSWORD"

# or

nmcli device wifi connect "eduroam" \
    --ask
```

## 4. Verify internet

```bash
ping -c 3 archlinux.org
```

## 5. If no NIC shows up

That usually means:

Missing driver module in `mkinitcpio.conf` or packages list (e.g. `r8168`, `iwlwifi)`.

Sometimes needs firmware (`linux-firmware` should cover most cases — can add it in `packages.x86_64`/`packages.aarch64`).

## 6. LnOS @ UTA

If all else fails for UTA students I recommend checking UTA OIT WiFi guidelines to connect to WiFi internet: https://oit.uta.edu/services/wireless-network/

---
