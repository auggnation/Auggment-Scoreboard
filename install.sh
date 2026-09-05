#!/bin/bash
# install.sh — Gameday Scoreboard Installer
#
# Single installer for server, kiosk, or combined (all-in-one) deployments.
# Creates every folder and file the app needs, installs a browser (preferring
# Google Chrome on x86_64, else a distro-appropriate Chromium), and disables
# whatever desktop manager is currently running so the kiosk boots straight
# into the scoreboard.
#
# OPTIONAL — x86_64 kiosk/combined installs:
#   For Google Chrome, place the .deb next to this script before running:
#     https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
#   If Chrome is not found, the installer falls back to a distro-appropriate
#   Chromium automatically (Debian/Ubuntu/Raspbian use apt; indices that no
#   longer ship Chromium fall back to Google's Chromium .deb on x86_64).
#   ARM systems (Raspberry Pi, etc.) always use Chromium via the distro.
#
# Run with: sudo ./install.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

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
read -rp "Enter the username to install under [default: root]: " APP_USER
APP_USER="${APP_USER:-root}"
[ -z "$APP_USER" ] && echo "ERROR: Username cannot be empty." && exit 1
APP_DIR="/home/$APP_USER/scoreboard"

# The app is delivered as a single app.py that detects server vs kiosk from
# settings.json / kiosk.json at runtime, so there is one source file regardless
# of mode. Ports differ only by displayed URL.
if [[ "$MODE" == "kiosk" ]]; then
    APP_SRC="app.py"
    DISPLAY_PORT=5001
else
    APP_SRC="app.py"
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

# ─── DETECT DISTRO (all modes) ────────────────────────────────────────────────
# Needed for the system-packages section regardless of mode.
ARCH=$(uname -m)
if [ -r /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_FAMILY=""
    case "$DISTRO_ID" in
        debian|ubuntu|raspbian|linuxmint|elementary|pop) DISTRO_FAMILY="debian" ;;
        fedora|centos|rhel|rocky|almalinux)              DISTRO_FAMILY="fedora" ;;
        arch|manjaro|endeavouros)                        DISTRO_FAMILY="arch"   ;;
        opensuse*|suse)                                  DISTRO_FAMILY="suse"   ;;
        *)                                               DISTRO_FAMILY="debian" ;;
    esac
else
    DISTRO_ID="unknown"
    DISTRO_FAMILY="debian"
fi
echo "Architecture : $ARCH"
echo "Distro       : $DISTRO_ID (family: $DISTRO_FAMILY)"
echo ""

# ─── DETECT BROWSER (kiosk/combined only) ─────────────────────────────────────
if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    BROWSER_TYPE=""
    BROWSER_BIN=""
    # x86_64 → prefer Google Chrome (real browser, no sandbox flags needed).
    # Otherwise use the distro Chromium.
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
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

# video + render: display hardware access (kiosk/combined)
EXTRA_GROUPS=""
[[ "$MODE" == "kiosk" || "$MODE" == "combined" ]] && EXTRA_GROUPS="$EXTRA_GROUPS,video,render"
EXTRA_GROUPS="${EXTRA_GROUPS#,}"
if [ -n "$EXTRA_GROUPS" ]; then
    usermod -aG "$EXTRA_GROUPS" "$APP_USER"
    echo "Groups: $EXTRA_GROUPS"
else
    echo "No extra groups needed."
fi
echo ""

# ─── SYSTEM PACKAGES ─────────────────────────────────────────────────────────
echo "--- Installing System Packages ---"

