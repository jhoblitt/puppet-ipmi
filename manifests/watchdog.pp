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

  # ipmi_watchdog only creates /dev/watchdog. With WatchdogDevice unset,
  # systemd up to 249 opens /dev/watchdog and 252 onwards falls back to it,
  # but 250 and 251 open /dev/watchdog0 and nothing else.
  $systemd_version = $facts['ipmi_systemd_version']

  case $ipmi::watchdog_supervisor {
    'systemd':  { $use_systemd = true }
    'openipmi': { $use_systemd = false }
    default:    { $use_systemd = $systemd_version =~ NotUndef and !(String($systemd_version) in ['250', '251']) }
  }

  $timeout = $ipmi::watchdog_timeout
  $module_options = $ipmi::watchdog_module_options
  $load_module = $use_systemd and $ipmi::watchdog and $ipmi::watchdog_manage_module
  $options_used = $load_module or (!$use_systemd and $ipmi::watchdog)

  if $options_used and $timeout > 0 and 'timeout' in $module_options and String($module_options['timeout']) != String($timeout) {
    fail("ipmi::watchdog_module_options timeout (${module_options['timeout']}) conflicts with ipmi::watchdog_timeout (${timeout}); set only one")
  }

  if $timeout > 0 {
    $timeout_options = { 'timeout' => $timeout }
  } else {
    $timeout_options = {}
  }

  $option_words = ($timeout_options + $module_options).map |$option, $value| { "${option}=${value}" }
  $options = $option_words.empty ? {
    true    => undef,
    default => $option_words.join(' '),
  }

  class { 'ipmi::watchdog::kmod':
    manage  => $load_module,
    options => $options,
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
    # systemd owns /dev/watchdog and Puppet loads the module. IPMI_WATCHDOG=yes
    # would make the OpenIPMI service also load and unload ipmi_watchdog itself
    # (per upstream ipmi.init), so force it to "no" if the config file exists.
    # The file is not created, and the rest of ipmi::watchdog::openipmi is
    # deliberately not declared.
    class { 'ipmi::watchdog::openipmi::watchdog_param':
      enable         => false,
      only_if_exists => true,
    }

    contain ipmi::watchdog::openipmi::watchdog_param
  } else {
    # OpenIPMI is the owner: IPMI_WATCHDOG=yes makes its service load the
    # module, with IPMI_WATCHDOG_OPTIONS.
    class { 'ipmi::watchdog::openipmi':
      enable  => $ipmi::watchdog,
      options => $options,
    }

    contain ipmi::watchdog::openipmi

    Class['ipmi::watchdog::openipmi'] ~> Class['ipmi::service::ipmi']
  }
}
