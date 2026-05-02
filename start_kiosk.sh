#!/bin/bash

# Kill any existing kiosk Chrome so we get a clean single instance
pkill -f "chrome.*--kiosk" 2>/dev/null || true
sleep 2

xset s off
xset -dpms
xset s noblank

pkill unclutter 2>/dev/null || true
unclutter -idle 0 &

_tries=0
until curl -sf http://localhost:5000 > /dev/null 2>&1; do
    sleep 1
    _tries=$((_tries+1))
    [ $_tries -ge 60 ] && break
done

# Use exec + raw binary so systemd tracks the Chrome PID directly.
# --user-data-dir isolates the kiosk profile so Chrome never detects an
# "existing browser session" and exits prematurely.
exec /opt/google/chrome/chrome \
    --kiosk \
    --no-first-run \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --noerrdialogs \
    --disable-translate \
    --check-for-update-interval=31536000 \
    --confirm-to-quit \
    --user-data-dir=/home/auggie/.config/chrome-kiosk \
    http://localhost:5000
