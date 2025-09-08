# Network Configuration

This is a guide for connecting to the internet on LnOS Arch.  
It covers both wired (Ethernet) and wireless (Wi-Fi) setups.

---

## 1. Check Network Devices

Run:

```bash
ip link
```

## 2. Enable Network Interface with DHCP

For wired:
```bash
sudo ip link set enp3s0 up
sudo dhclient enp3s0   # or: sudo dhcpcd enp3s0
```

For wireless:
```bash
sudo ip link set wlp2s0 up
```

## 3. Wi-Fi Login Settings/Configurations

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

## 4. Check Internet Connection

```bash
ping -c 3 ping.archlinux.org
```

## 5. Network Card and Recommendations

If your system does not detect a network card (NIC), the most common reasons are:

- Missing driver – The kernel may not include the correct driver for your hardware (e.g., Realtek `r8168`, Intel Wi-Fi `iwlwifi`).

- Missing firmware – Some devices require additional firmware files. The linux-firmware package covers most cases.

  - For custom builds, ensure `linux-firmware` is listed under `packages.x86_64` or `packages.aarch64`.


Recommendation:

- Verify that your NIC is listed with `ip link`.

- If no device appears, install or enable the appropriate driver and confirm `linux-firmware` is available.

## 6. LnOS @ UTA

If all else fails for UTA students we recommend contacting the club or checking UTA OIT WiFi wireless network page to connect to WiFi internet: https://oit.uta.edu/services/wireless-network/

---
