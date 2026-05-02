# Auggmented Scoreboard

**Auggmented Scoreboard** is a Python-based web application designed to turn any TV into a dynamic sports ticker and schedule board. [cite_start]Developed for professional and local sports enthusiasts, it fetches real-time data from ESPN and integrates local school schedules via RSS, iCal, or MaxPreps feeds. 

---

## What It Does
* [cite_start]**Live Scores & Tickers**: Displays real-time scores for NFL, MLB, NBA, NHL, and more. 
* [cite_start]**Racing & Golf**: Specialized leaderboard cards for NASCAR, IndyCar, F1, and PGA. 
* [cite_start]**Local Sports Integration**: Automatically parses school calendars (Thrillshare, MaxPreps, iCal) to show local high school or community games. 
* [cite_start]**Kiosk/Server Architecture**: Run one central **Server** and pair multiple **Kiosks** (TVs) to it for synchronized data but independent display settings. 
* [cite_start]**Smart Automation**: Built-in display scheduling to turn TVs on/off at specific times and auto-update functionality via GitHub or local zip packages. 

---

## Requirements
* **Operating System**: 
    * **Raspberry Pi**: Raspberry Pi OS (Lite is recommended for Server; Desktop for Kiosk).
    * **Generic PC**: Debian or Ubuntu-based Linux distributions.
* **Hardware**: Raspberry Pi 3/4/5 or any x86_64 PC.
* **Environment**: The installer is designed for a **non-graphical (CLI)** environment or a fresh OS install. It installs and configures its own minimal window manager (Openbox) and display server (X11) for Kiosk mode.

---

## Installation

1. **Prepare the OS**: Start with a fresh install of Raspberry Pi OS or Ubuntu/Debian.
2. **Download Files**: Place `app.py`, `install.sh`, `version.txt`, and the `templates/` folder in a directory (e.g., `/home/auggie/scoreboard`).
3. **Run the Installer**:
   ```bash
   chmod +x install.sh
   sudo ./install.sh

   Choose Your Mode:

Server: No display. Acts as the data hub.

Kiosk: A display-only client that points to a server.

Combined: Runs both backend and display on one machine.

Google Chrome Troubleshooting (x86_64)
On PC-based Linux (x86_64), the script prefers Google Chrome for kiosk stability, while Raspberry Pi (ARM) always uses Chromium.

If Chrome fails to install:
Manual Download: If the installer cannot find the .deb file, download it manually:

Bash
wget [https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb](https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb)
Placement: Ensure the .deb file is in the same folder as install.sh before running the installer.

Dependency Fix: If you see "broken packages," run:

Bash
sudo apt --fix-broken install
Fallback: If Chrome is not found or fails, the install.sh script automatically falls back to chromium-browser.

How It Works & Tips
Pairing Kiosks
If you are running in Kiosk mode, go to the Settings page on your Server to generate a "Pairing Code". Enter that code on the Kiosk's startup screen to securely link the Kiosk to the Server's data.   

Local Schedules
To add your local school's games, go to Settings > Local Schedule. Paste the URL of the school's athletic page or MaxPreps link; the app will attempt to detect the feed type (Thrillshare, MaxPreps, or RSS) automatically.   

Display Control
The app uses xset to control the TV backlight.  Ensure your TV supports CEC or DPMS over HDMI for the "Power On/Off" features to work correctly. The start_kiosk.sh script handles "uncluttering" the mouse cursor so it disappears from the screen.  

Troubleshooting

Black Screen on Boot: Check the service status with systemctl status kiosk.service.  Ensure your graphics drivers are installed if it cannot open the display.  


Data Not Updating: Check the backend logs with journalctl -u scoreboard -f and verify the machine has internet access to reach ESPN’s APIs.   

Sudo Errors: The app requires specific NOPASSWD entries in /etc/sudoers.d/scoreboard to control the display and services from the web UI. These are created automatically by the installer.
