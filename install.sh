#!/bin/bash
# install.sh — Gameday Scoreboard Installer
#
# Single installer for server, kiosk, or combined (all-in-one) deployments.
#
# OPTIONAL — x86_64 kiosk/combined installs:
#   For Google Chrome, place the .deb next to this script before running:
#     https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
#   If Chrome is not found, the installer falls back to Chromium automatically.
#   ARM systems (Raspberry Pi, etc.) always use Chromium via apt.
#
# Run with: sudo ./install.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── ROOT CHECK ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root:  sudo ./install.sh"
    exit 1
fi

# ─── BANNER ──────────────────────────────────────────────────────────────────
echo ""
echo "======================================================="
echo "   Gameday Scoreboard — Installer"
echo "======================================================="
echo ""

# ─── INSTALL MODE ─────────────────────────────────────────────────────────────
echo "  What are you installing on this machine?"
echo ""
echo "  [1] Server   — headless data backend (port 5000, no display)"
echo "                 Other kiosk TVs point to this machine."
echo ""
echo "  [2] Kiosk    — display client (port 5001)"
echo "                 Pairs with a remote server, or runs standalone."
echo ""
echo "  [3] Combined — server + display on one machine (port 5000)"
echo "                 Simplest single-TV all-in-one setup."
echo ""
read -rp "  Enter choice [1/2/3]: " _choice
case "$_choice" in
    1) MODE="server"   ;;
    2) MODE="kiosk"    ;;
    3) MODE="combined" ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
esac
echo ""

# ─── USERNAME ────────────────────────────────────────────────────────────────
read -rp "Enter the username to install under [default: atsi]: " APP_USER
APP_USER="${APP_USER:-atsi}"
[ -z "$APP_USER" ] && echo "ERROR: Username cannot be empty." && exit 1
APP_DIR="/home/$APP_USER/scoreboard"

# Server/combined → appserver.py on port 5000
# Kiosk-only      → appkiosk.py  on port 5001
if [[ "$MODE" == "kiosk" ]]; then
    APP_SRC="appkiosk.py"
    DISPLAY_PORT=5001
else
    APP_SRC="appserver.py"
    DISPLAY_PORT=5000
fi

echo ""
echo "  Mode        : $MODE"
echo "  User        : $APP_USER"
echo "  Install dir : $APP_DIR"
echo "  Source dir  : $SCRIPT_DIR"
echo "  App file    : $APP_SRC → app.py"
[[ "$MODE" != "server" ]] && echo "  Browser URL : http://localhost:$DISPLAY_PORT"
echo "-------------------------------------------------------"
echo ""

# ─── KIOSK SERVER URL (kiosk mode only) ──────────────────────────────────────
if [[ "$MODE" == "kiosk" ]]; then
    echo "  This kiosk will proxy to a remote scoreboard server."
    read -rp "  Remote server URL [default: http://localhost:5000]: " KIOSK_SERVER_URL
    KIOSK_SERVER_URL="${KIOSK_SERVER_URL:-http://localhost:5000}"
    echo ""
fi

# ─── DETECT ARCH & BROWSER (kiosk/combined) ───────────────────────────────────
if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    ARCH=$(uname -m)
    DISTRO_ID=$(. /etc/os-release && echo "${ID:-unknown}")
    echo "Architecture : $ARCH"
    echo "Distro       : $DISTRO_ID"
    echo ""

    if [[ "$ARCH" == "x86_64" ]]; then
        BROWSER_TYPE="chrome"
        BROWSER_BIN="google-chrome"
        CHROME_DEB="$SCRIPT_DIR/google-chrome-stable_current_amd64.deb"
    else
        BROWSER_TYPE="chromium"
        BROWSER_BIN=""
    fi
    EXTRA_BROWSER_FLAGS=""
    [[ "$BROWSER_TYPE" == "chromium" ]] && EXTRA_BROWSER_FLAGS="--no-sandbox"
fi

# ─── CREATE USER ─────────────────────────────────────────────────────────────
echo "--- User Setup ---"
if id "$APP_USER" &>/dev/null; then
    echo "User '$APP_USER' already exists — skipping creation."
else
    useradd -m -s /bin/bash "$APP_USER"
    echo "Created user '$APP_USER'. Set a password:"
    passwd "$APP_USER"
fi

