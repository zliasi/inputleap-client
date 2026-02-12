# inputleap-client

systemd service and timer for automatically connecting to an Input Leap server.

`inputleap-client` manages an [`input-leapc`](https://github.com/input-leap/input-leap) process *via* systemd, handling startup,
crash recovery, and periodic reconnection when the server disappears. It supports
both system-wide and user-level installations.

The reconnect timer uses a health-check (`ExecCondition`) so it only restarts the
service when it is actually down, leaving healthy connections untouched.

## Installation

Clone or download the repository:

```
$ git clone https://github.com/zliasi/inputleap-client.git
$ cd inputleap-client
```

[`input-leapc`](https://github.com/input-leap/input-leap) must already be installed and available in `$PATH`.

### Interactive

Prompts for username, server address, and install type:

```
$ sudo ./install.sh
```

### Non-interactive

```
$ sudo ./install.sh --user john --server 10.0.0.1 --system
$ sudo ./install.sh --user john --server myhost:24800 --user-level
```

Flags:

```
--user USERNAME     Username to run Input Leap as
--server ADDRESS    Server address (IP, hostname, or host:port)
--system            Install system-wide (default)
--user-level        Install as user-level service
--uninstall         Remove installed services
--dry-run           Print rendered unit files without installing
--help              Show help
```

## Dry run

Write the rendered unit files to stdout instead of installing:

```
$ sudo ./install.sh --user john --server 10.0.0.1 --dry-run
```

## Uninstall

```
$ sudo ./install.sh --user john --uninstall --system
$ sudo ./install.sh --user john --uninstall --user-level
```

Stops, disables, and removes all unit files, then reloads the systemd daemon.

## Directory structure

- `system/`: System-level unit templates (runs at boot, no login needed)
- `user/`: User-level unit templates (runs on user login)

Both directories contain template files with `BINARY_PATH` and `SERVER_ADDRESS`
placeholders that the installer replaces at install time.

## Status and logs

System-wide:

```
$ sudo systemctl status inputleap.service
$ sudo systemctl list-timers
$ sudo journalctl -u inputleap -f
```

User-level:

```
$ systemctl --user status inputleap.service
$ systemctl --user list-timers
$ journalctl --user-unit inputleap -f
```
