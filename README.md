# InputLeap Client Automation

Systemd service and timer for automatically connecting to an InputLeap server on boot and reconnecting if the connection drops.

## Features

- Auto-connects to InputLeap server on boot
- Periodically reconnects every 30 seconds (handles server disappearing/reappearing)
- Auto-restarts if connection crashes
- Survives system reboots
- Works with system-wide or user-level installation

## Directory Structure

- `system/`: System-level services (runs at boot, no login needed, requires sudo)
- `user/`: User-level services (runs on user login, requires user session)

## Quick Install

### Option 1: Automated (Recommended)

```bash
sudo ./install.sh
```

This will prompt for:
- Username to run InputLeap as (must exist on system)
- Server IP address
- Whether to install system-wide or user-level

### Option 2: Manual Installation

**System-wide (survives reboots, runs immediately):**

```bash
sudo cp system/*.service system/*.timer /etc/systemd/system/
sudo sed -i 's/User=YOUR_USERNAME/User=<USERNAME>/g' /etc/systemd/system/inputleap.service
sudo sed -i 's/192.0.2.1/<SERVER_IP>/g' /etc/systemd/system/inputleap.service
sudo systemctl daemon-reload
sudo systemctl enable inputleap.service inputleap-reconnect.timer
sudo systemctl start inputleap.service inputleap-reconnect.timer
```

**User-level (runs on login):**

```bash
mkdir -p ~/.config/systemd/user
cp user/*.service user/*.timer ~/.config/systemd/user/
sed -i 's/192.0.2.1/<SERVER_IP>/g' ~/.config/systemd/user/inputleap.service
systemctl --user daemon-reload
systemctl --user enable inputleap.service inputleap-reconnect.timer
systemctl --user start inputleap.service inputleap-reconnect.timer
```

## Configuration

Edit the service file to change:
- `ExecStart` path if InputLeap is in a different location
- `192.0.2.1` to your actual server IP
- `RestartSec` if you want faster/slower auto-restart on crash
- `OnUnitActiveSec` in timer if you want different reconnection interval

## Status and Logs

**System-wide:**
```bash
sudo systemctl status inputleap.service
sudo systemctl list-timers
sudo journalctl -u inputleap -f
```

**User-level:**
```bash
systemctl --user status inputleap.service
systemctl --user list-timers
journalctl --user-unit inputleap -f
```

## Stop/Disable

**System-wide:**
```bash
sudo systemctl stop inputleap.service inputleap-reconnect.timer
sudo systemctl disable inputleap.service inputleap-reconnect.timer
```

**User-level:**
```bash
systemctl --user stop inputleap.service inputleap-reconnect.timer
systemctl --user disable inputleap.service inputleap-reconnect.timer
```