# shadow: PAM auth in app.py (all modes)
# video + render: display hardware access (kiosk/combined)
EXTRA_GROUPS="shadow"
[[ "$MODE" == "kiosk" || "$MODE" == "combined" ]] && EXTRA_GROUPS="$EXTRA_GROUPS,video,render"
usermod -aG "$EXTRA_GROUPS" "$APP_USER"
echo "Groups: $EXTRA_GROUPS"
echo ""

# ─── SYSTEM PACKAGES ─────────────────────────────────────────────────────────
echo "--- Installing System Packages ---"
apt-get update -q

# Python backend — all modes
apt-get install -y \
    python3-flask \
    python3-requests \
    python3-pytz \
    python3-dateutil \
    curl \
    wget \
    iproute2 \
    network-manager \
    wireless-tools \
    wpasupplicant \
    iw

# Display environment — kiosk and combined only
if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    apt-get install -y \
        unclutter \
        xorg \
        xserver-xorg \
        x11-xserver-utils \
        lightdm \
        openbox
fi
echo ""

# ─── INSTALL BROWSER (kiosk/combined) ────────────────────────────────────────
if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    echo "--- Installing Browser ---"

    if [[ "$BROWSER_TYPE" == "chrome" ]]; then
        if command -v google-chrome &>/dev/null; then
            echo "Google Chrome is already installed — skipping download/install."
            BROWSER_BIN="google-chrome"
        elif [[ -f "$CHROME_DEB" ]]; then
            echo "Installing Google Chrome from: $CHROME_DEB"
            apt-get install -y "$CHROME_DEB" || true
            apt-get install -f -y
            BROWSER_BIN="google-chrome"
        else
            echo ""
            echo "  NOTE: Google Chrome not found and no .deb present at:"
            echo "    $CHROME_DEB"
            echo "  Falling back to Chromium..."
            echo ""
            BROWSER_TYPE="chromium"
            EXTRA_BROWSER_FLAGS="--no-sandbox"
        fi
    fi

    if [[ "$BROWSER_TYPE" == "chromium" ]]; then
        echo "Installing Chromium for $ARCH via apt..."
        if apt-cache show chromium-browser &>/dev/null 2>&1; then
            apt-get install -y chromium-browser
            BROWSER_BIN="chromium-browser"
        elif apt-cache show chromium &>/dev/null 2>&1; then
            apt-get install -y chromium
            BROWSER_BIN="chromium"
        else
            echo ""
            echo "ERROR: No chromium package found in apt for this distro."
            echo "Install chromium manually, then re-run this script."
            exit 1
        fi
    fi

    if ! command -v "$BROWSER_BIN" &>/dev/null; then
        echo ""
        echo "ERROR: Browser binary '$BROWSER_BIN' not found after installation."
        exit 1
    fi
    echo "Browser binary: $(command -v "$BROWSER_BIN")"
    echo ""
fi

# ─── HELPER FUNCTIONS ────────────────────────────────────────────────────────
copy_if_exists() {
    local src="$1" dst="$2"
    [[ ! -f "$src" ]] && return 1
    [[ "$src" -ef "$dst" ]] && echo "  Skipped: $(basename "$dst") (already in place)" && return 0
    cp "$src" "$dst" && echo "  Copied: $(basename "$dst")" && return 0
    return 1
}
find_src() {
    local rel="$1"
    [[ -f "$SCRIPT_DIR/$rel" ]]            && echo "$SCRIPT_DIR/$rel"            && return
    [[ -f "$SCRIPT_DIR/scoreboard/$rel" ]] && echo "$SCRIPT_DIR/scoreboard/$rel" && return
    echo ""
}

# ─── APPLICATION DIRECTORIES & FILES ─────────────────────────────────────────
echo "--- Setting Up Application ---"
mkdir -p "$APP_DIR/templates"
mkdir -p "$APP_DIR/static/css"
mkdir -p "$APP_DIR/static/uploads/specials"
echo "Created: $APP_DIR/templates"
echo "Created: $APP_DIR/static/css"
echo "Created: $APP_DIR/static/uploads/specials"
echo ""

echo "--- Copying Application Files ---"
SRC=$(find_src "$APP_SRC")
[[ -z "$SRC" ]] && SRC=$(find_src "app.py")
if [[ -n "$SRC" ]]; then
    copy_if_exists "$SRC" "$APP_DIR/app.py"
