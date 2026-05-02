# Auggmented Scoreboard

[cite_start]**Auggmented Scoreboard** is a Python-based web application designed to turn any TV into a dynamic sports ticker and schedule board. [cite_start]Developed for professional and local sports enthusiasts, it fetches real-time data from ESPN and integrates local school schedules via RSS, iCal, or MaxPreps feeds.

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
