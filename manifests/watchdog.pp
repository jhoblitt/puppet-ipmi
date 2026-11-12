#
# @summary Coordinates the IPMI watchdog pieces
#
# When the watchdog is enabled the ipmi_watchdog kernel module is loaded,
# which creates /dev/watchdog. Loading the module does not start the BMC
# timer: that happens once something opens /dev/watchdog (or the module is
# given `start_now=1`).
#
# The device can only be opened once, and whoever holds it controls the BMC
# timer, so exactly one component should own it. The chosen owner is
# configured and the other one's configuration is removed or switched off:
#
# * systemd opens and pings /dev/watchdog itself (RuntimeWatchdogSec).
# * OpenIPMI only loads the module (IPMI_WATCHDOG=yes). Nothing in this
#   module opens the device, so the timer is started by whatever else does,
#   such as the `watchdog` daemon.
#
# @api private
#
class ipmi::watchdog {
  assert_private()

  # systemd 252 is the first release that falls back to /dev/watchdog when
  # /dev/watchdog0 is missing. ipmi_watchdog only creates /dev/watchdog.
  $systemd_min_version = '252'
  $systemd_version = pick($facts['ipmi_systemd_version'], '0')

  case $ipmi::watchdog_supervisor {
    'systemd':  { $use_systemd = true }
    'openipmi': { $use_systemd = false }
    default:    { $use_systemd = versioncmp($systemd_version, $systemd_min_version) >= 0 }
  }

  class { 'ipmi::watchdog::kmod':
    manage  => $ipmi::watchdog and $ipmi::watchdog_manage_module,
    timeout => $ipmi::watchdog_timeout,
    options => $ipmi::watchdog_module_options,
  }

  contain ipmi::watchdog::kmod

  class { 'ipmi::watchdog::systemd':
    enable  => $use_systemd and $ipmi::watchdog,
    timeout => $ipmi::watchdog_timeout,
    options => $ipmi::watchdog_systemd_options,
  }

  contain ipmi::watchdog::systemd

  Class['ipmi::watchdog::kmod'] -> Class['ipmi::watchdog::systemd']

  if $use_systemd {
    # systemd owns /dev/watchdog. IPMI_WATCHDOG=yes would make the OpenIPMI
    # service also load and unload ipmi_watchdog itself (per upstream
    # ipmi.init), so force it to "no" if the config file exists. The file is
    # not created, and the rest of ipmi::watchdog::openipmi is deliberately not
    # declared.
    class { 'ipmi::watchdog::openipmi::watchdog_param':
      enable         => false,
      only_if_exists => true,
    }

    contain ipmi::watchdog::openipmi::watchdog_param
  } else {
    # OpenIPMI is the owner: IPMI_WATCHDOG=yes makes its service load the
    # module.
    class { 'ipmi::watchdog::openipmi':
      enable => $ipmi::watchdog,
    }

    contain ipmi::watchdog::openipmi

    Class['ipmi::watchdog::openipmi'] ~> Class['ipmi::service::ipmi']
  }
}
