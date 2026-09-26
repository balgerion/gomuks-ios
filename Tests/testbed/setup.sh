#!/usr/bin/env bash
set -euo pipefail

TB="$(cd "$(dirname "$0")" && pwd)"
SRC="${GOMUKS_SRC:?set GOMUKS_SRC to a gomuks checkout}"
STATE="${TESTBED_STATE:-$TB/state}"
VENV="$STATE/venv"
HS_DIR="$STATE/synapse"
GM_ROOT="$STATE/gomuks"
LOGS="$STATE/logs"
HS_URL="http://127.0.0.1:8008"
GM_URL="http://localhost:29325"
FIX_DIR="$STATE/fixture"
FIX_URL="http://localhost:8765"
PLAYER_URL="http://127.0.0.1:5055"
export GOTOOLCHAIN=auto

log() { printf '[testbed %s] %s\n' "$(date +%T)" "$*"; }

wait_http() {
	for _ in $(seq 1 300); do
		if curl -s -o /dev/null --max-time 2 "$1"; then return 0; fi
		sleep 0.2
	done
	log "$2 did not come up at $1"
	return 1
}

mkdir -p "$STATE" "$LOGS"

if [ ! -x "$VENV/bin/python" ]; then
	python3 -m venv "$VENV"
fi
if ! "$VENV/bin/python" -c "import synapse, lxml" 2>/dev/null; then
	log "installing matrix-synapse"
	"$VENV/bin/pip" install -q "matrix-synapse[url-preview]"
fi

if [ ! -x "$SRC/gomuks" ]; then
	log "building gomuks"
	(cd "$SRC" && go generate ./web && GO_BUILD_TAGS=goolm ./build-noweb.sh) > "$LOGS/build.log" 2>&1
fi

if [ ! -f "$HS_DIR/homeserver.yaml" ]; then
	mkdir -p "$HS_DIR"
	"$VENV/bin/python" -m synapse.app.homeserver --server-name localhost \
		--config-path "$HS_DIR/homeserver.yaml" --generate-config --report-stats=no \
		--data-directory "$HS_DIR" > /dev/null
	"$VENV/bin/python" - "$HS_DIR" "$LOGS" <<'PY'
import re, sys, yaml
hs_dir, logs = sys.argv[1], sys.argv[2]
log_config = f"{hs_dir}/localhost.log.config"
text = open(log_config).read()
open(log_config, "w").write(re.sub(r"(\n\s*filename:).*", rf"\1 {logs}/homeserver.log", text))
path = f"{hs_dir}/homeserver.yaml"
c = yaml.safe_load(open(path))
c["listeners"] = [{"port": 8008, "bind_addresses": ["127.0.0.1"], "type": "http", "tls": False,
                   "x_forwarded": False, "resources": [{"names": ["client"], "compress": False}]}]
c["trusted_key_servers"] = []
c["suppress_key_server_warning"] = True
c["enable_registration"] = False
c["presence"] = {"enabled": False}
c["url_preview_enabled"] = True
c["url_preview_ip_range_blacklist"] = ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
                                       "100.64.0.0/10", "169.254.0.0/16", "::1/128", "fe80::/10", "fc00::/7"]
c["url_preview_ip_range_whitelist"] = ["127.0.0.0/8"]
c["media_store_path"] = f"{hs_dir}/media_store"
big = {"per_second": 10000, "burst_count": 100000}
for k in ("rc_message", "rc_registration", "rc_3pid_validation", "rc_admin_redaction", "rc_key_requests",
          "rc_room_creation", "rc_delayed_event_mgmt", "rc_reports", "rc_media_create"):
    c[k] = big
c["rc_login"] = {"address": big, "account": big, "failed_attempts": big}
c["rc_joins"] = {"local": big, "remote": big}
c["rc_invites"] = {"per_room": big, "per_user": big, "per_sender": big}
yaml.safe_dump(c, open(path, "w"), sort_keys=False)
PY
fi

if ! curl -s -o /dev/null --max-time 2 "$HS_URL/_matrix/client/versions"; then
	log "starting synapse"
	nohup "$VENV/bin/python" -m synapse.app.homeserver --config-path "$HS_DIR/homeserver.yaml" \
		> "$LOGS/synapse.stdout" 2>&1 < /dev/null &
	wait_http "$HS_URL/_matrix/client/versions" synapse
fi

for user in tester:testpass friend:friendpass; do
	out=$("$VENV/bin/register_new_matrix_user" -c "$HS_DIR/homeserver.yaml" -u "${user%%:*}" -p "${user#*:}" \
		--no-admin "$HS_URL" 2>&1) || echo "$out" | grep -q "User ID already taken" || { echo "$out"; exit 1; }
done