elif [[ -f "$APP_DIR/app.py" ]]; then
    echo "  OK: app.py (already installed)"
else
    echo "  WARNING: $APP_SRC not found — copy it to $APP_DIR/app.py manually."
fi

for tmpl in index.html login.html settings.html; do
    SRC=$(find_src "templates/$tmpl")
    [[ -z "$SRC" ]] && SRC=$(find_src "$tmpl")
    if [[ -n "$SRC" ]]; then
        copy_if_exists "$SRC" "$APP_DIR/templates/$tmpl"
    elif [[ -f "$APP_DIR/templates/$tmpl" ]]; then
        echo "  OK: $tmpl (already installed)"
    else
        echo "  WARNING: $tmpl not found — copy to $APP_DIR/templates/ manually."
    fi
done

SRC=$(find_src "static/css/main.css")
if [[ -n "$SRC" ]]; then
    copy_if_exists "$SRC" "$APP_DIR/static/css/main.css"
elif [[ -f "$APP_DIR/static/css/main.css" ]]; then
    echo "  OK: main.css (already installed)"
else
    echo "  WARNING: static/css/main.css not found — copy to $APP_DIR/static/css/ manually."
fi

# Optional helper scripts
for f in debug.py debug2.py init_display.sh; do
    SRC=$(find_src "$f")
    [[ -n "$SRC" ]] && copy_if_exists "$SRC" "$APP_DIR/$f"
done

# settings.json — preserve existing config
if [[ ! -f "$APP_DIR/settings.json" ]]; then
    SRC=$(find_src "settings.json")
    [[ -n "$SRC" ]] && copy_if_exists "$SRC" "$APP_DIR/settings.json"
else
    echo "  Skipped: settings.json (existing config preserved)"
fi

# kiosk.json — preserve existing config; create default for kiosk mode
if [[ "$MODE" == "kiosk" ]]; then
    if [[ ! -f "$APP_DIR/kiosk.json" ]]; then
        echo "{\"server_url\": \"$KIOSK_SERVER_URL\"}" > "$APP_DIR/kiosk.json"
        echo "  Created: kiosk.json (server: $KIOSK_SERVER_URL)"
    else
        echo "  Skipped: kiosk.json (existing config preserved)"
    fi
fi
echo ""

# ─── SYSTEMD: SCOREBOARD BACKEND ─────────────────────────────────────────────
echo "--- Creating Scoreboard Service ---"
cat > /etc/systemd/system/scoreboard.service <<EOF
[Unit]
Description=Gameday Scoreboard Backend
After=network-online.target
Wants=network-online.target

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3 $APP_DIR/app.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
echo "Written: /etc/systemd/system/scoreboard.service"
echo ""

# ─── KIOSK DISPLAY (kiosk/combined) ──────────────────────────────────────────
if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then

    echo "--- Configuring Auto-Login (LightDM) ---"
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-scoreboard.conf <<EOF
[Seat:*]
autologin-user=$APP_USER
autologin-user-timeout=0
user-session=openbox
EOF
    echo "Written: /etc/lightdm/lightdm.conf.d/50-scoreboard.conf"
    echo ""

    echo "--- Creating Kiosk Launch Script ---"
    # Resolve the full binary path now so it's baked into the script
    BROWSER_EXEC=$(command -v "$BROWSER_BIN")

    cat > "$APP_DIR/start_kiosk.sh" <<EOF
#!/bin/bash

# Kill any existing kiosk browser so we get a clean single instance
pkill -f "${BROWSER_BIN}.*--kiosk" 2>/dev/null || true
sleep 2

xset s off
xset -dpms
xset s noblank

pkill unclutter 2>/dev/null || true
unclutter -idle 0 &

_tries=0
until curl -sf http://localhost:$DISPLAY_PORT > /dev/null 2>&1; do
    sleep 1
    _tries=\$((_tries+1))
    [ \$_tries -ge 60 ] && break
done

# exec + full binary path keeps Chrome as the tracked PID so systemd knows
# when it exits. --user-data-dir isolates the kiosk profile so a second
# invocation never detects an "existing browser session" and exits early.
exec $BROWSER_EXEC \\
    --kiosk \\
    --no-first-run \\
    --disable-infobars \\
    --disable-session-crashed-bubble \\
    --disable-restore-session-state \\
    --noerrdialogs \\
    --disable-translate \\
    --check-for-update-interval=31536000 \\
    --confirm-to-quit \\
    --user-data-dir=/home/$APP_USER/.config/browser-kiosk \\
    $EXTRA_BROWSER_FLAGS \\
    http://localhost:$DISPLAY_PORT
