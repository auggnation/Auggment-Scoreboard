#!/bin/bash
# Run once with: sudo bash /home/auggie/scoreboard/setup_kiosk_service.sh
set -e

APP_USER="auggie"
APP_DIR="/home/$APP_USER/scoreboard"
SYSTEMCTL_PATH=$(command -v systemctl)

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
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH start kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH stop kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH restart kiosk.service
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
