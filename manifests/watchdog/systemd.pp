#
# @summary Let systemd (PID 1) own /dev/watchdog
#
# Declared by ipmi::watchdog only when systemd is the chosen owner. The device
# can only be opened once, so ipmi::watchdog also forces the OpenIPMI
# service's IPMI_WATCHDOG to "no" alongside this class.
#
# Writes a system.conf [Manager] drop-in. RuntimeWatchdogSec is always
# written, and `0` means off, matching the systemd default: no watchdog device
# is opened, configured or pinged. This lets a host with a buggy BMC watchdog
# keep `watchdog => true` (module loaded) while systemd leaves the device
# alone.
#
# WatchdogDevice is not written unless set in `options`. systemd tries
# /dev/watchdog0 first and, from 252, falls back to /dev/watchdog. On a host
# with another watchdog driver loaded, such as iTCO_wdt, /dev/watchdog0 may
# not be the BMC, so set `WatchdogDevice` in `options`.
#
# @param enable
#   Whether the drop-in is present. When `false` it is removed.
# @param timeout
#   Seconds, written as RuntimeWatchdogSec. `0` is off.
# @param options
#   Extra [Manager] settings. A `RuntimeWatchdogSec` here replaces `timeout`.
#
# @api private
#
class ipmi::watchdog::systemd (
  Boolean $enable,
  Integer[0] $timeout = 0,
  Systemd::ServiceManagerSettings $options = {},
) {
  assert_private()

  if $enable {
    $ensure = 'present'
  } else {
    $ensure = 'absent'
  }

  systemd::system::manage_dropin { '50-ipmi-watchdog.conf':
    ensure       => $ensure,
    system_entry => { 'RuntimeWatchdogSec' => $timeout } + $options,
  }
}