EOF
    chmod +x "$APP_DIR/start_kiosk.sh"
    echo "Written: $APP_DIR/start_kiosk.sh"
    echo ""

    echo "--- Creating Kiosk Browser Service ---"
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
    echo ""

    echo "--- Configuring Openbox ---"
    mkdir -p "/home/$APP_USER/.config/openbox"
    cat > "/home/$APP_USER/.config/openbox/autostart" <<EOF
# Display environment setup only — browser is launched by kiosk.service
xset s off
xset -dpms
xset s noblank
unclutter -idle 0 &
EOF
    echo "Written: /home/$APP_USER/.config/openbox/autostart"
    echo ""

fi

# ─── SUDOERS — all modes
echo "--- Configuring Sudoers ---"
SYSTEMCTL_PATH=$(command -v systemctl)
NMCLI_PATH=$(command -v nmcli 2>/dev/null || echo /usr/bin/nmcli)
IWLIST_PATH=$(command -v iwlist 2>/dev/null || echo /usr/sbin/iwlist)
IW_PATH=$(command -v iw 2>/dev/null || echo /usr/sbin/iw)
WPA_CLI_PATH=$(command -v wpa_cli 2>/dev/null || echo /usr/sbin/wpa_cli)
IP_PATH=$(command -v ip 2>/dev/null || echo /sbin/ip)
cat > /etc/sudoers.d/scoreboard <<EOF
# Scoreboard service control
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH start kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH stop kiosk.service
$APP_USER ALL=(ALL) NOPASSWD: $SYSTEMCTL_PATH restart kiosk.service
# Wi-Fi management (nmcli)
$APP_USER ALL=(ALL) NOPASSWD: $NMCLI_PATH device wifi list *
$APP_USER ALL=(ALL) NOPASSWD: $NMCLI_PATH device wifi connect *
$APP_USER ALL=(ALL) NOPASSWD: $NMCLI_PATH device disconnect *
# Wi-Fi scan (iw / iwlist)
$APP_USER ALL=(ALL) NOPASSWD: $IWLIST_PATH * scan
$APP_USER ALL=(ALL) NOPASSWD: $IW_PATH dev * scan
$APP_USER ALL=(ALL) NOPASSWD: $IW_PATH dev * info
# wpa_cli — allow all subcommands (connect, disconnect, list_networks, etc.)
$APP_USER ALL=(ALL) NOPASSWD: $WPA_CLI_PATH
EOF
chmod 440 /etc/sudoers.d/scoreboard
visudo -c -f /etc/sudoers.d/scoreboard && echo "Written: /etc/sudoers.d/scoreboard" \
    || echo "WARNING: sudoers syntax error — check /etc/sudoers.d/scoreboard"
echo ""

# ─── FALLBACK STATIC IP ─────────────────────────────────────────────────────
echo "--- Configuring Fallback Static IP (192.168.1.250) ---"
# Detect the primary ethernet interface
ETH_IFACE=$(ip link show 2>/dev/null | grep -E '^[0-9]+: (eth|en)' | head -1 | awk '{print $2}' | tr -d ':')
if [ -z "$ETH_IFACE" ]; then
    # Fallback: first non-loopback, non-wifi interface
    ETH_IFACE=$(ip link show 2>/dev/null | grep -v 'LOOPBACK\|wlan\|wl' | grep -E '^[0-9]+: [a-z]' | head -1 | awk '{print $2}' | tr -d ':')
fi
if [ -n "$ETH_IFACE" ]; then
    cat > /etc/systemd/system/scoreboard-fallback-ip.service <<EOF
[Unit]
Description=Scoreboard fallback static IP 192.168.1.250 on $ETH_IFACE
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip addr add 192.168.1.250/24 dev $ETH_IFACE
ExecStartPost=/sbin/ip link set $ETH_IFACE up
ExecStop=/sbin/ip addr del 192.168.1.250/24 dev $ETH_IFACE

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable scoreboard-fallback-ip.service
    systemctl restart scoreboard-fallback-ip.service 2>/dev/null || true
    echo "Fallback IP 192.168.1.250 enabled on $ETH_IFACE"
