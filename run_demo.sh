#!/usr/bin/env bash
# QueueCue: one command to start everything on the host laptop.
#   ./run_demo.sh            start (keeps current data)
#   ./run_demo.sh --reset    start from a fresh seed
#   ./run_demo.sh --live     start with the live local model on (needs Ollama + model)
#   ./run_demo.sh --lan      skip the Cloudflare tunnel (LAN-only fallback)
set -uo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
PORT="${QQ_PORT:-8080}"
LOG="$ROOT/server/data/logs"
mkdir -p "$LOG"
MODEL="$(sed -n 's/.*"model": *"\([^"]*\)".*/\1/p' server/config.json | head -1)"
ORG_KEY="$(sed -n 's/.*"organizer_key": *"\([^"]*\)".*/\1/p' server/config.json | head -1)"
SERVER_ARGS=()
USE_TUNNEL=1
for a in "$@"; do
  case "$a" in
    --reset) SERVER_ARGS+=(--reset) ;;
    --live) SERVER_ARGS+=(--live) ;;
    --cached) SERVER_ARGS+=(--cached) ;;
    --lan) USE_TUNNEL=0 ;;
  esac
done

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok() { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
PIDS=()
cleanup() {
  echo; bold "Stopping QueueCue..."
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  exit 0
}
trap cleanup INT TERM

bold "1/5 Tools"
command -v dart >/dev/null || { echo "Dart/Flutter not found. See README: Setup."; exit 1; }
ok "Dart $(dart --version 2>&1 | awk '{print $4}')"

bold "2/5 Local AI (Ollama, model: $MODEL)"
if curl -s -m 2 "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
  ok "Ollama is running"
elif command -v ollama >/dev/null; then
  (ollama serve >"$LOG/ollama.log" 2>&1 &) ; sleep 3
  curl -s -m 2 "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1 && ok "Started Ollama" || warn "Ollama did not start; Demo Mode cache still works"
else
  warn "Ollama not installed. Demo Mode uses the precomputed cache. (README: Setup step 3)"
fi
if curl -s -m 2 "http://127.0.0.1:11434/api/tags" 2>/dev/null | grep -q "\"$MODEL"; then
  ok "$MODEL is pulled"
elif command -v ollama >/dev/null; then
  warn "$MODEL not pulled yet. Run: ollama pull $MODEL   (Demo Mode cache works meanwhile)"
fi
if command -v whisper-cli >/dev/null && [ -f tools/whisper/ggml-small.en.bin ]; then ok "whisper.cpp ready"; else warn "whisper.cpp not set up: voice recordings fall back to typing (demo voice notes use the cache)"; fi

bold "3/5 Web app"
if [ ! -f app/build/web/index.html ] || [ -n "$(find app/lib app/web -newer app/build/web/index.html -type f 2>/dev/null | head -1)" ]; then
  (cd app && flutter build web --release --no-web-resources-cdn --no-wasm-dry-run) || { echo "Web build failed"; exit 1; }
fi
ok "Built: app/build/web"

bold "4/5 Server on :$PORT"
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  warn "Port $PORT busy; stopping the old process"
  kill $(lsof -ti tcp:"$PORT") 2>/dev/null; sleep 1
fi
(cd server && dart pub get >/dev/null 2>&1; exec dart run bin/server.dart "${SERVER_ARGS[@]+"${SERVER_ARGS[@]}"}") >"$LOG/server.log" 2>&1 &
PIDS+=($!)
for i in $(seq 1 90); do curl -s -m 1 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break; sleep 1; done
curl -s -m 2 "http://127.0.0.1:$PORT/api/health" >/dev/null || { echo "Server did not start. See $LOG/server.log"; tail -20 "$LOG/server.log"; cleanup; }
ok "Server up (log: server/data/logs/server.log)"

bold "5/5 HTTPS link for phones"
URL=""
if [ "$USE_TUNNEL" = 1 ] && command -v cloudflared >/dev/null; then
  cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" >"$LOG/tunnel.log" 2>&1 &
  PIDS+=($!)
  for i in $(seq 1 40); do
    URL="$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG/tunnel.log" | grep -v '//api\.' | head -1)"
    [ -n "$URL" ] && break; sleep 1
  done
  [ -n "$URL" ] && ok "Cloudflare quick tunnel: $URL" || warn "Tunnel did not come up (see $LOG/tunnel.log). Falling back to LAN."
elif [ "$USE_TUNNEL" = 1 ]; then
  warn "cloudflared not installed (README: Setup step 5). Falling back to LAN."
fi
if [ -z "$URL" ]; then
  IP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
  URL="http://${IP:-localhost}:$PORT"
  warn "LAN link: $URL  (same Wi-Fi only; iPhone camera + mic need HTTPS, so use Demo Mode taps and typed answers)"
fi

echo
bold "Scan with the iPhone camera:"
(cd server && dart run bin/qr.dart "$URL")
echo
bold "QueueCue is running."
echo "  Students:    $URL"
echo "  Phone A:     $URL/?student=demo-viktor        (add &frame=iphone on a laptop for a phone frame)"
echo "  Phone B:     $URL/?student=demo-hermione"
echo "  Recruiter:   $URL/?recruiter=bk-northwind     (recruiter app; sign in at $URL/recruiter)"
echo "  Big screen:  $URL/booth/northwind?key=bk-northwind"
echo "  Organizer:   $URL/organizer?org=$ORG_KEY"
echo "  All screens: $URL/links                  (jump to any feature; add ?splash=off to skip the intro)"
echo "  Local:       http://localhost:$PORT"
echo
echo "Press Ctrl-C to stop."
wait
