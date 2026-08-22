# NUT + UPSide on uCore/CoreOS: Troubleshooting and Final Working Configuration

This document records the troubleshooting path used to get Network UPS Tools (NUT) and the UPSide Cockpit extension working correctly on a uCore/CoreOS-based home server.

It is written as a practical reference rather than a transcript. The goal is to preserve the failure chain, the root causes, the exact persistent fixes, and the checks that proved each layer was working.

## Environment / final working state

- uCore HCI / Fedora 44
- NUT 2.8.5-3.fc44
- UPSide 1.0.6
- CyberPower GX1500U / USB `0764:0601`
- UPS name `CyberPower-UPS`

The final working stack is:

```text
CyberPower GX1500U
        |
        | USB 0764:0601
        v
udev permissions -> root:nut, mode 0664
        |
        v
usbhid-ups driver
        |
        v
nut-server / upsd
        |
        +--> nut-monitor / upsmon
        |
        +--> UPSide
```

Final basic validation:

```bash
upsc -l
```

Expected:

```text
CyberPower-UPS
```

```bash
upsc CyberPower-UPS ups.status
```

Expected when utility power is present:

```text
OL
```

---

## 1. Initial symptoms

NUT was installed in the custom uCore image, but the running server was not fully operational as a UPS host.

The problems appeared in layers.

### NUT server was inactive

`nut-server.service` was enabled but initially inactive.

Starting it manually brought `upsd` up, but it immediately showed:

```text
Can't connect to UPS [CyberPower-UPS] (/run/nut/usbhid-ups-CyberPower-UPS):
No such file or directory
```

This meant `upsd` knew a UPS section existed, but no driver socket had been created.

### Driver enumerator was disabled

The following were both disabled:

```text
nut-driver-enumerator.service
nut-driver-enumerator.path
```

There was also no active driver instance:

```bash
systemctl list-units --all 'nut-driver*'
```

Only `nut-driver.target` was active.

### Driver instance existed but could not open the UPS

After enabling the enumerator, the generated unit appeared:

```text
nut-driver@CyberPower-UPS.service
```

but the driver failed repeatedly with:

```text
libusb1: Could not open any HID devices: insufficient permissions on everything
No matching HID UPS found
```

### NUT could list the UPS name but the driver was disconnected

At one point:

```bash
upsc -l
```

returned:

```text
CyberPower-UPS
```

but:

```bash
upsc CyberPower-UPS ups.status
```

returned:

```text
Error: Driver not connected
```

That distinction was important: `upsd` knew the configured UPS name, but the actual hardware driver was not running.

### nut-monitor was polling the wrong UPS name

`nut-monitor.service` was running, but the journal repeated:

```text
Poll UPS [ups] failed - [ups] does not exist on server localhost
```

The actual UPS name was:

```text
CyberPower-UPS
```

### UPSide Control failed in multiple stages

UPSide first showed:

```text
NUT does not recognise this UPS.
```

Later, after the driver problem was fixed, Control authentication failed with:

```text
Could not reach NUT: not-found
```

After fixing the NUT listener, it progressed again and failed with:

```text
Invalid NUT username or password.
```

Each error represented a different layer of the stack.

---

## 2. Enable the required NUT services on the actual UPS host

The image can reasonably ship with NUT installed but disabled for generic users. On a machine that actually owns a UPS, the required services need to be enabled persistently.

The driver enumerator service and path watcher were enabled:

```bash
sudo systemctl enable --now \
    nut-driver-enumerator.service \
    nut-driver-enumerator.path
```

The path unit watches:

```text
/etc/ups/ups.conf
/etc/ups/nut.conf
```

and triggers re-enumeration when configuration changes.

The generated UPS driver unit became:

```text
nut-driver@CyberPower-UPS.service
```

The NUT server and monitor were also enabled on this machine:

```text
nut-server.service
nut-monitor.service
```

Useful checks:

```bash
systemctl is-enabled nut-server.service
systemctl is-enabled nut-monitor.service
systemctl is-enabled nut-driver-enumerator.service
systemctl is-enabled nut-driver-enumerator.path
```

---

## 3. USB permissions problem on CoreOS/uCore

