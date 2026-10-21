# Haku connection ports

Haku's GUI and terminal client connect to **haku-server on the same phone**.
Both default to `127.0.0.1:57042`. The upstream Frida service uses its own
package and ports; changing Haku's port does not reconfigure Frida.

| Component | Default | Configuration | Privilege |
| --- | --- | --- | --- |
| haku-server daemon | `127.0.0.1:57042` | `hakuctl port PORT` | root |
| Haku GUI/client | `127.0.0.1:57042` | Connection screen or `--set-port PORT` | mobile |
| One terminal invocation | Saved Haku destination | `--port PORT` | mobile |
| Upstream Frida | Separate installation, normally `27042` | Upstream configuration | Independent |

Allowed values are decimal ports **1–65535 excluding 27042 and 27043**. Empty,
signed, nondecimal and out-of-range values are rejected. This preserves the
requested separation from ordinary Frida; it is unrelated to target-app
selection. There is no fallback to another port or service.

## Change to 58000

First run on the **iPhone as root**:

```sh
/var/jb/usr/bin/hakuctl port 58000
/var/jb/usr/bin/hakuctl status
```

The first command saves the port and restarts only the Haku daemon. Then open
**Haku → Connection**, enter **58000** in **Port**, and tap **Save**. Return to
the application list and pull to refresh. The GUI setting changes the client
destination, so it must match the daemon setting.

The equivalent client commands run as **mobile**:

```sh
/var/jb/Applications/Haku.app/Haku --set-port 58000
/var/jb/Applications/Haku.app/Haku --connection
/var/jb/Applications/Haku.app/Haku --list
```

Expected connection output includes `"endpoint":"127.0.0.1:58000"`. The saved
preference is per user: setting it as root does not configure the mobile GUI.

For one command without changing the saved app preference:

```sh
/var/jb/Applications/Haku.app/Haku --port 58000 --list
/var/jb/Applications/Haku.app/Haku --port 58000 --dump org.example.myapp \
  /var/mobile/Documents/Haku/myapp-custom-port-run-001
```

`--port` does not start or reconfigure the daemon. Every export report records
the actual endpoint under `server_endpoint`.

## Persistence, status and reset

The daemon's configuration is `/var/jb/etc/haku-server.port`, a preserved Debian
configuration file. Use `hakuctl` to change it. Restarting or upgrading the
server preserves a valid custom port. The app saves its destination across
fresh launches and upgrades.

On the phone as root:

```sh
/var/jb/usr/bin/hakuctl port
/var/jb/usr/bin/hakuctl status
/var/jb/usr/bin/hakuctl restart
```

`hakuctl start` and `hakuctl stop` also control only
`com.jacklee.haku-server`. To restore the default, run as root:

```sh
/var/jb/usr/bin/hakuctl port 57042
```

Then save **57042** in Haku's Connection screen, or run as mobile:

```sh
/var/jb/Applications/Haku.app/Haku --set-port 57042
/var/jb/Applications/Haku.app/Haku --connection
/var/jb/Applications/Haku.app/Haku --list
```

## Optional Mac connection over an existing SSH setup

The packaged daemon listens on the phone's loopback interface. If the lab
already has a configured iPhone SSH alias, forward a local Mac port to the
chosen phone port. For example, when the daemon uses 58000:

```sh
ssh -N -L 58000:127.0.0.1:58000 iphone-lab
```

Keep that session open. A compatible Frida **17.24.3** client on the Mac can
then explicitly select the forwarded endpoint:

```sh
frida-ps -H 127.0.0.1:58000 -ai
```

Replace `iphone-lab` with the lab's actual SSH configuration. The Mac-side
port may differ if already occupied; the forwarding destination must match
the daemon. This is an SSH example, not a required step for on-device Haku.
An ordinary `frida -U` connection selects the upstream USB service rather than
automatically selecting Haku's custom listener.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Connection refused | Compare `hakuctl port` as root with Haku `--connection` as mobile; check `hakuctl status`. |
| Wrong server or protocol error | Install the matched haku-server package and select its explicit port. |
| List fails immediately after restart | Allow service startup to finish, then refresh; check daemon status if it continues. |
| Address already in use | Choose an unused allowed port and set both daemon and client to it. |
| Client reaches the old port | Check the user whose preferences were saved; `--port` overrides only that invocation. |
| Root required | Change the daemon through a root terminal; use mobile for the GUI's preferences. |

Default-port full acquisition, custom-port acquisition, preference persistence,
server restart, upgrade preservation and Frida coexistence have separate
entries in [VALIDATION.md](VALIDATION.md).
