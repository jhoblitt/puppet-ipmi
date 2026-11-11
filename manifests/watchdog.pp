#
# @summary Coordinates the IPMI watchdog pieces
#
# When the watchdog is enabled the ipmi_watchdog kernel module is loaded,
# which creates /dev/watchdog. The module does not start the BMC timer by
# itself; the timer runs once something opens /dev/watchdog (or the module is
# given `start_now=1`).
#
# The device can only be opened once, and whoever holds it controls the BMC
# timer. Exactly one component should therefore own the watchdog. Each owner
# is declared only when it is the chosen one, so the others stay unmanaged.
#
# @api private
#
class ipmi::watchdog {
  assert_private()

  if $ipmi::watchdog and $ipmi::watchdog_manage_module {
    class { 'ipmi::watchdog::kmod':
      timeout => $ipmi::watchdog_timeout,
      options => $ipmi::watchdog_module_options,
    }

    contain ipmi::watchdog::kmod
  }

  # OpenIPMI is the owner: IPMI_WATCHDOG=yes makes its service load the
  # module. See ipmi::watchdog::openipmi.
  class { 'ipmi::watchdog::openipmi':
    enable => $ipmi::watchdog,
  }

  contain ipmi::watchdog::openipmi
}
