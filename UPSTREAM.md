# Upstream issues

Bugs and missing pieces found while bringing up the R36S, with the
workaround used here. Checked against Linux 7.2.10 and upstream master
as of 2026-10-15.

## Linux: adc-joystick inverts axes using the wrong range

`drivers/input/joystick/adc-joystick.c` calls
`adc_joystick_invert(input, i, val)` with the channel index `i`, but
`adc_joystick_invert()` treats it as the event code when looking up the
axis range:

```c
static int adc_joystick_invert(struct input_dev *dev,
			       unsigned int axis, int val)
{
	int min = input_abs_get_min(dev, axis);
	int max = input_abs_get_max(dev, axis);

	return (max + min) - val;
}
```

Inversion therefore only works when `reg == linux,code` for the axis.
Otherwise the range of an unrelated (usually unset, 0..0) axis is used
and the axis reports `-val`. Seen on the R36S as `ABS_Y` (channel 2)
reporting -783..-447.

- **Fix:** pass `joy->axes[i].code` instead of `i` at both call sites.
- **Workaround here:** the joystick `io-channels` are reordered in
  `dts/rk3326-gameconsole-r36s.dts` so that both inverted axes have
  `reg == linux,code` (`ABS_X` = 0, `ABS_Y` = 1).
- **Send to:** linux-input@vger.kernel.org (Dmitry Torokhov), see
  `scripts/get_maintainer.pl`.

## Linux: rk3326-odroid-go.dtsi lacks `system-power-controller`

The rk817 PMIC node in `arch/arm64/boot/dts/rockchip/rk3326-odroid-go.dtsi`
has no `system-power-controller` property, so the kernel registers no
PMIC restart/power-off handler and relies on PSCI. With the vendor BL31
(v1.3, 2018) still used by the ODROID-GO/ArkOS U-Boot, PSCI
`SYSTEM_RESET` never returns and `reboot` hangs after
"reboot: Restarting system".

- **Fix:** add `system-power-controller;` to the rk817 node. The
  rk8xx driver then restarts via the PMIC's `DEV_RST` and powers off via
  `DEV_OFF`.
- **Workaround here:** added in the R36S DTS.
- **Note:** may not reproduce on boards with mainline TF-A, where PSCI
  reset works. Worth testing on an ODROID-GO Advance/Super before sending.

## Linux: no R36S device tree

Mainline has no R36S support, `dts/rk3326-gameconsole-r36s.dts` builds on
`rk3326-odroid-go3.dts`. Upstreaming needs the panel driver below first,
or a mainline panel driver for the R36S panels. Differences to the
ODROID-GO Super, all verified on hardware:

- OTG VBUS from the rk817 `OTG_SWITCH`, second SD slot on `sdio`
- L3/R3/FN instead of F3-F6, GPIO2_A5 not connected
- left analog stick inverted
- speaker on an external amplifier behind the headphone outputs, the
  rk817 class D output (SPKO) is unused; headphone detect is active low
- battery charged by a separate charger IC, DC detect on GPIO0_B3; the
  rk817 is only used as fuel gauge
- 3380 mAh battery

## ROCKNIX: panel-generic-dsi is out of tree

The display uses ROCKNIX's `panel-generic-dsi` driver
(`drivers/panel-generic-dsi`), which takes the full panel description
from the device tree. It is not in mainline and probably would not be
accepted in this form (DT bindings that encode init sequences are
generally rejected upstream). The mainline path is a proper driver per
panel, e.g. an R36S variant in `panel-sitronix-st7703.c`.

## ROCKNIX: importpanel.py writes delays in decimal, driver parses hex

ROCKNIX's `importpanel.py` emits `wait=<ms>` in decimal, but
`panel-generic-dsi.c` parses it with `simple_strtoul(val, NULL, 16)`, so
e.g. `wait=120` sleeps 288 ms instead of 120 ms. Harmless (only slower),
but one of the two should be changed. The DTS here writes hex values.

## Linux: dwc2 can leave the VBUS regulator off after a port power cycle

`dwc2_handle_session_req_intr()` in `drivers/usb/dwc2/core_intr.c` sets
`HPRT0_PWR` in host mode without enabling `vbus-supply`, while
`_dwc2_hcd_hub_control()` uses `HPRT0_PWR` to decide whether to enable or
disable the regulator. When unplugging a USB device makes the hub driver
power cycle the port ("usb usb1-port1: attempt power cycle"):

1. `ClearPortFeature(POWER)` sees `HPRT0_PWR` set and disables the
   regulator, VBUS goes off.
2. A session request interrupt sets `HPRT0_PWR` again, the regulator
   stays off.
3. `SetPortFeature(POWER)` sees `HPRT0_PWR` already set and does not
   enable the regulator.

The port then has no VBUS until the next reboot: every device fails with
`device descriptor read/8, error -71`, and the next power cycle warns
"unbalanced disables for otg_switch". `dwc2_core_host_init()` also sets
`HPRT0_PWR` without touching the regulator.

- **Fix:** call `dwc2_vbus_supply_init()` wherever `HPRT0_PWR` is turned
  on from off, or track the regulator state in a flag instead of
  deriving it from `HPRT0_PWR`.
- **Workaround here:** `regulator-always-on` on `otg_switch` in the R36S
  DTS, so dwc2 can't turn VBUS off.
- **Send to:** linux-usb@vger.kernel.org (Minas Harutyunyan, dwc2).
