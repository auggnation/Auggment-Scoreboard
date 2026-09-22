#!/bin/bash
# Run once with:  sudo bash setup_kiosk_service.sh
# Installs the kiosk browser systemd service plus the sudoers entries the app
# needs to control it (and Wi-Fi scanning) from the Settings page.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-$SCRIPT_DIR}"

# Resolve the app user: the (non-root) user who invoked sudo, else the owner of
# the app directory, else the current user.
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    APP_USER="$SUDO_USER"
else
    APP_USER="$(stat -c '%U' "$APP_DIR" 2>/dev/null || true)"
fi
APP_USER="${APP_USER:-$USER}"
SYSTEMCTL_PATH=$(command -v systemctl)
IP_PATH=$(command -v ip || true)
IP_PATH="${IP_PATH:-/usr/sbin/ip}"

echo "--- Kiosk Service Installer ---"
echo "  App dir : $APP_DIR"
echo "  App user: $APP_USER"
echo ""

echo "--- Writing kiosk.service ---"
cat > /etc/systemd/system/kiosk.service <<EOF
[Unit]
Description=Scoreboard Kiosk Browser
After=graphical.target scoreboard.service
Wants=scoreboard.service

[Service]
User=$APP_USER
Environment=DISPLAY=:0
ExecStart=$APP_DIR/start_kiosk.sh
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF
echo "Written: /etc/systemd/system/kiosk.service"

echo "--- Writing sudoers entry ---"
cat > /etc/sudoers.d/scoreboard <<EOF
# Scoreboard service control
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH start kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH stop kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH restart kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: /bin/systemctl start kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: /bin/systemctl stop kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart kiosk.service
# Wi-Fi management (incl. bringing interfaces up for scanning)
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/nmcli
$APP_USER ALL=(ALL) NOPASSWD: /bin/nmcli
$APP_USER ALL=(ALL) NOPASSWD: /usr/sbin/iwlist
$APP_USER ALL=(ALL) NOPASSWD: /bin/iwlist
$APP_USER ALL=(ALL) NOPASSWD: /usr/sbin/iw
$APP_USER ALL=(ALL) NOPASSWD: /bin/iw
$APP_USER ALL=(ALL) NOPASSWD: /usr/sbin/wpa_cli
$APP_USER ALL=(ALL) NOPASSWD: /bin/wpa_cli
$APP_USER ALL=(ALL) NOPASSWD: $IP_PATH link set *
EOF
chmod 440 /etc/sudoers.d/scoreboard
visudo -c -f /etc/sudoers.d/scoreboard && echo "Written: /etc/sudoers.d/scoreboard"

echo "--- Reloading systemd ---"
systemctl daemon-reload
systemctl enable kiosk.service
echo "Enabled: kiosk.service"

echo ""
echo "Done. kiosk.service is now installed."
echo "It will start automatically with a graphical session."
echo "Use the Settings page or 'sudo systemctl start kiosk.service' to launch it manually."
echo ""
echo "NOTE: Install a browser first:"
echo "  x86_64: place google-chrome-stable_current_amd64.deb next to install.sh, then:"
echo "    sudo apt install ./google-chrome-stable_current_amd64.deb"
echo "  ARM:    sudo apt install chromium"