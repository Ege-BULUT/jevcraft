#!/bin/bash
# Keeps JevCraft running on this Mac: the game (with the jev_agent mod), the window recorder and
# the uploader. Each one is restarted if it exits; the Mac is kept awake while this runs.
#
#   HF_REPO=<user>/jevcraft agent/supervise.sh
#
# Secrets live in the macOS keychain, never in files in the repo:
#   security add-generic-password -a jevcraft -s hf-token -w        # Hugging Face write token
#   security add-generic-password -a jevcraft -s jevcraft-key -w    # key for /api/decide
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN="$ROOT/run"
WORLD="$HOME/Library/Application Support/minetest/worlds/jevcraft"
HF_REPO=${HF_REPO:?set HF_REPO=<hf user>/jevcraft}
DECIDE_URL=${DECIDE_URL:-https://jevcraft.vercel.app/api/decide}
mkdir -p "$RUN/segments"

secret() { security find-generic-password -a jevcraft -s "$1" -w; }

# Luanti rewrites the config it loads, so start each game from a fresh copy plus the secrets.
write_config() {
  cp "$ROOT/config/client.conf" "$RUN/client.conf"
  printf 'jev_agent.decide_url = %s\njev_agent.key = %s\n' "$DECIDE_URL" "$(secret jevcraft-key)" >> "$RUN/client.conf"
  chmod 600 "$RUN/client.conf"
}

log() { echo "[supervise $(date '+%F %T')] $*"; }

cleanup() { log "stopping"; kill $(jobs -p) 2>/dev/null; pkill -f "luanti --config $RUN/client.conf"; exit 0; }
trap cleanup INT TERM

caffeinate -dimsu -w $$ &   # no idle or system sleep while this script lives; closing the lid still sleeps

while true; do
  if ! pgrep -f "luanti --config $RUN/client.conf" >/dev/null; then
    log "starting the game"
    write_config
    # -g: never bring the game to the foreground; it lives on its own Space (Dock > Options > Assign To).
    open -g -n -a /Applications/luanti.app --args --config "$RUN/client.conf" --logfile "$RUN/luanti.log" \
      --go --world "$WORLD" --name Jev --password ""
  fi
  if ! pgrep -f "jevcraft-recorder $RUN/segments" >/dev/null; then
    log "starting the recorder"
    "$ROOT/recorder/jevcraft-recorder" "$RUN/segments" "$WORLD/jev_recording" >> "$RUN/recorder.log" 2>&1 &
  fi
  if ! pgrep -f "uploader.py $RUN/segments" >/dev/null; then
    log "starting the uploader"
    uv run --script "$ROOT/agent/uploader.py" "$RUN/segments" "$HF_REPO" >> "$RUN/uploader.log" 2>&1 &
  fi
  sleep 15
done