The kernel saw the UPS correctly:

```bash
lsusb
```

Relevant device:

```text
Bus 001 Device 003: ID 0764:0601 Cyber Power System, Inc. PR1500LCDRT2U UPS
```

The installed Fedora NUT udev rule also explicitly covered this exact device:

```bash
grep -n -i -E '0764|0601|Cyber' /usr/lib/udev/rules.d/62-nut-usbups.rules
```

Relevant rule:

```text
ATTR{idVendor}=="0764", ATTR{idProduct}=="0601", MODE="664", GROUP="dialout"
```

The resulting USB node was:

```text
crw-rw-r--. 1 root dialout ...
```

However:

```bash
id nut
```

showed:

```text
uid=57(nut) gid=57(nut) groups=57(nut)
```

The `nut` user was not a member of `dialout`.

### Why simply adding `nut` to dialout was not a good fix here

A normal:

```bash
sudo usermod -aG dialout nut
```

returned success but did not change the effective membership.

Investigation showed:

```bash
getent group dialout
```

returned:

```text
dialout:x:18:
```

while:

```bash
grep '^dialout:' /etc/group /usr/lib/group
```

showed:

```text
/usr/lib/group:dialout:x:18:
```

So `dialout` came from the immutable vendor account database under `/usr/lib/group`.

The NUT package included:

```text
/usr/lib/sysusers.d/nut-common-sysusers.conf
```

with:

```text
u nut 57 'Network UPS Tools' /run/nut /bin/false
m nut dialout
m nut tty
```

But on this CoreOS-style system the supplementary memberships were not materialized as expected.

A safe test using a temporary root showed that `systemd-sysusers` would create new local groups with incorrect GIDs inside the test tree:

```text
dialout:x:999:nut
tty:x:998:nut
```

while the real system groups are:

```text
dialout = GID 18
tty     = GID 5
```

Therefore the real system group database was deliberately left untouched.

### Persistent CoreOS-friendly fix: local udev rule

Instead of modifying system groups, a local udev override was created for only this exact UPS:

```bash
sudo tee /etc/udev/rules.d/99-nut-cyberpower-local.rules >/dev/null <<'EOF_RULE'
# Local NUT access for CyberPower PR1500LCDRT2U UPS
SUBSYSTEM=="usb", ATTR{idVendor}=="0764", ATTR{idProduct}=="0601", MODE="0664", GROUP="nut"
EOF_RULE
```

Apply the rule:

```bash
sudo udevadm control --reload-rules

sudo udevadm trigger \
    --action=change \
    --subsystem-match=usb \
    --attr-match=idVendor=0764 \
    --attr-match=idProduct=0601

sudo udevadm settle
```

The USB node then became:

```text
crw-rw-r--. 1 root nut ...
```

This was the desired result.

No broad USB permissions such as `0666` were used.

---

## 4. Restart and verify the CyberPower driver

Restart only the generated UPS driver instance:

```bash
sudo systemctl restart nut-driver@CyberPower-UPS.service
```

Then verify:

```bash
systemctl status nut-driver@CyberPower-UPS.service
```

Successful startup included:

```text
Active: active (running)
Listening on socket /run/nut/usbhid-ups-CyberPower-UPS
Startup successful: usbhid-ups
```

The CyberPower driver also printed:

```text
Defaulting 'pollfreq' to 12 for CPS devices
You may want to set 'pollonly' flag on CPS devices
```

Those messages were informational and not the failure being investigated.

Now:

```bash
upsc CyberPower-UPS ups.status
```

returned:

```text
OL
```

At this point the hardware -> driver -> upsd path was working.

---

## 5. Fix the stale UPS name in `upsmon.conf`

The actual UPS section in `/etc/ups/ups.conf` was:

```ini
[CyberPower-UPS]
    driver = "usbhid-ups"
    port = "auto"
    vendorid = "0764"
    productid = "0601"
    product = "GX1500U"
    serial = "QBAQX2000662"
    vendor = "CPS"
```

However `/etc/ups/upsmon.conf` contained:

```text
MONITOR ups 1 upside-monitor <redacted> primary
```

