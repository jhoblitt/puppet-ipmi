#
# @summary Load the ipmi_watchdog kernel module at boot
#
# Writes /etc/modules-load.d/ipmi_watchdog.conf so the module is loaded at
# boot, and loads it now if it is not loaded. Loading the module creates
# /dev/watchdog but does not start the BMC timer.
#
# Modprobe options are written to /etc/modprobe.d/ipmi_watchdog.conf before
# the module is loaded. They only take effect the next time the module is
# loaded, so changing them on a host where it is already loaded needs a reboot
# or a manual reload.
#
# @param timeout
#   Watchdog timeout in seconds, passed as the `timeout` module option.
#   `0` writes no option, leaving the driver default (10 seconds).
# @param options
#   Extra module options. A `timeout` key here must not disagree with
#   `timeout` above; a mismatch fails the catalog.
#
# @api private
#
class ipmi::watchdog::kmod (
  Integer[0] $timeout = 0,
  Hash[String[1], Scalar] $options = {},
) {
  assert_private()

  if $timeout > 0 and 'timeout' in $options and String($options['timeout']) != String($timeout) {
    fail("ipmi::watchdog_module_options timeout (${options['timeout']}) conflicts with ipmi::watchdog_timeout (${timeout}); set only one")
  }

  if $timeout > 0 {
    $timeout_options = { 'timeout' => $timeout }
  } else {
    $timeout_options = {}
  }

  kmod::load { 'ipmi_watchdog': }

  ($timeout_options + $options).each |$option, $value| {
    kmod::option { "ipmi_watchdog_${option}":
      module => 'ipmi_watchdog',
      option => $option,
      value  => $value,
      before => Kmod::Load['ipmi_watchdog'],
    }
  }
}