else
    echo "WARNING: No ethernet interface detected — skipping fallback IP setup."
fi
echo ""

# ─── PERMISSIONS ─────────────────────────────────────────────────────────────
echo "--- Setting Permissions ---"
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chmod -R 755 "$APP_DIR"
[[ -f "$APP_DIR/settings.json" ]] && chmod 664 "$APP_DIR/settings.json"
[[ -f "$APP_DIR/kiosk.json" ]]   && chmod 664 "$APP_DIR/kiosk.json"
[[ -f "$APP_DIR/start_kiosk.sh" ]] && chmod +x "$APP_DIR/start_kiosk.sh"
[[ -f "$APP_DIR/init_display.sh" ]] && chmod +x "$APP_DIR/init_display.sh"
[[ "$MODE" == "kiosk" || "$MODE" == "combined" ]] && chown -R "$APP_USER:$APP_USER" "/home/$APP_USER/.config"
echo "Permissions set on $APP_DIR"
echo ""

# ─── ENABLE SERVICES ─────────────────────────────────────────────────────────
echo "--- Enabling Services ---"
systemctl daemon-reload
systemctl enable scoreboard.service
echo "Enabled: scoreboard.service"
if [[ -f "$APP_DIR/app.py" ]]; then
    systemctl restart scoreboard.service && echo "Started:  scoreboard.service"
else
    echo "WARNING: $APP_DIR/app.py not found — scoreboard service not started."
fi

if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    systemctl enable lightdm.service
    echo "Enabled: lightdm.service"
fi
echo ""

# ─── DONE ────────────────────────────────────────────────────────────────────
echo "======================================================="
echo "   Installation Complete!"
echo "======================================================="
echo ""
echo "  Mode     : $MODE"
echo "  App dir  : $APP_DIR"
echo "  User     : $APP_USER"
echo ""

if [[ "$MODE" == "server" ]]; then
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "  Backend URL : http://${SERVER_IP:-<this-machine-ip>}:5000"
    echo "  Point your kiosk(s) to this address in their settings."
    echo ""
    WARN=0
    for f in "$APP_DIR/app.py" \
              "$APP_DIR/templates/index.html" \
              "$APP_DIR/templates/login.html" \
              "$APP_DIR/templates/settings.html" \
              "$APP_DIR/static/css/main.css"; do
        [[ ! -f "$f" ]] && echo "  WARNING: Missing — $f" && WARN=1
    done
    [[ $WARN -eq 1 ]] && echo ""
fi

if [[ "$MODE" == "kiosk" ]]; then
    echo "  Browser       : $BROWSER_BIN"
    echo "  Display       : http://localhost:$DISPLAY_PORT"
    echo "  Remote server : $KIOSK_SERVER_URL"
    echo "  (Edit $APP_DIR/kiosk.json or use Settings to change the server URL)"
    echo ""
    WARN=0
    for f in "$APP_DIR/app.py" \
              "$APP_DIR/templates/index.html" \
              "$APP_DIR/templates/login.html" \
              "$APP_DIR/templates/settings.html" \
              "$APP_DIR/static/css/main.css" \
              "$APP_DIR/kiosk.json"; do
        [[ ! -f "$f" ]] && echo "  WARNING: Missing — $f" && WARN=1
    done
    [[ $WARN -eq 1 ]] && echo ""
    echo "  The system will reboot in 10 seconds and boot directly"
    echo "  into the scoreboard kiosk via HDMI."
    echo "  Press Ctrl+C to cancel the reboot."
fi

if [[ "$MODE" == "combined" ]]; then
    echo "  Browser : $BROWSER_BIN"
    echo "  Display : http://localhost:$DISPLAY_PORT"
    echo ""
    WARN=0
    for f in "$APP_DIR/app.py" \
              "$APP_DIR/templates/index.html" \
              "$APP_DIR/templates/login.html" \
              "$APP_DIR/templates/settings.html" \
              "$APP_DIR/static/css/main.css"; do
        [[ ! -f "$f" ]] && echo "  WARNING: Missing — $f" && WARN=1
    done
    [[ $WARN -eq 1 ]] && echo ""
    echo "  The system will reboot in 10 seconds and boot directly"
    echo "  into the scoreboard kiosk via HDMI."
    echo "  Press Ctrl+C to cancel the reboot."
fi

echo "======================================================="

if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    sleep 10
    reboot
fi