This caused:

```text
Poll UPS [ups] failed - [ups] does not exist on server localhost
```

A backup was made first:

```bash
sudo cp -a /etc/ups/upsmon.conf /etc/ups/upsmon.conf.pre-cyberpower-fix
```

Then only the UPS name was changed:

```bash
sudo sed -i 's/^MONITOR ups /MONITOR CyberPower-UPS /' /etc/ups/upsmon.conf
```

Final form:

```text
MONITOR CyberPower-UPS 1 upside-monitor <redacted> primary
```

Restart:

```bash
sudo systemctl restart nut-monitor.service
```

Successful journal output then showed:

```text
UPS: CyberPower-UPS (primary) (power value 1)
```

The old `Poll UPS [ups] failed` loop disappeared.

UPSide then correctly displayed the local server as a protected primary host.

---

## 6. `upsmon.pid` warning and SELinux

After `nut-monitor` was working, startup still logged:

```text
writepid: fopen /run/nut/upsmon.pid: Permission denied
```

The runtime directory itself looked correct:

```text
drwxrwx---. ... nut dialout system_u:object_r:nut_var_run_t:s0 /run/nut
```

The two upsmon processes were:

```text
root root  ... /usr/bin/upsmon -F
nut  nut   ... /usr/bin/upsmon -F
```

SELinux recorded:

```text
avc: denied { dac_override } for comm="upsmon"
scontext=system_u:system_r:nut_upsmon_t:s0
tclass=capability
```

No custom SELinux allow rule was added.

The Fedora/NUT systemd unit runs:

```text
ExecStart=/usr/bin/upsmon -F
Type=simple
PIDFile=/run/nut/upsmon.pid
```

NUT's own documentation notes that foreground/systemd operation can avoid depending on a PID file.

Since:

- `nut-monitor.service` remained active,
- the correct UPS was recognized,
- monitoring worked,
- no poll/authentication/driver failures remained,

the PID-file warning was treated as a non-fatal NUT/Fedora/SELinux quirk rather than weakening SELinux policy.

---

## 7. UPSide Control could not reach NUT over IPv4

After the driver and monitor were working, UPSide Control still failed with:

```text
Could not reach NUT: not-found
```

The important test was:

```bash
ss -ltnp | grep ':3493'
```

which initially showed only:

```text
[::1]:3493
```

Then:

```bash
upsc CyberPower-UPS@127.0.0.1 ups.status
```

failed with:

```text
Error: Connection failure: Connection refused
```

UPSide 1.0.6 validates a bare local UPS through:

```text
127.0.0.1:3493
```

so the failure was not authentication at all. UPSide simply could not reach the NUT TCP server at the IPv4 loopback address.

### Explicit local-only listeners

`/etc/ups/upsd.conf` had no active `LISTEN` directives.

A backup was created:

```bash
sudo cp -a /etc/ups/upsd.conf /etc/ups/upsd.conf.pre-listen-fix
```

Then both loopback listeners were added:

```ini
# Explicit local listeners for NUT clients and UPSide
LISTEN 127.0.0.1 3493
LISTEN ::1 3493
```

Restart was required because NUT does not apply `LISTEN` changes with reload:

```bash
sudo systemctl restart nut-server.service
```

Verification:

```bash
ss -ltnp | grep ':3493'
```

Expected:

```text
LISTEN ... 127.0.0.1:3493 ...
LISTEN ... [::1]:3493 ...
```

And:

```bash
upsc CyberPower-UPS@127.0.0.1 ups.status
```

returned:

```text
OL
```

Port 3493 remained loopback-only. It was not exposed to LAN or WAN.

---

## 8. UPSide orphaned control user

After the IPv4 listener was fixed, UPSide progressed further but then reported:

```text
Invalid NUT username or password.
```

The UPSide dialog showed:

```text
"upside" already exists
```

Inspection of `/etc/ups/upsd.users` showed two separate accounts:

```text
[upside]
[upside-monitor]
```

Their purposes are different.

### `upside-monitor`

This account is used by `nut-monitor` / `upsmon` for shutdown protection:

```text
[upside-monitor]
    password = <redacted>
    upsmon primary
```

