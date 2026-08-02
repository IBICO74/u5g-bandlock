# u5g-bandlock

Persistent LTE/5G **band locking** for Ubiquiti **UniFi U5G modems** (U5G,
U5G-Max, U5G-Max-Outdoor) — from any Linux box on your LAN. No third-party
code on the gateway, no firmware patching.

## The problem

In 5G **NSA** mode the connection is anchored to an LTE carrier. If that
anchor lands on a noisy band (strong RSRP but poor SINR), the whole session
tears down and re-attaches — short 1–3 minute WAN drops, a new CGNAT address
every time, and occasionally a modem watchdog reset (`MBB_SIM_INSERTED` in the
UniFi system log without anyone touching the SIM).

UniFi intentionally offers **no band selection in the UI** (a feature request
has been open since 2022), and the modem stores radio preferences in **tmpfs**
— anything you set is lost on every reboot.

Real-world result that motivated this tool: anchor forced from B3
(SINR 7 dB, frequent drops) to B7 → SINR 11.2 dB, stable session.

## How it works

`apply.sh` runs from a systemd timer (default: every 15 min) on any Linux
machine that can reach the modem's LAN IP:

1. Fetches the **device SSH password** live from the UniFi Network API
   (`X-API-KEY` auth) — or uses a static one from the config.
2. SSHes to the modem and reads the current preference with
   `uiwwand-ctl get-radio-pref`.
3. If it differs from your configured band list, re-applies it with
   `set-radio-pref`.

The modem only honors a new list at its next (re-)registration — reboot it
once from the console after the first apply. After that, the timer keeps the
preference alive across modem reboots and firmware updates.

## Install

```bash
git clone https://github.com/IBICO74/u5g-bandlock /opt/u5g-bandlock
cp /opt/u5g-bandlock/env.example /root/.config/u5g-bandlock/env
chmod 600 /root/.config/u5g-bandlock/env   # edit: modem IP, ICCID, bands, API key
ln -s /opt/u5g-bandlock/u5g-bandlock.{service,timer} /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now u5g-bandlock.timer
systemctl start u5g-bandlock.service && journalctl -u u5g-bandlock -n 3
```

Dependencies: `bash`, `curl`, `jq`, `sshpass`, `ssh`.

## Revert

```bash
systemctl disable --now u5g-bandlock.timer
```
…then reboot the modem from the UniFi console — tmpfs means it boots straight
back to factory band behavior (`automatic`, all bands).

## Notes & credits

- Tested on U5G-Max-Outdoor (UMBBE631, fw 7.5.3) with UniFi Network 10.5 on a
  UDM-SE. Should work on any `UMBBE*` model.
- Inspired by [FRooter/u5g-bandfix](https://github.com/FRooter/u5g-bandfix),
  which runs *on the Cloud Gateway* with MongoDB + key installs. This tool
  deliberately keeps the gateway untouched: any LAN host, password auth via
  the official API, ~50 lines of bash.
- Band prefs are carrier-dependent — pick allowed bands from what your
  carrier actually deploys, and always leave more than one LTE band in the
  list so the modem has somewhere to go.
- Use at your own risk; this drives an undocumented on-modem CLI
  (`uiwwand-ctl`). A modem reboot always restores factory behavior.
