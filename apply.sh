#!/bin/bash
# u5g-bandlock — persistent LTE/5G band preference for UniFi U5G modems
# (U5G, U5G-Max, U5G-Max-Outdoor). The modem stores band prefs in tmpfs and
# forgets them on every reboot; run this from a systemd timer (or cron) on any
# Linux box on the LAN to re-apply them whenever they drift.
#
# Config: environment variables (see env.example). Read from
# /root/.config/u5g-bandlock/env if that file exists (systemd install), or
# passed in directly (Docker). Set U5G_BANDLOCK_ENV to use another path.
set -euo pipefail
ENV_FILE="${U5G_BANDLOCK_ENV:-/root/.config/u5g-bandlock/env}"
# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${MODEM_IP:?}" "${ICCID:?}" "${LTE_BAND:?}"
MODE="${MODE:-5gnr,lte}"
NR5G_SA_BAND="${NR5G_SA_BAND:-}"
MODEM_USER="${MODEM_USER:-}"

# Device SSH password: either static in env, or fetched live from the UniFi
# Network API (Settings → System → Device SSH Authentication).
if [ -z "${MODEM_SSH_PASSWORD:-}" ]; then
  : "${UNIFI_HOST:?}" "${UNIFI_API_KEY:?}"
  MGMT=$(curl -sk -m 10 -H "X-API-KEY: $UNIFI_API_KEY" \
    "https://${UNIFI_HOST}/proxy/network/api/s/default/get/setting" \
    | jq -r '.data[] | select(.key=="mgmt")')
  MODEM_SSH_PASSWORD=$(jq -r '.x_ssh_password' <<<"$MGMT")
  [ -n "$MODEM_USER" ] || MODEM_USER=$(jq -r '.x_ssh_username' <<<"$MGMT")
fi

mctl() { printf '%s' "$1" | sshpass -p "$MODEM_SSH_PASSWORD" ssh \
  -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
  "${MODEM_USER}@${MODEM_IP}" uiwwand-ctl 2>/dev/null; }

CUR=$(mctl "{\"method\":\"get-radio-pref\",\"params\":{\"iccid\":\"$ICCID\"}}" \
  | jq -r '.result.lte_band // "unset"')

if [ "$CUR" = "$LTE_BAND" ]; then
  echo "ok: lte_band=$CUR"
  exit 0
fi

echo "drift: lte_band was «$CUR» — re-applying $LTE_BAND"
PARAMS="{\"iccid\":\"$ICCID\",\"mode\":\"$MODE\",\"lte_band\":\"$LTE_BAND\""
[ -n "$NR5G_SA_BAND" ] && PARAMS="$PARAMS,\"nr5g_sa_band\":\"$NR5G_SA_BAND\""
mctl "{\"method\":\"set-radio-pref\",\"params\":$PARAMS}}"
# Note: the modem only honors the new list at its next (re-)registration.
# Reboot it once from the UniFi console to force an immediate re-attach.