This account had to remain intact.

### `upside`

This was the UPSide Control account:

```text
[upside]
    password = <redacted>
    instcmds = ...
    actions = SET
    upsmon secondary
```

The likely sequence was:

1. UPSide generated a random control password.
2. UPSide wrote `[upside]` to `upsd.users`.
3. UPSide reloaded `nut-server`.
4. UPSide attempted credential validation through `127.0.0.1:3493`.
5. IPv4 localhost was not listening yet.
6. Validation failed before the generated password could be presented successfully.
7. The `[upside]` account remained in `upsd.users`.
8. Later attempts saw an existing user, but the original generated password was no longer available to the operator.

### Remove only the orphaned control account

Backup first:

```bash
sudo cp -a /etc/ups/upsd.users /etc/ups/upsd.users.pre-upside-reset
```

A temporary candidate file was created with only the `[upside]` section removed:

```bash
sudo awk '
/^\[upside\]$/ { skip=1; next }
/^\[/ && skip { skip=0 }
!skip
' /etc/ups/upsd.users > /tmp/upsd.users.new
```

Verify section headers:

```bash
grep -nE '^\[[^]]+\]$' /tmp/upsd.users.new
```

Expected:

```text
[upside-monitor]
```

Then copy the verified contents back into the existing file:

```bash
sudo sh -c 'cat /tmp/upsd.users.new > /etc/ups/upsd.users'
```

Verify again:

```bash
sudo grep -nE '^\[[^]]+\]$' /etc/ups/upsd.users
/etc/pcp/openmetrics/nut
/var/lib/pcp/pmdas/openmetrics/config.d/nut
/var/lib/pcp/config/pmlogger/config.default
```

Expected:

```text
[upside-monitor]
```

Reload NUT:

```bash
sudo systemctl reload nut-server.service
```

UPSide Control was then used again:

```text
Control -> Authenticate -> Create one
```

This time UPSide successfully created the control user and authentication completed.

---

## 9. Final verification

### Driver

```bash
systemctl status nut-driver@CyberPower-UPS.service
```

Expected:

```text
Active: active (running)
```

### Server

```bash
systemctl status nut-server.service
```

Expected:

```text
Active: active (running)
```

### Monitor

```bash
systemctl status nut-monitor.service
```

Expected:

```text
Active: active (running)
```

Journal should show:

```text
UPS: CyberPower-UPS (primary) (power value 1)
```

### Enumerated UPS

```bash
upsc -l
```

Expected:

```text
CyberPower-UPS
```

### Live status

```bash
upsc CyberPower-UPS ups.status
```

Expected on utility power:

```text
OL
```

### IPv4 loopback path used by UPSide

```bash
upsc CyberPower-UPS@127.0.0.1 ups.status
```

Expected:

```text
OL
```

### NUT listeners

```bash
ss -ltnp | grep ':3493'
```

Expected:

```text
127.0.0.1:3493
[::1]:3493
```

### UPSide

Final working state:

- UPS visible and updating
- battery/load/runtime data visible
- server listed as a protected primary host
- Control authentication successful
- local host shutdown configuration visible
- no `Driver not connected`
- no `UNKNOWN-UPS`
- no `Could not reach NUT`
- no repeated `Poll UPS [ups] failed`

---

## 10. Things deliberately not done

Several tempting workarounds were rejected because they would weaken the system or create unnecessary CoreOS-specific state.

### No broad USB permissions

No:

```text
MODE="0666"
```

was used.

Only USB ID `0764:0601` was reassigned to group `nut`.

### No forced `nut` -> `dialout` group hack

The immutable `/usr/lib/group` behavior made traditional supplementary-group assumptions unsafe.

The real CoreOS account database was not rewritten.

### No manual replacement of system groups

The dry-run/test-root investigation showed why blindly running sysusers could create incorrect local GIDs.

No real `dialout` or `tty` group entries were recreated under `/etc/group`.

### No SELinux allow rule for `dac_override`

The single startup AVC was not enough justification to grant a broad DAC-bypass capability.

NUT was already functionally working without that permission.

### No LAN or WAN NUT listener

