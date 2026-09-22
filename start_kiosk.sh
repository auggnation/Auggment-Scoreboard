#!/bin/bash
# Kiosk launcher. install.sh regenerates this with the exact browser/port baked
# in; this self-configuring copy is a safe fallback for manual installs.

# Pick the best available browser binary
if command -v chromium >/dev/null 2>&1; then
    BROWSER=$(command -v chromium)
elif command -v chromium-browser >/dev/null 2>&1; then
    BROWSER=$(command -v chromium-browser)
elif [ -x /opt/google/chrome/chrome ]; then
    BROWSER=/opt/google/chrome/chrome
elif command -v google-chrome-stable >/dev/null 2>&1; then
    BROWSER=$(command -v google-chrome-stable)
fi
if [ -z "$BROWSER" ] || [ ! -x "$BROWSER" ]; then
    echo "No Chromium/Chrome browser found. Install one first." >&2
    exit 1
fi

# Port: settings.json (when present) is authoritative — it is what app.py
# actually binds. Fallback: kiosk.json present => kiosk mode (5001), else 5000.
_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=5000
[ -f "$_APP_DIR/kiosk.json" ] && PORT=5001
if command -v python3 >/dev/null 2>&1 && [ -f "$_APP_DIR/settings.json" ]; then
    SPORT=$(python3 - "$_APP_DIR/settings.json" <<'PYEOF' 2>/dev/null
import json, sys
try: print(json.load(open(sys.argv[1])).get('port', ''))
except Exception: pass
PYEOF
)
    case "$SPORT" in
        ''|*[!0-9]*) ;;
        *) [ "$SPORT" -gt 0 ] 2>/dev/null && PORT="$SPORT" ;;
    esac
fi
echo "Kiosk will open http://localhost:${PORT}"

# Chrome's --kiosk can fail to go fullscreen on WM-less X11 (Chrome >= 152),
# leaving a default-sized window. Force the exact active-resolution geometry.
CHROME_GEOMETRY=""
if command -v xrandr >/dev/null 2>&1; then
    GEO=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')
    if [ -n "$GEO" ]; then
        W=${GEO%x*}
        H=${GEO#*x}
        case "$W:$H" in
            *[!0-9]*:*[!0-9]*) ;;
            *) [ "$W" -gt 0 ] 2>/dev/null && [ "$H" -gt 0 ] 2>/dev/null \
                && CHROME_GEOMETRY="--window-size=${W},${H} --window-position=0,0" ;;
        esac
    fi
fi

# Kill any existing kiosk browser so we get a clean single instance
pkill -f "chrom.*--kiosk" 2>/dev/null || true
sleep 2

xset s off
xset -dpms
xset s noblank

pkill unclutter 2>/dev/null || true
unclutter -idle 0 &

_tries=0
until curl -sf "http://localhost:${PORT}" > /dev/null 2>&1; do
    sleep 1
    _tries=$((_tries+1))
    [ $_tries -ge 60 ] && break
done

# exec the raw binary so systemd tracks the browser PID directly.
# --user-data-dir isolates the kiosk profile so Chrome never detects an
# "existing browser session" and exits prematurely.
exec "$BROWSER" \
    --kiosk \
    --start-fullscreen \
    --no-first-run \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --noerrdialogs \
    --disable-translate \
    --check-for-update-interval=31536000 \
    --confirm-to-quit \
    $CHROME_GEOMETRY \
    --user-data-dir="$HOME/.config/browser-kiosk" \
    "http://localhost:${PORT}"