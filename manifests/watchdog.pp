#
# @summary Coordinates the IPMI watchdog supervisors
#
# ipmi_watchdog is a single-open device: a second process that opens
# /dev/watchdog gets EBUSY, and whoever holds it controls the BMC timer.
# Exactly one component should therefore own the watchdog. Each owner is
# declared only when it is the chosen one, so the others stay unmanaged and
# cannot compete for the device.
#
# @api private
#
class ipmi::watchdog {
  assert_private()

  # OpenIPMI is the owner. IPMI_WATCHDOG=yes makes the OpenIPMI service load
  # ipmi_watchdog; see ipmi::watchdog::openipmi.
  class { 'ipmi::watchdog::openipmi':
    enable => $ipmi::watchdog,
  }

  contain ipmi::watchdog::openipmi
}