The final `upsd` listeners are only:

```text
127.0.0.1:3493
[::1]:3493
```

This is enough for local NUT clients and UPSide.

---

## 11. CoreOS/uCore lessons

### Package assumptions can differ from an image-based OS

Traditional Fedora packages often assume local mutable account/group behavior.

On CoreOS/uCore, system users and groups may be split across:

```text
/etc/passwd
/etc/group
/usr/lib/passwd
/usr/lib/group
```

That difference matters when software expects supplementary group membership.

Before using `usermod`, `groupmod`, or `systemd-sysusers` to "fix" a packaged service account, verify where the account and target group actually come from.

Useful commands:

```bash
getent passwd nut
getent group nut
getent group dialout
getent group tty

grep '^nut:' /etc/passwd /usr/lib/passwd 2>/dev/null
grep '^nut:' /etc/group /usr/lib/group 2>/dev/null
grep '^dialout:' /etc/group /usr/lib/group 2>/dev/null
grep '^tty:' /etc/group /usr/lib/group 2>/dev/null
```

### Prefer narrow local overrides

For hardware access, a narrow persistent rule under:

```text
/etc/udev/rules.d/
```

fit the CoreOS model better than modifying immutable or vendor-owned account data.

### Diagnose NUT layer by layer

The most useful order was:

```text
USB visible?
    |
udev permissions correct?
    |
driver instance running?
    |
driver socket exists?
    |
upsd sees the UPS?
    |
upsc can read live data?
    |
upsmon monitors the correct UPS name?
    |
TCP listener matches the client address family?
    |
UPSide authentication works?
```

This avoided treating every UPSide error as an UPSide bug.

---

## 12. UPSide history / PCP

UPSide live monitoring works without historical collection. The **Trends** card reads historical samples from PCP archives.

On this uCore HCI / Fedora 44 host, all required PCP packages were already present in the base image:

```text
pcp-7.2.0-2.fc44.x86_64
pcp-pmda-openmetrics-7.2.0-2.fc44.x86_64
python3-pcp-7.2.0-2.fc44.x86_64
pcp-zeroconf-7.2.0-2.fc44.x86_64
```

Both PCP services were already enabled and active:

```bash
systemctl is-enabled pmcd pmlogger
systemctl is-active pmcd pmlogger
```

Result:

```text
enabled
enabled
active
active
```

### Register the OpenMetrics PMDA

Initially:

```bash
pminfo openmetrics.control.status
```

returned:

```text
Error: openmetrics.control.status: Unknown metric name
```

That confirmed the package was installed but the OpenMetrics PMDA had not been registered.

Register it:

```bash
cd /var/lib/pcp/pmdas/openmetrics
sudo ./Install
```

Successful registration ended with output similar to:

```text
Updating the Performance Metrics Name Space (PMNS) ...
Terminate PMDA if already installed ...
Updating the PMCD control file, and notifying PMCD ...
Check openmetrics metrics have appeared ...
```

Afterward:

```bash
pminfo openmetrics.control.status
```

returned the metric name successfully.

### Let UPSide create the NUT history plumbing

After OpenMetrics was registered, the UPSide **Setup** action created:

```text
/etc/pcp/openmetrics/nut
```

and activated it with:

```text
/var/lib/pcp/pmdas/openmetrics/config.d/nut
    -> /etc/pcp/openmetrics/nut
```

UPSide also added the NUT namespace to the default `pmlogger` configuration:

```text
log mandatory on 1 minute {
    openmetrics.nut
}
```

inside:

```text
/var/lib/pcp/config/pmlogger/config.default
```

This host-local layout is intentional. The PCP/NUT history configuration is kept in writable `/etc` and `/var` paths and is **not baked into the custom bootc image**.

### UPSide 1.0.6 scraper bug discovered

The generated scraper worked when run manually as user `pcp`:

```bash
sudo -u pcp /etc/pcp/openmetrics/nut | head -40
```

It emitted valid metrics such as:

```text
battery_charge{ups="CyberPower-UPS"} 100
battery_runtime{ups="CyberPower-UPS"} 3825
ups_load{ups="CyberPower-UPS"} 11
ups_realpower{ups="CyberPower-UPS"} 99
input_voltage{ups="CyberPower-UPS"} 122.0
output_voltage{ups="CyberPower-UPS"} 122.0
```

However PCP still rejected the source. The control status showed:

```text
inst [6 or "nut"] value "failed to fetch URL or execute script ... returned non-zero exit status 1."
```

The script's final requested NUT variable was `output.frequency`. This UPS does not report that variable.

The generated loop ends each metric with a conditional similar to:

```bash
[[ $val =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && printf ...
```

When the final variable is absent, that final conditional evaluates false and becomes the script's exit status. Therefore the script exits `1` even though it emitted valid OpenMetrics data for all available variables.

The behavior was confirmed directly:

```bash
sudo -u pcp /etc/pcp/openmetrics/nut >/dev/null
echo "exit=$?"
```

Result:

```text
exit=1
```

### Local workaround

Back up the UPSide-generated scraper:

```bash
sudo cp -a /etc/pcp/openmetrics/nut /etc/pcp/openmetrics/nut.pre-exit-fix
```

Append an explicit successful exit:

```bash
echo 'exit 0' | sudo tee -a /etc/pcp/openmetrics/nut
```

The corrected script must end with:

```bash
exit 0
```

Restart PCP:

```bash
sudo systemctl restart pmcd
```

The NUT source then changed to:

```text
inst [6 or "nut"] value "success"
```

and the actual UPS metric became available:

```bash
pminfo -f openmetrics.nut.battery_charge
```

Result:

```text
openmetrics.nut.battery_charge
    inst [0 or "0 ups:CyberPower-UPS"] value 100
```

This is a small UPSide history-scraper bug, not a CoreOS or PCP failure. If UPSide regenerates `/etc/pcp/openmetrics/nut` before the bug is fixed upstream, verify that the explicit `exit 0` is still present.

### Verify pmlogger archives the UPS metrics

Confirm the archive rule exists:

```bash
sudo grep -n -B2 -A4 'openmetrics\.nut' /var/lib/pcp/config/pmlogger/config.default
```

Expected block:

```text
log mandatory on 1 minute {
    openmetrics.nut
}
```

Then locate the newest archive and query it:

```bash
arch=$(ls -t /var/log/pcp/pmlogger/$(hostname)/*.index | head -1)
base=${arch%.index}
echo "$base"

pmrep -z -a "$base" -t 1m -o csv openmetrics.nut.battery_charge | tail -10
```

Working samples on this host looked like:

```text
2026-08-22 04:51:01,100.000
2026-08-22 04:52:01,100.000
2026-08-22 04:53:01,100.000
2026-08-22 04:54:01,100.000
2026-08-22 04:55:01,100.000
```

This proves the PCP archive path is working.

### UPSide 1.0.6 local-history parser bug with PCP 7.2

After PCP was collecting and `pmlogger` had real samples, UPSide still showed:

```text
No history yet
```

and on the detailed Metrics page:

```text
No history for this range
```

The important diagnostic was that UPSide itself reported hundreds of PCP samples in range, while the instance list looked like:

```text
battery_charge: [CyberPower-UPS]]
```

That extra closing `]` was the clue.

The raw PCP 7.2 `pmrep` CSV header was checked directly:

```bash
arch=$(ls -t /var/log/pcp/pmlogger/$(hostname)/*.index | head -1)
base=${arch%.index}

pmrep -z -a "$base" -t 1m -A 1m -s 1 -o csv -f %s \
    openmetrics.nut.battery_charge | head -2
```

Result:

```text
Time,"openmetrics.nut.battery_charge[0 ups:CyberPower-UPS]"
```

UPSide 1.0.6's local archive parser used this regular expression in two places:

```javascript
/ ups:(.+)$/
```

With the PCP 7.2 header, that captures:

```text
CyberPower-UPS]
```

instead of:

```text
CyberPower-UPS
```

UPSide then compares the parsed instance name with the real UPS name exactly, so it rejected otherwise valid historical samples. This was a UI/parser compatibility bug, not a PCP collection failure.

### Local writable workaround for the parser bug

