#
# @summary Load the ipmi_watchdog kernel module at boot
#
# Loads ipmi_watchdog through the puppet/kmod module. Loading the module
# creates /dev/watchdog but does not start the BMC timer.
#
# Modprobe options go through the same module and are applied before the
# module loads. See the kmod module documentation for what it writes and how
# options are applied; they take effect only the next time the module is
# loaded, so changing them on a host where it is already loaded needs a reboot
# or a manual reload.
# https://forge.puppet.com/modules/puppet/kmod/readme
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
