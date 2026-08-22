# Local UPSide / PCP history samples

These files are examples for a host-local uCore/CoreOS setup. They are not intended to be baked into the bootc image.

## `nut-openmetrics`

Suggested live location:

```text
/etc/pcp/openmetrics/nut
```

Make it executable:

```bash
sudo chmod +x /etc/pcp/openmetrics/nut
```

Activate it for the PCP OpenMetrics PMDA:

```bash
sudo ln -sfn /etc/pcp/openmetrics/nut /var/lib/pcp/pmdas/openmetrics/config.d/nut
```

The sample contains the explicit `exit 0` workaround required for UPSide 1.0.6 when the last requested NUT variable is absent.

## `pmlogger-openmetrics-nut.conf`

This is a snippet, not a complete replacement file. Add its `log mandatory` block before `[access]` in:

```text
/var/lib/pcp/config/pmlogger/config.default
```

Then restart the relevant PCP services and verify the NUT OpenMetrics namespace before relying on UPSide Trends.

## UPSide 1.0.6 PCP 7.2 parser workaround

On PCP 7.2, `pmrep` can emit a local archive instance header such as:

```text
openmetrics.nut.battery_charge[0 ups:CyberPower-UPS]
```

UPSide 1.0.6's local parser can incorrectly treat the UPS name as `CyberPower-UPS]`, which causes Trends to report no matching history even though PCP returned samples. The tested host-local workaround is to copy the Cockpit package to persistent `/usr/local/share/cockpit/upside` and patch only the two local-history expressions from `/ ups:(.+)$/` to `/ ups:(.+?)\]?$/`. Do not patch the separate remote `pmproxy` expression `/ups:(.+)$/`.

The local Cockpit override shadows the packaged copy under `/usr/share/cockpit/upside`. Remove the override after an upstream UPSide release fixes this parser.

## Re-running UPSide Setup

UPSide 1.0.6's history Setup code is additive: it writes `/etc/pcp/openmetrics/nut` only if that file is absent and adds the pmlogger rule only if missing. Re-running Setup on an already configured host should therefore be a no-op and should not overwrite the current `exit 0` fix or `/usr/local` Cockpit override.

Still, after any UPSide upgrade, reset, manual deletion, or future Setup behavior change, verify the local fixes again. If the scraper is recreated from the bundled template before the upstream bug is fixed, the explicit `exit 0` may need to be restored.
