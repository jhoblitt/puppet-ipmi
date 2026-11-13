#
# @summary Manages OpenIPMI
#
# @param packages
#   List of packages to install.
# @param config_file
#   Absolute path to the ipmi service config file.
# @param service_name
#   Name of IPMI service.
# @param service_ensure
#   Controls the state of the `ipmi` service. Possible values: `running`, `stopped`
# @param ipmievd_service_name
#   Name of ipmievd service.
# @param ipmievd_service_ensure
#   Controls the state of the `ipmievd` service. Possible values: `running`, `stopped`
# @param watchdog
#   Controls whether the IPMI watchdog is enabled. When `true`, the owner
#   chosen by `watchdog_supervisor` is configured: under `openipmi`
#   `IPMI_WATCHDOG` is set to `yes`, so the OpenIPMI service loads the
#   `ipmi_watchdog` kernel module; under `systemd` Puppet loads the module (see
#   `watchdog_manage_module`) and a system.conf drop-in is written. When
#   `false`, `IPMI_WATCHDOG` is set to `no` (`openipmi`), and the drop-in and
#   the module's modprobe.d and modules-load.d files are removed. A loaded
#   module is never unloaded: it stays loaded until the next boot or a manual
#   unload.
# @param snmps
#   `ipmi_snmp` resources to create.
# @param users
#   `ipmi_user` resources to create.
# @param networks
#   `ipmi_network` resources to create.
# @param service_manage
#   Controls whether the `ipmi` service is managed. When `false`, the
#   `service` resource is not declared and the service is left unmanaged
#   (handled by the administrator or an external tooling system).
# @param watchdog_manage_module
#   Whether Puppet loads the `ipmi_watchdog` kernel module, and writes its
#   modprobe options, when `watchdog` is `true` under `systemd`. Set `false`
#   when `/dev/watchdog` already exists, for example because the module is
#   built in or loaded by other tooling; this module's modprobe.d and
#   modules-load.d files are then removed, and `watchdog_timeout` and
#   `watchdog_module_options` have no effect on the module. Has no effect
#   under `openipmi`, where the OpenIPMI service loads the module.
# @param watchdog_supervisor
#   Which component owns `/dev/watchdog`: `systemd`, `openipmi`, or `auto`.
#   `systemd` writes a system.conf drop-in so PID 1 opens and pings the device,
#   and forces `IPMI_WATCHDOG` to `no` if its file exists. `openipmi` sets
#   `IPMI_WATCHDOG`, which only makes the OpenIPMI service load the module;
#   nothing in this module opens the device. `auto` selects `systemd` when
#   the `ipmi_systemd_version` fact is present, unless it is 250 or 251, and
#   `openipmi` otherwise. `ipmi_watchdog` creates only `/dev/watchdog`, which
#   systemd 250 and 251 replace with `/dev/watchdog0`.
# @param watchdog_timeout
#   Watchdog timeout in seconds. Passed to the `ipmi_watchdog` module as its
#   `timeout` option (in modprobe.d under `systemd`, in
#   `IPMI_WATCHDOG_OPTIONS` under `openipmi`) and, under `systemd`, written as
#   RuntimeWatchdogSec. `0`, the default, writes neither: the driver default
#   of 10 seconds applies, and systemd keeps whatever RuntimeWatchdogSec the
#   rest of its configuration sets, which is off unless something sets it.
# @param watchdog_systemd_options
#   Extra system.conf [Manager] settings, used only under `systemd`. A
#   `RuntimeWatchdogSec` here replaces `watchdog_timeout`, so setting it to `0`
#   keeps systemd off the device while `watchdog` is `true`.
# @param watchdog_module_options
#   Extra `ipmi_watchdog` module options, for example
#   `{ 'action' => 'power_cycle' }`, written with `watchdog_timeout` to
#   modprobe.d under `systemd` or to `IPMI_WATCHDOG_OPTIONS` under `openipmi`.
#   When neither is set, `IPMI_WATCHDOG_OPTIONS` keeps the value it has, such
#   as the package's `timeout=60`. A `timeout` key must not disagree with a
#   non-zero `watchdog_timeout`. Booleans are written as 1/0 and whole Floats
#   as integers; a fractional value is an error.
# @param default_channel
#   Optional default IPMI channel (1-15) to use for resources that do not
#   specify one. When unset, class-declared resources use the node's
#   ipmi.default.channel fact if valid; otherwise the class uses an integer
#   LAN title or channel 1. Directly declared native resources
#   do not use facts for their defaults.
#
class ipmi (
  Array[String] $packages,
  Stdlib::Absolutepath $config_file,
  String $service_name,
  String $ipmievd_service_name,
  Variant[Stdlib::Ensure::Service, String[0]] $service_ensure,
  Stdlib::Ensure::Service $ipmievd_service_ensure,
  Boolean $watchdog,
  Hash $snmps,
  Hash $users,
  Hash $networks,
  Boolean $service_manage,
  Boolean $watchdog_manage_module = true,
  Enum['auto', 'systemd', 'openipmi'] $watchdog_supervisor = 'auto',
  Integer[0] $watchdog_timeout = 0,
  Ipmi::Watchdog::SystemdOptions $watchdog_systemd_options = {},
  Ipmi::Watchdog::ModuleOptions $watchdog_module_options = {},
  Optional[Integer[1, 15]] $default_channel = undef,
) {
  contain ipmi::install
  contain ipmi::watchdog
  contain ipmi::service

  # Only ordering: a package change must neither re-execute PID 1 nor
  # restart the services. ipmi::watchdog notifies the ipmi service itself
  # when it changes what that service loads.
  Class['ipmi::install'] -> Class['ipmi::watchdog']
  Class['ipmi::install'] -> Class['ipmi::service']
  # IPMI_WATCHDOG must be settled before the OpenIPMI service starts, or it
  # loads ipmi_watchdog with its own IPMI_WATCHDOG_OPTIONS first.
  Class['ipmi::watchdog'] -> Class['ipmi::service']

  # The class sees the target node's facts on Puppet Server. Native type
  # defaultto blocks run on the compiler and must not read local Facter data.
  $fact_channel = $facts.dig('ipmi', 'default', 'channel')
  if $default_channel != undef {
    $effective_channel = $default_channel
  } elsif $fact_channel =~ Integer[1, 15] {
    $effective_channel = $fact_channel
  } else {
    $effective_channel = 1
  }

  $user_defaults = { 'channel' => $effective_channel }
  $lan_defaults = { 'lan_channel' => $effective_channel }

  $users.each |$key, $params| {
    $user_title = String($key)
    ipmi_user { $user_title:
      * => $user_defaults + $params,
    }
    Class['ipmi::install'] -> Ipmi_user[$user_title]
  }

  $networks.each |$key, $params| {
    $network_title = String($key)
    # An integer title is already a channel unless the caller explicitly
    # requested an override via default_channel.
    if $default_channel == undef and $network_title =~ /\A[0-9]+\z/ {
      $network_defaults = { 'lan_channel' => Integer($network_title, 10) }
    } else {
      $network_defaults = $lan_defaults
    }
    ipmi_network { $network_title:
      * => $network_defaults + $params,
    }
    Class['ipmi::install'] -> Ipmi_network[$network_title]
  }

  $snmps.each |$key, $params| {
    $snmp_title = String($key)
    if $default_channel == undef and $snmp_title =~ /\A[0-9]+\z/ {
      $snmp_defaults = { 'lan_channel' => Integer($snmp_title, 10) }
    } else {
      $snmp_defaults = $lan_defaults
    }
    ipmi_snmp { $snmp_title:
      * => $snmp_defaults + $params,
    }
    Class['ipmi::install'] -> Ipmi_snmp[$snmp_title]
  }
}