case "$DISTRO_FAMILY" in
    debian)
        apt-get update -q
        # Python backend — all modes
        apt-get install -y \
            python3 \
            python3-flask \
            python3-requests \
            python3-pytz \
            python3-dateutil \
            python3-pip \
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
        ;;
    fedora)
        dnf install -y \
            python3 python3-flask python3-requests python3-pytz \
            python3-dateutil python3-pip curl wget iproute \
            NetworkManager wireless-tools wpa_supplicant iw 2>/dev/null \
            || yum install -y python3 python3-flask python3-requests \
               python3-pytz python3-dateutil python3-pip curl wget iproute \
               NetworkManager wireless-tools wpa_supplicant iw
        if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
            dnf install -y unclutter xorg-x11-server-Xorg \
                xorg-x11-server-utils lightdm openbox 2>/dev/null \
                || yum install -y unclutter xorg-x11-server-Xorg \
                   xorg-x11-server-utils lightdm openbox
        fi
        ;;
    arch)
        pacman -Sy --noconfirm \
            python python-flask python-requests python-pytz \
            python-dateutil python-pip curl wget iproute2 \
            networkmanager wireless_tools wpa_supplicant iw
        if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
            pacman -S --noconfirm unclutter xorg-server xorg-xinit \
                lightdm openbox
        fi
        ;;
    suse)
        zypper --non-interactive install \
            python3 python3-Flask python3-requests python3-pytz \
            python3-dateutil python3-pip curl wget iproute2 \
            NetworkManager wireless-tools wpa_supplicant iw
        if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
            zypper --non-interactive install unclutter xorg-x11-server \
                xorg-x11-utils lightdm openbox
        fi
        ;;
    *) echo "WARNING: Unknown distro family '$DISTRO_ID' — using Debian path." ;;
esac
echo ""

# ─── PYTHON DEPENDENCIES (fallback so a fresh OS still gets every module) ────
echo "--- Ensuring Python Dependencies ---"
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    if have_cmd pip3; then
        pip3 install --break-system-packages -q -r "$SCRIPT_DIR/requirements.txt" \
            || pip3 install -q -r "$SCRIPT_DIR/requirements.txt" || true
    fi
fi
echo ""

# ─── INSTALL BROWSER (kiosk/combined) ────────────────────────────────────────
if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    echo "--- Installing Browser ---"

    if [[ "$BROWSER_TYPE" == "chrome" ]]; then
        if have_cmd google-chrome; then
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
            echo "  Falling back to a distro-appropriate Chromium..."
            echo ""
            BROWSER_TYPE="chromium"
            EXTRA_BROWSER_FLAGS="--no-sandbox"
        fi
    fi

    if [[ "$BROWSER_TYPE" == "chromium" ]]; then
        case "$DISTRO_FAMILY" in
            debian)
                # Older distros ship chromium-browser; newer ones ship chromium.
                if apt-cache show chromium-browser >/dev/null 2>&1; then
                    echo "Installing chromium-browser via apt..."
                    apt-get install -y chromium-browser
                    BROWSER_BIN="chromium-browser"
                elif apt-cache show chromium >/dev/null 2>&1; then
                    echo "Installing chromium via apt..."
                    apt-get install -y chromium
                    BROWSER_BIN="chromium"
                elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
                    # Debian 12+/no chromium package: fall back to Google Chromium's
                    # .deb (a real browser that works in --kiosk without sandbox hacks).
                    echo "No apt Chromium package found — downloading Google Chromium .deb..."
                    if wget -q -O /tmp/chromium.deb \
                        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb";
                    then
                        if apt-get install -y /tmp/chromium.deb; then
                            BROWSER_BIN="google-chrome"
                            EXTRA_BROWSER_FLAGS=""
                        fi
                    fi
                    if [[ -z "$BROWSER_BIN" ]]; then
                        echo "ERROR: Could not download/install a Chromium binary for this distro."
                        echo "Install Chromium manually, then re-run this script."
                        exit 1
                    fi
                else
                    echo ""
                    echo "ERROR: No chromium package found in apt for this distro."
                    echo "Install chromium manually, then re-run this script."
                    exit 1
                fi
                ;;
            fedora)
                if dnf list installed chromium >/dev/null 2>&1 || apt-cache show chromium >/dev/null 2>&1; then
                    dnf install -y chromium 2>/dev/null || apt-get install -y chromium
                else
                    dnf install -y chromium 2>/dev/null || true
                fi
                BROWSER_BIN="chromium"
                ;;
            arch)
                pacman -S --noconfirm chromium
                BROWSER_BIN="chromium"
                ;;
            suse)
                zypper --non-interactive install chromium
                BROWSER_BIN="chromium"
                ;;
            *)
                echo "WARNING: No known Chromium install path for '$DISTRO_ID'."
                echo "Install a browser manually, then re-run this script."
                exit 1
                ;;
        esac
    fi

    # Verify the browser binary resolves (chrome -> /usr/bin/google-chrome etc.)
    if [[ -n "$BROWSER_BIN" ]] && ! have_cmd "$BROWSER_BIN"; then
        # Some chromium builds name the binary differently; search common names.
        for cand in chromium chromium-browser google-chrome google-chrome-stable; do
            if have_cmd "$cand"; then
                BROWSER_BIN="$cand"
                break
            fi
        done
    fi

    if ! have_cmd "$BROWSER_BIN"; then
        echo ""
        echo "ERROR: Browser binary '$BROWSER_BIN' not found after installation."
        exit 1
    fi
    echo "Browser binary: $(command -v "$BROWSER_BIN")"
    echo ""