ffmpeg_bin() {
	if command -v ffmpeg > /dev/null 2>&1; then
		command -v ffmpeg
		return 0
	fi
	if ! "$1/bin/python" -c "import pyffmpeg" 2>/dev/null; then
		log "installing pyffmpeg" >&2
		"$1/bin/pip" install -q pyffmpeg >&2
	fi
	"$1/bin/python" -c "import pyffmpeg; print(pyffmpeg.FFmpeg().get_ffmpeg_bin())" | tail -n 1
}

if [ ! -f "$FIX_DIR/video.html" ]; then
	log "generating video fixture"
	mkdir -p "$FIX_DIR"
	"$VENV/bin/python" "$TB/fixture.py" "$FIX_DIR" "$(ffmpeg_bin "$VENV")" "$FIX_URL"
fi

if ! curl -s -o /dev/null --max-time 2 "$FIX_URL/video.html"; then
	log "starting fixture server"
	nohup "$VENV/bin/python" -m http.server 8765 --bind 127.0.0.1 --directory "$FIX_DIR" \
		> "$LOGS/fixture.log" 2>&1 < /dev/null &
	wait_http "$FIX_URL/video.html" fixture
fi

if [ -n "${PLAYER_SRC:-}" ]; then
	PVENV="$STATE/player-venv"
	PAPP="$STATE/player-app"
	if [ ! -x "$PVENV/bin/python" ]; then
		python3 -m venv "$PVENV"
	fi
	if ! "$PVENV/bin/python" -c "import flask, yt_dlp, uvicorn, starlette, dotenv, psutil, pyffmpeg" 2>/dev/null; then
		log "installing player requirements"
		"$PVENV/bin/pip" install -q -r "$PLAYER_SRC/src/requirements.txt" pyffmpeg
	fi
	if ! curl -s -o /dev/null --max-time 2 "$PLAYER_URL/"; then
		log "starting player"
		rm -rf "$PAPP"
		cp -R "$PLAYER_SRC/src" "$PAPP"
		git -C "$PLAYER_SRC" rev-parse --short HEAD > "$PAPP/version.txt" 2>/dev/null || echo testbed > "$PAPP/version.txt"
		mkdir -p "$STATE/player-data"
		(cd "$PAPP" && PORT=5055 DATA_PATH="$STATE/player-data" PYTHONUNBUFFERED=1 \
			nohup "$PVENV/bin/python" main.py > "$LOGS/player.log" 2>&1 < /dev/null &)
		wait_http "$PLAYER_URL/" player
	fi
fi

"$VENV/bin/python" "$TB/seed.py"

mkdir -p "$GM_ROOT/config"
if [ ! -f "$GM_ROOT/config/config.yaml" ]; then
	hash=$("$VENV/bin/python" -c "import bcrypt; print(bcrypt.hashpw(b'adminpass', bcrypt.gensalt(12)).decode())")
	cat > "$GM_ROOT/config/config.yaml" <<YAML
web:
  listen_address: localhost:29325
  username: admin
  password_hash: '$hash'
  insecure_cookies: true
YAML
fi

if ! curl -s -o /dev/null --max-time 2 "$GM_URL/"; then
	log "starting gomuks"
	GOMUKS_ROOT="$GM_ROOT" nohup "$SRC/gomuks" > "$LOGS/gomuks.stdout" 2>&1 < /dev/null &
	wait_http "$GM_URL/" gomuks
fi

jar="$STATE/cookies.txt"
curl -s -f -o /dev/null -c "$jar" -u admin:adminpass -X POST "$GM_URL/_gomuks/auth"
gexec() { curl -s -b "$jar" -X POST -H 'Content-Type: application/json' --data "$2" "$GM_URL/_gomuks/exec/$1"; }

if [ ! -f "$STATE/gomuks-verified" ]; then
	log "logging gomuks in"
	resp=$(gexec login '{"homeserver_url":"http://127.0.0.1:8008","username":"tester","password":"testpass"}')
	if echo "$resp" | grep -q '"errcode"' && ! echo "$resp" | grep -q "already logged in"; then
		echo "login failed: $resp"
		exit 1
	fi
	for _ in $(seq 1 100); do
		grep -qE "Saving account to database|Device verification state" "$GM_ROOT/logs/gomuks.log" 2>/dev/null && break
		sleep 0.2
	done
	key=$(gexec generate_recovery_key '{}')
	echo "$key" | grep -q recovery_key || { echo "generate_recovery_key failed: $key"; exit 1; }
	body=$("$VENV/bin/python" -c 'import json,sys; d=json.loads(sys.argv[1]); d["account_password"]="testpass"; print(json.dumps(d))' "$key")
	resp=$(gexec reset_encryption "$body")
	if echo "$resp" | grep -q '"errcode"'; then
		echo "reset_encryption failed: $resp"
		exit 1
	fi
	touch "$STATE/gomuks-verified"
fi

log "ready: gomuks $GM_URL (admin/adminpass)"