Do not modify the image-owned package under:

```text
/usr/share/cockpit/upside
```

On uCore/CoreOS, `/usr/local` resolves to persistent writable machine state:

```text
/usr/local -> /var/usrlocal
```

Cockpit prefers a package under `/usr/local/share/cockpit` over the same package under `/usr/share/cockpit`, so a local override can patch UPSide without changing the bootc image or vendor files.

Create the local override and a backup:

```bash
sudo mkdir -p /usr/local/share/cockpit
sudo cp -a /usr/share/cockpit/upside /usr/local/share/cockpit/
sudo cp -a /usr/local/share/cockpit/upside/index.js \
    /usr/local/share/cockpit/upside/index.js.pre-pcp-instance-fix
```

Verify Cockpit is using the local package:

```bash
cockpit-bridge --packages | grep -A2 -B2 upside
```

Expected path:

```text
/usr/local/share/cockpit/upside
```

Before patching, verify that the local-history expression occurs exactly twice:

```bash
sudo grep -oF 'const m = / ups:(.+)$/.exec(hh);' \
    /usr/local/share/cockpit/upside/index.js | wc -l
```

Expected:

```text
2
```

Patch only those two local-history parsers:

```bash
sudo sed -i 's|/ ups:(.+)$/|/ ups:(.+?)\\]?$/|g' \
    /usr/local/share/cockpit/upside/index.js
```

The two local parser expressions should become:

```javascript
/ ups:(.+?)\]?$/
```

while the separate remote `pmproxy` parser remains unchanged:

```javascript
/ups:(.+)$/
```

Verify all three relevant expressions:

```bash
sudo grep -oE '.{0,80}ups:\(\.\+\??\).{0,30}' \
    /usr/local/share/cockpit/upside/index.js | head -5
```

Working result:

```text
const m = / ups:(.+?)\]?$/.exec(hh);
const m = / ups:(.+?)\]?$/.exec(hh);
const m = /ups:(.+)$/.exec(r.name.trim());
```

After a hard browser refresh, UPSide Trends displayed the archived battery charge, load, input voltage, output voltage, real power, and battery voltage correctly.

This local package override intentionally shadows future UPSide files under `/usr/share/cockpit/upside`. Once an upstream UPSide release fixes the PCP 7.2 parser, remove the override so the packaged version is used again:

```bash
sudo rm -rf /usr/local/share/cockpit/upside
cockpit-bridge --packages | grep -A2 -B2 upside
```

The second command should then point back to:

```text
/usr/share/cockpit/upside
```

### Important: re-running the UPSide history Setup wizard

UPSide 1.0.6's current history-setup implementation is designed to be **additive and idempotent**. It writes `/etc/pcp/openmetrics/nut` only if that scraper is absent, adds the `pmlogger` rule only if it is absent, and otherwise treats an already configured host as a no-op. It does not manage the `/usr/local/share/cockpit/upside` override.

Therefore, with UPSide 1.0.6 as tested here, simply clicking the history Setup action again should **not** overwrite the existing `exit 0` fix or the local Cockpit parser override.

However, treat any future re-run after an UPSide upgrade, reset, manual deletion, or changed setup implementation as something that can potentially recreate its managed history files. In particular, if `/etc/pcp/openmetrics/nut` is absent, the wizard will recreate it from the bundled UPSide scraper template. Until the scraper bug is fixed upstream, that regenerated file may again lack the explicit `exit 0`.

After any UPSide upgrade, history reset, or Setup re-run, verify both local workarounds before assuming history is still correct:

```bash
sudo tail -8 /etc/pcp/openmetrics/nut

cockpit-bridge --packages | grep -A2 -B2 upside

sudo grep -oE '.{0,80}ups:\(\.\+\??\).{0,30}' \
    /usr/local/share/cockpit/upside/index.js 2>/dev/null | head -5
```

The scraper should still end with:

```text
exit 0
```

and, while this workaround is required, Cockpit should still use `/usr/local/share/cockpit/upside` with exactly the two local parser expressions accepting the optional closing `]`.

The complete working history path is therefore:

