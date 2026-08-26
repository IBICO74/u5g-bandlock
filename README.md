# u5g-bandlock

**Lock your UniFi 5G modem to specific LTE/5G bands — and make it stick.**

For Ubiquiti **U5G**, **U5G-Max** and **U5G-Max-Outdoor** modems. Runs from any
Linux box on your LAN (or a Docker container). Nothing is installed on your
gateway, and no firmware is modified.

---

## Do I need this?

You probably do if your 5G WAN **drops for 1–3 minutes at a time, several times
a week**, even though the UniFi console shows a strong signal.

Check the UniFi console under **Internet → your 5G WAN**. The tell-tale pattern:

| What you see | What it means |
|---|---|
| `Primary Tech: 5G NSA` | Your 5G rides on an LTE "anchor" band. If the anchor stumbles, the whole connection drops. |
| **Signal strength (RSRP) is good** (better than −90 dBm) | The tower is close enough — distance is *not* your problem. |
| **LTE Radio Health (SINR) is poor** (below ~10 dB) | The anchor band is noisy. This is what tears down your connection. |
| A new IP address after every drop | The modem isn't just losing packets — it's re-registering from scratch. |

In the UniFi system log (**Settings → System Log**, filter *Internet & WAN*)
the same problem looks like repeated `NETWORK_WAN_FAILED` / `RESTORED` pairs,
often with `ISP_PACKET_LOSS` just before, and sometimes `MBB_SIM_INSERTED`
(the modem resetting itself) even though nobody touched the SIM.

**Real example this tool was built for:** anchor stuck on B3 with SINR 7 dB and
RSRP −70 dBm. Excluding B3 moved the anchor to B7 → **SINR 11.2 dB** and a
stable session. Same hardware, same location, same tower — just a quieter band.

## Why a tool at all?

Two obstacles, both outside your control:

1. **UniFi has no band selection in the UI.** Ubiquiti considers band choice a
   carrier matter; the [feature request has been open since 2022](https://community.ui.com/questions/UniFi-5G-Max-Outdoor/e0f504e3-7b9d-41f2-bb39-54d913fe8229).
   The setting *does* exist on the modem, via an undocumented CLI
   (`uiwwand-ctl`) reachable over SSH.
2. **The modem forgets.** Its config lives in tmpfs, so any band preference is
   wiped on every reboot — including reboots the modem does on its own.

So the fix is: set the preference over SSH, then keep re-applying it. That's
all this tool does — one ~50-line bash script on a timer.

## What you need before starting

- A **UniFi U5G modem** (`UMBBE*` model) adopted in UniFi Network.
- **Device SSH enabled**: console → **Settings → System → Device SSH
  Authentication**. Note the username; the password is fetched automatically if
  you use an API key (below).
- A **UniFi API key** (recommended, so a rotated SSH password doesn't break
  things): console → **Settings → Control Plane → Integrations → Create API Key**.
  Alternatively skip it and hardcode the SSH username/password.
- Your SIM's **ICCID** — visible in the UniFi console on the 5G WAN page, or by
  running `cat /etc/uiwwand.json` on the modem over SSH.
- A **Linux host on the same LAN** that can reach the modem's IP, with either
  Docker, or `bash curl jq sshpass openssh-client` installed.

### Choosing bands

List the bands your carrier actually deploys in your area (a cell-mapping app
or your carrier's coverage page will tell you), then **remove the noisy one**
you identified above. Two rules:

- **Always leave several bands in the list.** If you allow only one and it's
  unavailable where you are, the modem has nowhere to go and you lose the WAN
  entirely.
- **Don't touch the 5G bands** unless the 5G leg itself is the problem — in NSA
  mode it's usually the LTE anchor that misbehaves.

`LTE_BAND=1,7,20,28` in the examples means "any of B1/B7/B20/B28, but never
B3". Numbers are plain LTE band numbers.

---

## Install with Docker (easiest)

```bash
git clone https://git.protonord.no/Protonord_public/u5g-bandlock && cd u5g-bandlock
```

Then edit `docker-compose.yml`:

```yaml
# docker-compose.yml
services:
  u5g-bandlock:
    build: .
    container_name: u5g-bandlock
    restart: unless-stopped
    environment:
      MODEM_IP: 192.168.1.53
      ICCID: "8947000000000000000"
      LTE_BAND: "1,7,20,28"
      NR5G_SA_BAND: "1,3,28,78"
      INTERVAL: 900                 # check every 15 min
      UNIFI_HOST: 192.168.1.1
      UNIFI_API_KEY: your-api-key
```

```bash
docker compose up -d --build
docker compose logs -f      # expect: "ok: lte_band=1,7,20,28"
```

The container needs normal LAN access to the modem and the console — no host
networking, no privileges.

## Install with systemd

```bash
git clone https://github.com/IBICO74/u5g-bandlock /opt/u5g-bandlock
mkdir -p /root/.config/u5g-bandlock
cp /opt/u5g-bandlock/env.example /root/.config/u5g-bandlock/env
chmod 600 /root/.config/u5g-bandlock/env      # then edit it
ln -s /opt/u5g-bandlock/u5g-bandlock.service /etc/systemd/system/
ln -s /opt/u5g-bandlock/u5g-bandlock.timer /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now u5g-bandlock.timer
systemctl start u5g-bandlock.service && journalctl -u u5g-bandlock -n 5
```

## One-time step after the first run

Setting the preference does **not** disturb the connection that's already up —
the modem only picks new bands when it next registers. Reboot the modem once
(UniFi console → the modem → **Restart**) to force a re-attach.

Afterwards, verify in the console that **LTE Radio Health (SINR)** improved and
that the band changed. From then on the tool keeps the preference alive on its
own; you'll see `drift: lte_band was «…» — re-applying …` in the logs after
each modem reboot.

## Undo

```bash
docker compose down          # or: systemctl disable --now u5g-bandlock.timer
```
Then reboot the modem from the console. Because of the tmpfs behaviour it comes
straight back to factory defaults (`automatic`, all bands) — there is nothing
left behind to clean up.

## Configuration reference

| Variable | Required | Meaning |
|---|---|---|
| `MODEM_IP` | yes | The modem's LAN IP |
| `ICCID` | yes | SIM ICCID |
| `LTE_BAND` | yes | Allowed LTE bands, comma-separated |
| `NR5G_SA_BAND` | no | Allowed 5G SA bands |
| `MODE` | no | Radio access modes, default `5gnr,lte` |
| `UNIFI_HOST` + `UNIFI_API_KEY` | either this… | Fetch device SSH password live from the Network API |
| `MODEM_USER` + `MODEM_SSH_PASSWORD` | …or this | Static SSH credentials |
| `INTERVAL` | Docker only | Seconds between checks (default 900) |

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Permission denied (publickey,password)` | Device SSH is off, or the username differs — check Settings → System → Device SSH Authentication |
| `{"error":-1}` from the modem | Wrong ICCID, or a method your firmware doesn't expose |
| `curl: (22) The requested URL returned error: 401` | Wrong or revoked UniFi API key |
| `curl: (22) … error: 502`/`503` | The UniFi console is restarting or unreachable (e.g. nightly maintenance) — transient, the next run recovers |
| Band never changes | You haven't rebooted the modem since the first apply |
| WAN goes down after locking | Your allowed list has no band available here — widen it and reboot the modem |

## Dependencies

| What | Details |
|---|---|
| UniFi Network API | `GET https://<console>/proxy/network/api/s/default/get/setting` with an `X-API-KEY` header; the `mgmt` object carries `x_ssh_username`/`x_ssh_password` (device SSH credentials). Read-only — nothing is written to the console. Answers HTML/5xx while the console restarts, which shows up as one failed run. |
| Modem `uiwwand-ctl` (undocumented) | JSON-RPC on stdin over SSH (Dropbear, password auth via `sshpass`): `get-radio-pref` and `set-radio-pref` with `iccid`, `mode`, `lte_band`, `nr5g_sa_band`. The preference lives in tmpfs on the modem. |
| Runtime | `bash curl jq sshpass openssh-client`; the Docker image is `alpine:3.20` with the same packages. No image is published — `docker compose` builds it locally. |
| Protonord's own instance | The systemd install, where `/opt/u5g-bandlock` is a **symlink to the git checkout**: whatever is checked out runs on the next timer tick (every 15 min). Work on a branch in a separate worktree and merge to `main` to deploy. Config in `/root/.config/u5g-bandlock/env` (mode 600, never in git). |
| Forgejo → GitHub | Push-mirror from `Protonord_public/u5g-bandlock` to `github.com/IBICO74/u5g-bandlock` every 8 h. Changes go issue → branch → PR → merge on Forgejo (`pn-forgejo` from the workspace VM); `main` is not branch-protected. |

## Source

Developed at [Protonord](https://git.protonord.no/Protonord_public/u5g-bandlock) —
the Forgejo repo is the source of truth; this GitHub repo is an automatic mirror.

## Notes

- Tested on U5G-Max-Outdoor (UMBBE631, fw 7.5.3) with UniFi Network 10.5 on a
  UDM-SE.
- If your modem reports `5gnr-sa` support (`get-radio-cap`), full **5G
  Standalone** is another route — it drops the LTE anchor entirely. Set
  `MODE=5gnr` to try, if your carrier deploys SA on your cell.
- Inspired by [FRooter/u5g-bandfix](https://github.com/FRooter/u5g-bandfix),
  which runs on the Cloud Gateway itself using MongoDB lookups and SSH key
  installs. This tool deliberately leaves the gateway untouched.
- Use at your own risk: it drives an undocumented CLI on the modem. Nothing is
  written to persistent storage, so a reboot always restores factory behaviour.
