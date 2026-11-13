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

  if $timeout > 0 {
    $option_timeout = $module_options['timeout']
    $timeouts_agree = $option_timeout ? {
      undef                            => true,
      Numeric                          => $option_timeout == $timeout,
      Pattern[/\A[0-9]+(\.[0-9]+)?\z/] => Numeric($option_timeout) == $timeout,
      default                          => false,
    }

    if $options_used and !$timeouts_agree {
      fail("ipmi::watchdog_module_options timeout (${option_timeout}) conflicts with ipmi::watchdog_timeout (${timeout}); set only one")
    }

    $module_settings = { 'timeout' => $timeout } + ($module_options - 'timeout')
  } else {
    $module_settings = $module_options
  }

  # ipmi_watchdog's integer parameters (start_now, timeout, pretimeout) reject
  # "true" and "60.0", and 1/0 is also what its bool parameters accept.
  $option_words = $module_settings.map |$option, $value| {
    case $value {
      Boolean: {
        $written = if $value { 1 } else { 0 }
      }
      Float: {
        unless $value.floor == $value {
          fail("ipmi::watchdog_module_options ${option} (${value}) must be a whole number")
        }
        $written = $value.floor
      }
      default: {
        $written = $value
      }
    }
    "${option}=${written}"
  }
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
    timeout => $timeout,
    options => $ipmi::watchdog_systemd_options,
  }

  contain ipmi::watchdog::systemd

  Class['ipmi::watchdog::kmod'] -> Class['ipmi::watchdog::systemd']

  # When systemd owns /dev/watchdog, Puppet loads the module. IPMI_WATCHDOG=yes
  # would have the OpenIPMI service load it as well, with its own
  # IPMI_WATCHDOG_OPTIONS, so it is forced to "no" if the config file exists;
  # the file is not created.
  class { 'ipmi::watchdog::openipmi':
    enable         => !$use_systemd and $ipmi::watchdog,
    only_if_exists => $use_systemd,
    options        => $options,
  }

  contain ipmi::watchdog::openipmi

  unless $use_systemd {
    # The ipmi service loads the module, with IPMI_WATCHDOG_OPTIONS.
    Class['ipmi::watchdog::openipmi'] ~> Class['ipmi::service::ipmi']
  }
}