```text
NUT
  -> /etc/pcp/openmetrics/nut
  -> OpenMetrics PMDA
  -> openmetrics.nut.*
  -> pmlogger
  -> PCP archive
  -> UPSide local-history parser
  -> UPSide Trends
```

### Keep the PCP/NUT history setup local, not image-owned

The final design decision for this server is:

```text
Keep PCP/NUT history configuration local and writable.
Do not add nut-openmetrics or a setup-nut-history helper to the custom image.
```

Reasons:

- uCore HCI already contains all required PCP packages.
- `pmcd` and `pmlogger` are already enabled by the base system.
- UPSide already performs the one-time host setup after OpenMetrics is registered.
- `/etc/pcp/openmetrics/nut` is legitimate persistent host configuration.
- `/var/lib/pcp/...` and `/var/log/pcp/...` are naturally machine-local PCP state and history.
- keeping the workaround local avoids carrying duplicate UPSide setup logic in the custom image.

Sample files accompanying this document:

```text
samples/nut-openmetrics
samples/pmlogger-openmetrics-nut.conf
samples/README-nut-history-local.md
```

The sample `nut-openmetrics` contains the `exit 0` workaround.

### Unrelated default OpenMetrics sources

The OpenMetrics PMDA registration also activated several packaged sample/default sources. On this host some are not used:

```text
ceph   -> connection refused
dcgm   -> connection refused
etcd   -> connection refused
vllm   -> HTTP 404
grafana -> success
nut    -> success
```

The `vllm` default targets `localhost:8000`, but port 8000 on this server belongs to the Gluetun/qBittorrent networking stack, not vLLM. These failures are unrelated to NUT history.

They can be cleaned up separately by deactivating unused entries from the OpenMetrics `config.d` directory without deleting Fedora's packaged source definitions.

### Notifications still optional

`nut-monitor` currently reports:

```text
Warning: no custom notification command defined, just so you know
```

This is not an operational failure.

Notifications can be configured later through NUT/UPSide without changing the working driver/server/monitor/history stack.

---

## 13. Files changed on the host

Persistent configuration touched during this troubleshooting:

```text
/etc/udev/rules.d/99-nut-cyberpower-local.rules
/etc/ups/upsd.conf
/etc/ups/upsmon.conf
/etc/ups/upsd.users
/etc/pcp/openmetrics/nut
/var/lib/pcp/pmdas/openmetrics/config.d/nut
/var/lib/pcp/config/pmlogger/config.default
/usr/local/share/cockpit/upside/
```

Backups created during the session:

```text
/etc/ups/upsmon.conf.pre-cyberpower-fix
/etc/ups/upsd.conf.pre-listen-fix
/etc/ups/upsd.users.pre-upside-reset
/etc/pcp/openmetrics/nut.pre-exit-fix
/usr/local/share/cockpit/upside/index.js.pre-pcp-instance-fix
```

Temporary troubleshooting data under `/tmp` was removed or can be safely removed after verification.

---

## Final state

The native NUT stack and UPSide are both operational.

The home server:

- owns the CyberPower UPS directly over USB,
- runs the `usbhid-ups` driver,
- exposes the UPS through local `upsd`,
- monitors it as the primary protected host,
- is configured to run `systemctl poweroff` on critical shutdown,
- exposes NUT only on local IPv4 and IPv6 loopback,
- allows UPSide to authenticate with a dedicated control account,
- exports NUT metrics through the PCP OpenMetrics PMDA,
- archives those metrics with `pmlogger`,
- and uses a persistent `/usr/local/share/cockpit/upside` override so UPSide 1.0.6 can correctly parse PCP 7.2 instance labels and display Trends.

The important lesson from this troubleshooting session is that the failures were not one problem. They were a chain of independent issues across service enablement, CoreOS account/group behavior, udev permissions, stale NUT configuration, IPv4/IPv6 listener behavior, an orphaned UPSide control account, OpenMetrics PMDA registration, a non-zero exit bug in the UPSide-generated history scraper, and a second UPSide 1.0.6 parser bug with PCP 7.2 instance headers.

Solving each layer independently produced a clean working configuration without weakening USB permissions, replacing CoreOS system groups, or relaxing SELinux.