fi

# ─── HELPER FUNCTIONS ────────────────────────────────────────────────────────
copy_if_exists() {
    local src="$1" dst="$2" name
    name="$(basename "$dst")"
    if [[ ! -f "$src" ]]; then
        echo "  WARNING: source not found — $src"
        return 1
    fi
    if [[ "$src" -ef "$dst" ]]; then
        echo "  OK: $name (already in place)"
        return 0
    fi
    cp "$src" "$dst" && echo "  Copied: $name"
}

# Find a file in the source tree. Prefers the repo root, then a nested
# 'scoreboard/' staging dir, handling the lowercase vs uppercase 'CSS' quirk.
find_src() {
    local rel="$1"
    if [[ -f "$SCRIPT_DIR/$rel" ]]; then
        echo "$SCRIPT_DIR/$rel"; return
    fi
    if [[ -n "${rel##templates/*}" && -f "$SCRIPT_DIR/templates/$(basename "$rel")" ]]; then
        echo "$SCRIPT_DIR/templates/$(basename "$rel")"; return
    fi
    # static/CSS vs static/css
    if [[ "$rel" == static/css/* && -f "$SCRIPT_DIR/static/CSS/$(basename "$rel")" ]]; then
        echo "$SCRIPT_DIR/static/CSS/$(basename "$rel")"; return
    fi
    if [[ -f "$SCRIPT_DIR/scoreboard/$rel" ]]; then
        echo "$SCRIPT_DIR/scoreboard/$rel"; return
    fi
    echo ""
}

# ─── APPLICATION DIRECTORIES ─────────────────────────────────────────────────
echo "--- Setting Up Application Directories ---"
# Every directory the app touches at runtime, so nothing relies on lazy mkdir.
mkdir -p "$APP_DIR/templates"
mkdir -p "$APP_DIR/static/css"
mkdir -p "$APP_DIR/static/uploads"
mkdir -p "$APP_DIR/static/uploads/specials"
mkdir -p "$APP_DIR/static/uploads/rss_logos"
echo "  Created: $APP_DIR/templates"
echo "  Created: $APP_DIR/static/css"
echo "  Created: $APP_DIR/static/uploads"
echo "  Created: $APP_DIR/static/uploads/specials"
echo "  Created: $APP_DIR/static/uploads/rss_logos"
echo ""

# ─── COPY APPLICATION FILES ──────────────────────────────────────────────────
echo "--- Copying Application Files ---"

# Main application source
copy_if_exists "$SCRIPT_DIR/app.py" "$APP_DIR/app.py" || true

# Templates
for tmpl in index.html login.html settings.html; do
    SRC=$(find_src "templates/$tmpl")
    if [[ -n "$SRC" ]]; then
        copy_if_exists "$SRC" "$APP_DIR/templates/$tmpl" || true
    else
        echo "  WARNING: template not found — templates/$tmpl"
    fi
done

# Stylesheet (templates reference static/css/main.css)
SRC=$(find_src "static/css/main.css")
if [[ -n "$SRC" ]]; then
    copy_if_exists "$SRC" "$APP_DIR/static/css/main.css" || true
else
    echo "  WARNING: stylesheet not found — static/css/main.css"
fi

# version.txt — read by the /api/update/version endpoint
copy_if_exists "$SCRIPT_DIR/version.txt" "$APP_DIR/version.txt" || true

# settings.json — preserve existing config if already installed
if [[ ! -f "$APP_DIR/settings.json" ]]; then
    copy_if_exists "$SCRIPT_DIR/settings.json" "$APP_DIR/settings.json" || true
else
    echo "  OK: settings.json (existing config preserved)"
fi

# kiosk.json — kiosk mode: create with the chosen server URL if absent.
#              server/combined: preserve if present, else copy default.
if [[ ! -f "$APP_DIR/kiosk.json" ]]; then
    if [[ "$MODE" == "kiosk" ]]; then
        echo "{\"server_url\": \"$KIOSK_SERVER_URL\"}" > "$APP_DIR/kiosk.json"
        echo "  Created: kiosk.json (server: $KIOSK_SERVER_URL)"
    else
        copy_if_exists "$SCRIPT_DIR/kiosk.json" "$APP_DIR/kiosk.json" || true
    fi
else
    echo "  OK: kiosk.json (existing config preserved)"
fi

# paired_kiosks.json — kiosk registry consumed by the pairing endpoint.
if [[ ! -f "$APP_DIR/paired_kiosks.json" ]]; then
    if [[ -f "$SCRIPT_DIR/paired_kiosks.json" ]]; then
        copy_if_exists "$SCRIPT_DIR/paired_kiosks.json" "$APP_DIR/paired_kiosks.json" || true
    else
        echo "{}" > "$APP_DIR/paired_kiosks.json"
        echo "  Created: paired_kiosks.json (empty registry)"
    fi
else
    echo "  OK: paired_kiosks.json (existing config preserved)"
fi

# requirements.txt — records pip deps for the backend
copy_if_exists "$SCRIPT_DIR/requirements.txt" "$APP_DIR/requirements.txt" || true

# Optional helper scripts (copied if they exist in the source tree)
for f in debug.py debug2.py init_display.sh setup_kiosk_service.sh; do
    copy_if_exists "$SCRIPT_DIR/$f" "$APP_DIR/$f" || true
done

# Default logo (templates reference /static/uploads/logo.png). If the repo
# carries one, provision it; otherwise flag it so it can be set via Settings.
if [[ -f "$SCRIPT_DIR/static/uploads/logo.png" ]]; then
    copy_if_exists "$SCRIPT_DIR/static/uploads/logo.png" "$APP_DIR/static/uploads/logo.png" || true
elif [[ -f "$SCRIPT_DIR/logo.png" ]]; then
    copy_if_exists "$SCRIPT_DIR/logo.png" "$APP_DIR/static/uploads/logo.png" || true
else
    echo "  NOTE: no default logo found — set one from the Settings page."
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

    echo "--- Disabling other desktop managers ---"
    # Only one display manager can own the seat. LightDM is what we configure
    # for autologin, so disable anything else (GDM, SDDM, LXDM, SLiM) that
    # might be the active session on a pre-existing desktop install.
    for dm in gdm gdm3 sddm lxdm slim lightdm; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${dm}.service"; then
            if [[ "$dm" != "lightdm" ]]; then
                systemctl disable "$dm.service" 2>/dev/null || true
                echo "  Disabled: $dm.service"
            fi
        fi
    done
    echo ""

    echo "--- Configuring Auto-Login (LightDM) ---"
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-scoreboard.conf <<EOF
[Seat:*]
autologin-user=$APP_USER
autologin-user-timeout=0
user-session=openbox
EOF
    # If lightdm uses a greeter service set, ensure it's not blocked by an
    # active gdm targeting the default display-manager.service alias.
    if [ -f /etc/systemd/system/display-manager.service ]; then
        CURRENT_DM="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null)"
        if [[ -n "$CURRENT_DM" ]]; then
            echo "  Display-manager currently points to: $CURRENT_DM"
            rm -f /etc/systemd/system/display-manager.service
        fi
    fi
    # Point the default display-manager alias at LightDM.
    systemctl enable lightdm.service 2>/dev/null || true
    ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service 2>/dev/null \
        || ln -sf /usr/lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service 2>/dev/null || true
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

# ─── SUDOERS — all modes ─────────────────────────────────────────────────────
echo "--- Configuring Sudoers ---"
SYSTEMCTL_PATH=$(command -v systemctl)
NMCLI_PATH=$(command -v nmcli 2>/dev/null || echo /usr/bin/nmcli)
IWLIST_PATH=$(command -v iwlist 2>/dev/null || echo /usr/sbin/iwlist)
IW_PATH=$(command -v iw 2>/dev/null || echo /usr/sbin/iw)
WPA_CLI_PATH=$(command -v wpa_cli 2>/dev/null || echo /usr/sbin/wpa_cli)
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
    systemctl enable scoreboard-fallback-ip.service 2>/dev/null || true
    systemctl restart scoreboard-fallback-ip.service 2>/dev/null || true
    echo "Fallback IP 192.168.1.250 enabled on $ETH_IFACE"
else
    echo "WARNING: No ethernet interface detected — skipping fallback IP setup."
fi
echo ""

# ─── PERMISSIONS ─────────────────────────────────────────────────────────────
echo "--- Setting Permissions ---"
chown -R "$APP_USER:$APP_USER" "$APP_DIR" 2>/dev/null || true
chmod -R 755 "$APP_DIR"
[[ -f "$APP_DIR/settings.json" ]]  && chmod 664 "$APP_DIR/settings.json"
[[ -f "$APP_DIR/kiosk.json" ]]     && chmod 664 "$APP_DIR/kiosk.json"
[[ -f "$APP_DIR/paired_kiosks.json" ]] && chmod 664 "$APP_DIR/paired_kiosks.json"
[[ -f "$APP_DIR/start_kiosk.sh" ]] && chmod +x "$APP_DIR/start_kiosk.sh"
[[ -f "$APP_DIR/init_display.sh" ]] && chmod +x "$APP_DIR/init_display.sh"
[[ "$MODE" == "kiosk" || "$MODE" == "combined" ]] && chown -R "$APP_USER:$APP_USER" "/home/$APP_USER/.config" 2>/dev/null || true
echo "Permissions set on $APP_DIR"
echo ""

# ─── ENABLE SERVICES ─────────────────────────────────────────────────────────
echo "--- Enabling Services ---"
systemctl daemon-reload
systemctl enable scoreboard.service 2>/dev/null || true
echo "Enabled: scoreboard.service"
if [[ -f "$APP_DIR/app.py" ]]; then
    systemctl restart scoreboard.service && echo "Started:  scoreboard.service" \
        || echo "WARNING: scoreboard.service failed to start — check journalctl -u scoreboard."
else
    echo "WARNING: $APP_DIR/app.py not found — scoreboard service not started."
fi

if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    systemctl enable lightdm.service 2>/dev/null || true
    echo "Enabled: lightdm.service"
    systemctl enable kiosk.service 2>/dev/null || true
    echo "Enabled: kiosk.service"
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

REQUIRED_FILES="$APP_DIR/app.py
$APP_DIR/templates/index.html
$APP_DIR/templates/login.html
$APP_DIR/templates/settings.html
$APP_DIR/static/css/main.css
$APP_DIR/version.txt"
WARN=0
for f in $REQUIRED_FILES; do
    [[ ! -f "$f" ]] && echo "  WARNING: Missing — $f" && WARN=1
done

if [[ "$MODE" == "server" ]]; then
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "  Backend URL : http://${SERVER_IP:-<this-machine-ip>}:5000"
    echo "  Point your kiosk(s) to this address in their settings."
    echo ""
elif [[ "$MODE" == "kiosk" ]]; then
    echo "  Browser       : $BROWSER_BIN"
    echo "  Display       : http://localhost:$DISPLAY_PORT"
    echo "  Remote server : $KIOSK_SERVER_URL"
    echo "  (Edit $APP_DIR/kiosk.json or use Settings to change the server URL)"
    echo ""
    echo "  The system will reboot in 10 seconds and boot directly"
    echo "  into the scoreboard kiosk via HDMI."
    echo "  Press Ctrl+C to cancel the reboot."
else
    echo "  Browser : $BROWSER_BIN"
    echo "  Display : http://localhost:$DISPLAY_PORT"
    echo ""
    echo "  The system will reboot in 10 seconds and boot directly"
    echo "  into the scoreboard kiosk via HDMI."
    echo "  Press Ctrl+C to cancel the reboot."
fi

[[ $WARN -eq 1 ]] && echo ""
echo "======================================================="

if [[ "$MODE" == "kiosk" || "$MODE" == "combined" ]]; then
    sleep 10
    reboot
fi
