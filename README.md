# IPMI Puppet Module

[![CI](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/ci.yml/badge.svg)](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/ci.yml)
[![markdownlint](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/markdownlint.yaml/badge.svg)](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/markdownlint.yaml)
[![shellcheck](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/shellcheck.yaml/badge.svg)](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/shellcheck.yaml)
[![yamllint](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/yamllint.yaml/badge.svg)](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/yamllint.yaml)
[![Puppet Forge](https://img.shields.io/puppetforge/v/jhoblitt/ipmi.svg)](https://forge.puppet.com/jhoblitt/ipmi)
[![Apache-2 License](https://img.shields.io/github/license/jhoblitt/puppet-ipmi.svg)](LICENSE)

---

## Table of Contents

1. [Overview](#overview)
1. [What this module manages](#what-this-module-manages)
1. [Getting started](#getting-started)
   1. [Install the module](#install-the-module)
   1. [Bootstrap a host with a BMC](#bootstrap-a-host-with-a-bmc)
   1. [Configure a BMC account and network](#configure-a-bmc-account-and-network)
   1. [The equivalent in Hiera](#the-equivalent-in-hiera)
1. [The `ipmi` class: tuning what is managed](#the-ipmi-class-tuning-what-is-managed)
1. [The resource types](#the-resource-types)
   1. [Which resource to use](#which-resource-to-use)
   1. [Channels and user slots](#channels-and-user-slots)
   1. [`ipmi_user` -- manage a BMC account](#ipmi_user----manage-a-bmc-account)
   1. [`ipmi_network` -- manage BMC IPv4 settings](#ipmi_network----manage-bmc-ipv4-settings)
   1. [`ipmi_snmp` -- manage the BMC SNMP community](#ipmi_snmp----manage-the-bmc-snmp-community)
1. [The IPMI hardware watchdog](#the-ipmi-hardware-watchdog)
   1. [Choose a supervisor](#choose-a-supervisor)
   1. [Watchdog files and changes](#watchdog-files-and-changes)
1. [Facts and troubleshooting](#facts-and-troubleshooting)
1. [Providers and credentials](#providers-and-credentials)
1. [Common misconceptions and pitfalls](#common-misconceptions-and-pitfalls)
1. [Limitations and deprecations](#limitations-and-deprecations)
1. [Migrating from the wrapper defines](#migrating-from-the-wrapper-defines)
1. [Development](#development)
1. [Support and authors](#support-and-authors)

---

## Overview

This module configures a server's **own baseboard management controller (BMC)**
from the operating system running on that server. A BMC is the independent
controller that provides hardware management even when the host OS is
unavailable.

The module installs [OpenIPMI](https://openipmi.sourceforge.io/) and
[ipmitool](https://github.com/ipmitool/ipmitool), manages local IPMI services,
and provides Puppet resources for BMC accounts, IPv4 network settings, and the
SNMP community. It also supports the IPMI hardware watchdog and supplies
inventory facts compatible with [The Foreman](https://www.theforeman.org/).

Management is **in-band**: tools access the BMC through the host's local IPMI
device, normally `/dev/ipmi0`. The module does **not** connect to remote BMC
addresses or require a BMC login to make local changes. The Puppet agent needs
permission to access that device and manage packages and services, normally by
running as `root`.

Use this README for setup, examples, and operational behaviour. See
[REFERENCE.md](REFERENCE.md) for the full API and
[metadata.json](metadata.json) for dependencies and supported platforms.

---

## What this module manages

Depending on how you configure it, the module can manage these things:

| Element | Default location / name | Puppet representation | Managed by default? |
| --- | --- | --- | --- |
| OpenIPMI and ipmitool packages | `openipmi`, `ipmitool` (Debian) or `OpenIPMI`, `ipmitool` (RedHat) | `ipmi` class (private `ipmi::install`) | Yes |
| OpenIPMI service | `openipmi` (Debian) or `ipmi` (RedHat) | `ipmi` class (private `ipmi::service`) | Yes |
| `ipmievd` event daemon | `ipmievd` | `ipmi` class | Yes (stopped/disabled) |
| BMC accounts | BMC user slots | `ipmi_user` / `ipmi::users` | Only when you declare them |
| BMC IPv4 address source, address, netmask, gateway | BMC LAN channel | `ipmi_network` / `ipmi::networks` | Only when you declare them |
| BMC SNMP community | BMC LAN channel | `ipmi_snmp` / `ipmi::snmps` | Only when you declare them |
| IPMI hardware watchdog | `/dev/watchdog` | `ipmi::watchdog*` | Disabled and cleaned up |
| Hardware and network facts | `ipmi`, `ipmi_*`, `ipmitool`, `ipmi_systemd_version` | Custom facts | Collected when prerequisites are met |

Declaring `include ipmi` does **not** create BMC users or change the BMC
address or SNMP community. Declared BMC settings are enforced on subsequent
runs; removing a declaration stops managing that setting rather than restoring
its previous value. Unlisted accounts are retained. To retire an account,
declare it with `ensure => absent`.

**Watchdog ownership is different:** even with `watchdog => false`, the class
removes its three `50-ipmi-watchdog.conf` files and manages the OpenIPMI
`IPMI_WATCHDOG` switch. See
[Watchdog files and changes](#watchdog-files-and-changes) before combining
this class with another watchdog configuration.

---

## Getting started

### Install the module

Deploy the desired revision and its dependencies using your usual Puppet
tooling. To install a published release from the Forge:

```sh
puppet module install jhoblitt-ipmi
```

These examples describe the current source. The published 8.x releases
use the older wrapper defines; use the README for the installed release or
follow [Migrating from the wrapper defines](#migrating-from-the-wrapper-defines)
when deploying this source.

The smallest useful configuration is:

```puppet
include ipmi
```

This installs the packages, manages the services, and applies the default
watchdog configuration. The OpenIPMI service loads the drivers used for local
BMC access; it is **not** a remote IPMI server.

### Bootstrap a host with a BMC

The default service state depends on facts collected **before** catalog
application. `ipmitool.mc_info.IPMI_Puppet_Service_Recommend` is `running` only
when `ipmitool mc info` reports `Device Available: yes`. Without the tool or
working drivers, it recommends `stopped`.

On a host known to have a BMC, explicitly start the service:

```puppet
class { 'ipmi':
  # Bootstrap local access before BMC discovery facts are available.
  service_ensure => 'running',
}
```

Do not assume that installing the packages guarantees discovery on the next
run: the drivers must also become available. The module does **not** skip
declared BMC resources when no BMC is detected. Classify those resources only
onto hosts with usable local IPMI access.

### Configure a BMC account and network

This example is for a host whose BMC LAN channel is 1. Replace the example
credentials and addresses with your site values.

```puppet
class { 'ipmi':
  service_ensure => 'running',
}

# With user_id omitted, reuse this username's slot or allocate a free one.
ipmi_user { 'opsadmin':
  password => Sensitive('replace-me'), # Replace with your site's secret lookup.
  priv     => 4,                       # ADMINISTRATOR
  channel  => 1,                       # BMC LAN channel; verify on your hardware.
  require  => Class['ipmi'],           # Wait for packages and service setup.
}

ipmi_network { '1': # A numeric title selects the BMC LAN channel.
  type    => 'static',
  ip      => '192.0.2.10',
  netmask => '255.255.255.0',
  gateway => '192.0.2.1',
  require => Class['ipmi'],
}

ipmi_snmp { '1': # Configure the community on the same channel.
  community => Sensitive('site-community'), # hiera-eyaml is helpful here
  require   => Class['ipmi'],
}
```

The account uses an existing slot with that username or a free slot. The
network and SNMP titles select channel 1. `require => Class['ipmi']` orders
these directly declared resources after package, watchdog, and service setup;
native resources do not add that dependency themselves.

### The equivalent in Hiera

You do not have to touch a manifest. The class parameters `users`, `networks`,
and `snmps` accept hashes whose keys are resource titles and whose values are
native resource attributes.

```yaml
lookup_options:
  ipmi::users:
    merge: hash
  ipmi::networks:
    merge: hash
  ipmi::snmps:
    merge: hash

ipmi::service_ensure: running

ipmi::users:
  opsadmin:
    # Example only: store the real password encrypted with hiera-eyaml.
    password: 'replace-me'
    priv: 4
    channel: 1

ipmi::networks:
  '1':
    type: static
    ip: '192.0.2.10'
    netmask: '255.255.255.0'
    gateway: '192.0.2.1'

ipmi::snmps:
  '1':
    # Encrypt the real community with hiera-eyaml too.
    community: 'site-community'
```

Use [hiera-eyaml](https://github.com/voxpupuli/hiera-eyaml) or your site's
secret lookup mechanism for the credentials; the strings above are
placeholders. With an eyaml-enabled Hiera hierarchy, replace them with
encrypted `ENC[PKCS7,...]` values generated by `eyaml encrypt`. Hiera decrypts
these before passing them to the module's sensitive properties.

Hiera supplies parameters but does not declare the class. In your profile,
include it and add service ordering for the hash-created resources:

```puppet
include ipmi

# Hash-created resources get package ordering; add service ordering here.
# This requires service_manage => true.
Service[$ipmi::service_name] -> Ipmi_user <| |>
Service[$ipmi::service_name] -> Ipmi_network <| |>
Service[$ipmi::service_name] -> Ipmi_snmp <| |>
```

The class itself orders hash-created resources after **installation only**.
The relationships above additionally wait for the OpenIPMI service and require
`service_manage => true`. With an externally managed service or driver setup,
use that setup's resource as the dependency instead. Do not add
`require => Class['ipmi']` inside these hashes: their resources are contained
by that class, so this would introduce a dependency cycle.

---

## The `ipmi` class: tuning what is managed

`class ipmi (...)` is the only *public* class. Pulling it in installs packages,
configures the watchdog, and manages the services. The private classes
`ipmi::install`, `ipmi::service*`, and `ipmi::watchdog*` are implementation
details and should not be declared directly.

The most commonly used parameters are:

| Parameter | Default | Purpose |
| --- | --- | --- |
| `packages` | OS-specific list below | Packages to ensure installed. An override replaces the list. |
| `config_file` | OS-specific path below | OpenIPMI service configuration edited with Augeas. |
| `service_name` | OS-specific name below | OpenIPMI service resource name. |
| `service_manage` | `true` | Declare the OpenIPMI service resource. |
| `service_ensure` | From the `ipmitool` fact | `running` enables boot startup; `stopped` disables it. An empty fact-derived value also means stopped/disabled. |
| `ipmievd_service_name` | `ipmievd` | Event daemon service name. |
| `ipmievd_service_ensure` | `stopped` | `running` also enables boot startup. |
| `users`, `networks`, `snmps` | `undef` | Hashes of native resources. |
| `default_channel` | `undef` | Override the default channel for hash-created resources. |
| `watchdog` | `false` | Configure the selected watchdog supervisor. |
| `watchdog_supervisor` | `auto` | `auto`, `systemd` or `openipmi`. |
| `watchdog_timeout` | `0` | Seconds; zero omits the timeout setting. |

OS defaults from `data/os/`:

| OS family | Packages | OpenIPMI service | Configuration file |
| --- | --- | --- | --- |
| RedHat | `OpenIPMI`, `ipmitool` | `ipmi` | `/etc/sysconfig/ipmi` |
| Debian | `openipmi`, `ipmitool` | `openipmi` | `/etc/default/openipmi` |

To leave the OpenIPMI service to other tooling:

```puppet
class { 'ipmi':
  service_manage => false,
}
```

This flag affects only that service. Packages, `ipmievd`, watchdog
configuration, and any declared BMC resources are still managed. There is no
separate flag to leave `ipmievd` unmanaged, and service boot enablement is tied
to the requested `running`/`stopped` state.

To start the event daemon, set `ipmievd_service_ensure => 'running'`.
Package changes do not trigger service restarts.

---

## The resource types

The module exposes three native types, each with an `ipmitool` provider and an
alternative `freeipmi` provider. These are resources such as `ipmi_user`, not
defined types such as the former `ipmi::user`.

### Which resource to use

Use this table to pick the right resource.

| What you want to manage... | Use... |
| --- | --- |
| A BMC user account | `ipmi_user` |
| BMC IPv4 address source, address, netmask, gateway | `ipmi_network` |
| BMC SNMP community string | `ipmi_snmp` |

### Channels and user slots

Every BMC resource targets a LAN channel and, for users, a user slot.
Understanding this before declaring resources will save you time. The channel
and slot rules are described here; each resource section below assumes you have
read them.

#### Choosing a channel

A BMC has numbered channels. The LAN channel carrying its management network is
often 1, but this is hardware-dependent. The module accepts channel numbers
1-15; the BMC and selected tool must support the number you choose. Fact
discovery probes channels 1-11.

For resources created from class hashes (`ipmi::users`, `ipmi::networks`,
`ipmi::snmps`), selection follows this order:

1. An explicit `channel` for a user, or `lan_channel` for network/SNMP.
1. `ipmi::default_channel`, when set.
1. A numeric resource title for network/SNMP.
1. The node's `ipmi.default.channel` fact, if it is an integer from 1 to 15.
1. Channel 1.

Directly declared native resources use an explicit channel, a numeric
network/SNMP title, or channel 1. They do not consult facts or
`ipmi::default_channel`.

For clarity on multi-channel hardware, set channels explicitly. In particular,
`ipmi::default_channel` overrides numeric titles in class hashes. Only one
network resource and one SNMP resource may target a given channel; duplicate
targets fail the pre-run check.

#### Understanding user slots

BMC accounts occupy a fixed table of numbered slots. **The username, password
and enabled state are BMC-wide; privilege and access are per-channel.** A user
declared on two channels is one account, not two independent logins.

`user_id => 'auto'` is the default. Explicit slot assignments are reserved
first, existing usernames keep an available matching slot, and new names take
the lowest free slots in resource-title order. A free slot has an empty or
`DISABLED_*` name, is not reported enabled, and has no privilege on any channel
read. Slot 1 is the anonymous slot and is never allocated. This allocation is
independent of resource evaluation order, but can yield different IDs on hosts
with different existing user tables.

An explicit `user_id` **takes over that slot**, including an account with a
different name. The provider revokes the old account's access and disables it
before renaming. Slot 2 is vendor-reserved for `ADMIN` on Supermicro, `admin` on
ASUS and `OPERATOR` on HP Enterprise (HPE). The module does not implement a
vendor-specific slot reservation policy. Check existing slot assignments before
pinning IDs.

### `ipmi_user` -- manage a BMC account

Channel selection and slot allocation follow the rules in
[Channels and user slots](#channels-and-user-slots).

| Attribute | Default | Meaning |
| --- | --- | --- |
| `username` | Resource title | Non-empty login name, at most 16 bytes, without whitespace or a leading `-`. |
| `password` | Unset | Required for an enabled, present account; string or `Sensitive[String]`, at most 20 bytes. |
| `priv` | `4` | `1` CALLBACK, `2` USER, `3` OPERATOR, `4` ADMINISTRATOR. |
| `enable` | `true` | Whether the account is enabled. |
| `user_id` | `auto` | Slot 2-63, or automatic allocation. Actual capacity depends on the BMC. |
| `channel` | `1` when declared directly | Channel whose access is configured. |
| `purge_duplicates` | `false` | Retire other slots holding this username. |
| `ensure` | `present` | `present` or `absent`. |

Give one account different privileges on two channels:

```puppet
# The resource title is a label; username identifies the BMC account.
ipmi_user { 'operator-channel-1':
  username => 'operator',
  password => Sensitive('replace-me'), # hiera-eyaml is helpful here
  priv     => 3, # OPERATOR
  channel  => 1,
  require  => Class['ipmi'],
}

# Same account and password, with different privilege on channel 2.
ipmi_user { 'operator-channel-2':
  username => 'operator',
  password => Sensitive('replace-me'), # hiera-eyaml is helpful here
  priv     => 2, # USER
  channel  => 2,
  require  => Class['ipmi'],
}
```

Resources sharing a username must agree on password, enabled state, and any
explicit slot assignment. Only privilege may differ by channel. Declaring the
same username twice on one channel is rejected.

Enabling an account grants IPMI channel access and Serial over LAN (SOL)
payload access on its channel. These access flags have no independent resource
parameters. Disabling revokes access across discovered LAN channels and
channels named by user resources:

```puppet
# Keep the named account, but disable it across channels.
ipmi_user { 'retired_operator':
  enable  => false,
  require => Class['ipmi'],
}

# Retire a specific named slot and make it available for reuse.
ipmi_user { 'oldadmin':
  ensure  => absent,
  user_id => 5, # Only retire slot 5 if it belongs to oldadmin.
  require => Class['ipmi'],
}
```

`enable => false` also creates/reserves a named disabled slot if the account is
missing. `ensure => absent` only removes a matching username (and matching ID,
when specified). Since IPMI cannot delete slots, removal revokes access,
disables the account, and renames it `DISABLED_<id>`.

When moving a username to another slot, set `purge_duplicates => true` to
retire its old slots. Otherwise they can remain enabled. This purges only
duplicates of that username, not all unmanaged users. Each duplicate is a
generated `ensure => absent` resource, ordered before the target account and
visible in `--noop`. Discovery happens before resources are applied; if the
tool or BMC is unavailable then, duplicate cleanup is deferred.

Some BMCs refuse privilege changes on disabled users. A user reported as
disabled can therefore be treated as converged even with stored privilege
bits. Renaming/removal has stricter checks and can fail if access cannot be
confirmed revoked. See [REFERENCE.md](REFERENCE.md#ipmi_user) for the complete
account and allocation rules.

### `ipmi_network` -- manage BMC IPv4 settings

Channel selection follows the rules in
[Channels and user slots](#channels-and-user-slots).

`ipmi_network` manages four properties independently:

| Attribute | Default | Meaning |
| --- | --- | --- |
| `lan_channel` | Numeric title, otherwise `1` | BMC LAN channel. |
| `type` | Unmanaged | `static` or `dhcp`. |
| `ip` | Unmanaged | IPv4 address. Required with `type => 'static'`. |
| `netmask` | Unmanaged | Dotted-decimal IPv4 mask. Required with `type => 'static'`. |
| `gateway` | Unmanaged | IPv4 default gateway. |

To use DHCP:

```puppet
ipmi_network { '1':
  type    => 'dhcp', # Omit ip, netmask and gateway when selecting DHCP.
  require => Class['ipmi'],
}
```

`dhcp` rejects `ip`, `netmask` and `gateway` in the same resource. For a static
address, use the complete example in [Getting started](#getting-started). An
omitted gateway retains the BMC's current gateway; it does not clear it.

Leaving `type` unset leaves the address source unchanged, while any explicit
address properties are still managed. An empty resource manages nothing. There
is no `ensure => absent` for network settings.

Writes affect the BMC management interface, not the host OS interface, and may
interrupt existing remote BMC sessions. The provider rechecks declared address
settings after switching to static, because some BMCs restore a stored
configuration during that switch.

### `ipmi_snmp` -- manage the BMC SNMP community

Channel selection follows the rules in
[Channels and user slots](#channels-and-user-slots).

```puppet
# Always set community explicitly; omitting it writes 'public'.
ipmi_snmp { '1':
  community => Sensitive('site-community'), # hiera-eyaml can protect this further
  require   => Class['ipmi'],
}
```

`lan_channel` follows the same title/default rules as `ipmi_network`.
**Omitting `community` actively sets it to `public`.** The value must be
non-empty, at most 18 bytes, and have no leading or trailing whitespace. It is
redacted in Puppet reports whether supplied as a string or as `Sensitive`.

This resource only manages the community string. It does not configure SNMPv3,
enable an OS SNMP service, or set BMC alert destinations and event filters.
There is no `ensure => absent`; remove the declaration to stop enforcing the
community.

---

## The IPMI hardware watchdog

The BMC watchdog can reset or power-cycle a host when its supervising process
stops sending keepalives. Loading `ipmi_watchdog` normally only creates
`/dev/watchdog`; **it does not arm the timer**. The timer starts when a process
opens the device, or when `start_now=1` is passed to the driver. Exactly one
process can own the device.

### Choose a supervisor

| `watchdog_supervisor` | Module loading | Who sends keepalives? |
| --- | --- | --- |
| `systemd` | Puppet loads the driver now and through `modules-load.d` at boot. | PID 1, when effective `RuntimeWatchdogSec` is non-zero. |
| `openipmi` | The OpenIPMI service loads the driver using `IPMI_WATCHDOG=yes`. | An externally configured process; this module supplies none. |
| `auto` | Selects `systemd` when `ipmi_systemd_version` is available and is not 250 or 251; otherwise `openipmi`. | As above. |

On a systemd host with a working IPMI device, a complete configuration is:

```puppet
class { 'ipmi':
  service_ensure          => 'running',
  watchdog                => true,
  watchdog_supervisor     => 'systemd', # PID 1 opens the device and sends keepalives.
  watchdog_timeout        => 60,        # Seconds: driver timeout and RuntimeWatchdogSec.
  watchdog_module_options => { 'action' => 'power_cycle' },
}
```

This sets the module timeout and systemd's `RuntimeWatchdogSec` to 60 seconds.
It does not install a separate watchdog daemon. Hardware watchdog setup is not
conditional on the BMC discovery fact.

| Parameter | Default | Behaviour |
| --- | --- | --- |
| `watchdog_timeout` | `0` | Non-zero writes the driver timeout and, under systemd, `RuntimeWatchdogSec`. Zero writes neither; it does not explicitly disable another timeout setting. |
| `watchdog_systemd_options` | `{}` | Additional `[Manager]` settings. An explicit `RuntimeWatchdogSec` overrides `watchdog_timeout` in the drop-in. |
| `watchdog_module_options` | `{}` | Driver options such as `action`, `pretimeout` and `start_now`. Booleans become `1`/`0`; fractional numbers are rejected. |
| `watchdog_manage_module` | `true` | Under systemd, load the driver and manage its two configuration files. Set false when other tooling supplies the device. |

With `watchdog => true` and all other defaults, systemd is not instructed to
arm the timer. Set a non-zero timeout for that purpose. Under OpenIPMI,
omitting timeout/options preserves any existing `IPMI_WATCHDOG_OPTIONS`,
including package defaults. A `timeout` in `watchdog_module_options` must agree
with a non-zero `watchdog_timeout`.

### Watchdog files and changes

The module owns these files:

| File | When present |
| --- | --- |
| `/etc/modprobe.d/50-ipmi-watchdog.conf` | Systemd supervisor, watchdog/module management enabled, and driver options supplied. |
| `/etc/modules-load.d/50-ipmi-watchdog.conf` | Systemd supervisor with watchdog/module management enabled. |
| `/etc/systemd/system.conf.d/50-ipmi-watchdog.conf` | Systemd supervisor with watchdog enabled and at least one manager setting to write. |

In other cases the files are removed. Other files in these directories are not
purged by this module. If another module purges unmanaged drop-ins, ensure it
preserves this module's file.

Under systemd, Augeas sets `IPMI_WATCHDOG=no` only if the OpenIPMI config
already exists and is non-empty. Under OpenIPMI, the switch is set to `yes` or
`no`, and supplied options are written when enabling. Other OpenIPMI
configuration keys are retained.

Changes to the systemd drop-in trigger `systemctl daemon-reexec` when systemd
is running. Under the OpenIPMI supervisor, configuration changes notify the
managed OpenIPMI service; they do not restart `ipmievd`. Driver options apply
on the next module load. Puppet does not reload an already loaded driver just
because its options changed.

#### Device selection and disabling

`ipmi_watchdog` exposes the legacy `/dev/watchdog` device rather than a
numbered `/dev/watchdogN` device. Leave `WatchdogDevice` unset for the module's
automatic selection behaviour:

* systemd through 249 opens `/dev/watchdog`.
* systemd 252 and later can fall back to it when `/dev/watchdog0` is absent.
* systemd 250 and 251 do not make that fallback, which is why `auto` selects
  OpenIPMI on those versions.

Another watchdog driver can claim `/dev/watchdog` first and prevent the IPMI
driver from registering it. Check the kernel log and PID 1's `Using hardware
watchdog 'IPMI'` message to verify which device is in use.

`watchdog => false` removes this module's watchdog files and sets the OpenIPMI
switch to `no` where applicable. It **does not unload the driver** or guarantee
that another supervisor or another systemd configuration has stopped the timer.
Removing the drop-in makes systemd re-read its remaining configuration.

To explicitly turn off systemd's runtime watchdog while continuing to load the
driver, set:

```puppet
class { 'ipmi':
  watchdog                 => true, # Continue loading the IPMI watchdog driver.
  watchdog_supervisor      => 'systemd',
  # Explicitly disable systemd's runtime timer, rather than omit its setting.
  watchdog_systemd_options => { 'RuntimeWatchdogSec' => 0 },
}
```

An active BMC timer can outlive its driver. Plan supervisor changes and driver
reloads with that behaviour in mind; removing a configuration file alone is not
a hardware watchdog shutdown operation.

---

## Facts and troubleshooting

### Available facts

| Fact | Contents and prerequisites |
| --- | --- |
| `ipmi` | Structured LAN information and user names/privileges, keyed by integer channel number. `default` repeats the first discovered channel. Requires local access through `ipmitool`; returns an empty hash when no LAN data is found. |
| `ipmi_ipaddress`, `ipmi_ipaddress_source`, `ipmi_subnet_mask`, `ipmi_gateway`, `ipmi_macaddress`, `ipmi_lan_channel` | Flat facts for Foreman BMC discovery. Use the structured fact for multi-channel hardware. |
| `ipmitool.mc_info` | Parsed `ipmitool mc info`, plus `IPMI_Puppet_Service_Recommend`. Confined to non-virtual Linux hosts. |
| `ipmitool.fru` | Parsed `ipmitool fru print 0`; field names are lowercase with underscores. Same confinement as `mc_info`. |
| `ipmi_systemd_version` | Systemd major version as a string, when `/run/systemd/system` exists and `systemctl --version` succeeds. Does not require ipmitool. |

For example, a manifest can read the selected channel from
`$facts['ipmi']['default']['channel']`, or channel 1's address from
`$facts['ipmi'][1]['ipaddress']`. Guard against missing data when using these
facts in your own code. Facts are a snapshot from before catalog application,
so BMC changes appear in a later collection.

Facts use `ipmitool` even when resources use FreeIPMI. Loading the custom facts
can query the BMC even if the `ipmi` class is not declared. Foreman credentials
are configured separately; these facts do not contain BMC passwords.

### Inspect local access

Run these on the managed host with the same privileges as the Puppet agent,
using its Puppet/Facter executables and synced custom facts:

```sh
facter -p ipmi ipmitool ipmi_systemd_version
ipmitool mc info
ipmitool channel info 1
ipmitool lan print 1
ipmitool user list 1
ipmitool channel getaccess 1
puppet resource ipmi_user
```

Use the appropriate channel instead of 1. `lan print` includes the current SNMP
community, so redact it when sharing diagnostic output. `puppet resource
ipmi_user` enumerates named, non-free slots with channel 1 privileges; network
and SNMP providers do not implement enumeration.

| Symptom | What to check |
| --- | --- |
| OpenIPMI remains stopped after installation | Fact-driven bootstrap: explicitly set `service_ensure => 'running'` on known BMC hosts and verify local access. |
| BMC resources run before drivers are ready | Direct resources need a dependency; class hashes only receive package ordering. See [Getting started](#getting-started). |
| Settings land on the wrong channel | Direct resource defaults differ from class defaults; inspect `channel`/`lan_channel` and `default_channel`. |
| No free user slot | Inspect the whole BMC user table. Disabled named accounts remain reserved, and privilege on another channel prevents reuse. |
| User reads fail during channel discovery | User management needs a complete view of LAN access. Unexpected probe failures fail the operation rather than silently omitting a channel. |
| Password changes repeat | The provider tests the desired password rather than reading it back. A failed check is treated as out of sync; check tool/BMC support and any reported errors. |
| Watchdog driver is loaded but no timer is running | Check the effective `RuntimeWatchdogSec` or the external keepalive process. Loading alone does not arm it. |

`puppet agent --test --noop` can show proposed changes once prerequisites are
installed. It still queries the BMC and tests passwords; it cannot prove that
firmware will accept writes or that remote access will work after a network
change.

---

## Providers and credentials

`ipmitool` is the default Linux provider. The alternative `freeipmi` providers
are experimental and use `bmc-config` for users/network and `ipmi-pef-config`
for SNMP. Install the appropriate distribution package and select
`provider => 'freeipmi'` on each resource that should use it. For example, on a
RedHat-family host:

```puppet
class { 'ipmi':
  # Replaces the package list; retain OpenIPMI and ipmitool for services/facts.
  packages       => ['OpenIPMI', 'ipmitool', 'freeipmi'],
  service_ensure => 'running',
}

ipmi_user { 'operator':
  password => Sensitive('replace-me'), # hiera-eyaml can protect this further
  priv     => 3, # OPERATOR
  channel  => 1,
  provider => 'freeipmi', # Select the backend per resource.
  require  => Class['ipmi'],
}
```

On Debian-family systems, FreeIPMI tools are packaged as `freeipmi-tools`.
Overriding `packages` replaces the list, so retain the packages needed for
services and facts.

Passwords and communities are sensitive Puppet properties. Providers pass them
through mode `0600` temporary files, removed after use, rather than putting them
in command-line arguments. Secret-bearing error output is scrubbed. `Sensitive()`
provides redaction, not encryption at rest; use hiera-eyaml to encrypt
credentials stored in Hiera, or your site's secret storage.

Tool input formats impose additional limits beyond IPMI's byte limits:

* All passwords reject newlines and NUL bytes. Passwords of 17-20 bytes require
  the BMC's IPMI 2.0 20-byte password support.
* With ipmitool, 17-20 byte passwords and SNMP communities reject `#`,
  whitespace other than spaces, NUL bytes, both quote characters in the same
  value, and `~` together with a space or quote. Communities also cannot start
  with `help`.
* FreeIPMI passwords and communities reject all whitespace and NUL bytes.

Limits are in **bytes**, not characters. See the
[password](REFERENCE.md#ipmi_user) and
[community](REFERENCE.md#ipmi_snmp) reference sections for details.

---

## Common misconceptions and pitfalls

* **`include ipmi` does not create users or change network settings.** It only
  installs packages and services. BMC accounts, networks, and SNMP communities
  must be declared separately.

* **The OpenIPMI service is not a remote IPMI server.** It loads kernel drivers
  so local tools can talk to the BMC through `/dev/ipmi0`.

* **Default service state is fact-driven.** On the first run after package
  installation, the discovery fact may recommend `stopped` until drivers are
  loaded. Set `service_ensure => 'running'` on hosts known to have a BMC.

* **Direct native resources need explicit dependencies.** `ipmi_user`,
  `ipmi_network`, and `ipmi_snmp` do not automatically depend on the OpenIPMI
  service. Use `require => Class['ipmi']` or order against
  `Service[$ipmi::service_name]`.

* **Class hashes only get package ordering.** If you want hash-created BMC
  resources to wait for the service to start, add the explicit service
  relationships shown in [The equivalent in Hiera](#the-equivalent-in-hiera).

* **`default_channel` only affects class hashes.** Directly declared resources
  do not consult `ipmi::default_channel` or the `ipmi.default.channel` fact.

* **Omitting `community` on `ipmi_snmp` writes `public`.** This is intentional
  but surprising; always set the community explicitly.

* **Loading the watchdog driver does not arm the timer.** Something must open
  `/dev/watchdog` (or `start_now=1` must be passed). Under systemd this means
  setting a non-zero `watchdog_timeout` or `RuntimeWatchdogSec`.

* **The module never unloads the watchdog driver.** Disabling the watchdog
  removes configuration files, but a loaded module stays loaded until reboot or
  a manual unload. A running BMC timer can outlive its driver.

* **`ensure => absent` on a user does not restore the previous account.** It
  disables and renames the slot to `DISABLED_<id>`. IPMI cannot delete slots.

* **Removing a resource declaration stops enforcement; it does not revert the
  BMC.** If you set a network address through Puppet and then remove the
  declaration, the address stays set.

---

## Limitations and deprecations

* **Platform support:** `metadata.json` declares Puppet 8
  (`>= 8.0.0 < 9.0.0`), RedHat/AlmaLinux/Rocky 8-10, Debian 11 and Ubuntu
  20.04. OS defaults do not establish support for every firmware implementation.

* **Local BMC only:** no remote-host, `lanplus`, Redfish, or Puppet device
  transport configuration is provided.

* **Limited network and alert scope:** no IPv6, VLAN, cipher-suite,
  authentication-type, PEF rule, or alert-destination management. Address
  validation checks IPv4 syntax, not reachability or subnet correctness.

* **Limited hardware scope:** no firmware updates, power/boot orchestration,
  sensor policy, or SEL clearing. User enable/disable operations include SOL
  payload access, but general SOL configuration is not exposed.

* **Firmware-dependent operations:** BMCs differ in slot capacity, reserved
  accounts, password support, and access commands. A successful catalog
  compilation does not establish hardware compatibility.

* **Incremental changes:** BMC writes are separate commands, not an atomic
  transaction with rollback. If enabling or revoking access fails, the providers
  attempt to disable the account, but that command can also fail; inspect
  reported errors and the resulting BMC state.

* **Ownership:** changing managed settings through a BMC web UI or another tool
  creates drift that Puppet can reverse. Omitting a resource stops management
  rather than undoing its last change.

* **Test coverage:** acceptance tests run without a BMC and check package
  installation/provider execution. Unit tests exercise recorded output and
  simulated BMC behaviour; hardware operation and watchdog recovery need
  validation on your systems.

* The private `ipmi::install`, `ipmi::service*`, and `ipmi::watchdog*` classes
  are not public API. Declare the `ipmi` class and use its parameters instead.

* The `ipmi::user`, `ipmi::network`, and `ipmi::snmp` defined types from the
  8.x releases are replaced by the native `ipmi_user`, `ipmi_network`, and
  `ipmi_snmp` types. See [Migrating from the wrapper defines](#migrating-from-the-wrapper-defines).

* Per-channel flat facts such as `ipmi1_ipaddress` are removed. Use the
  structured `ipmi` fact; the channel-agnostic `ipmi_*` facts remain.

* See [CHANGELOG.md](CHANGELOG.md) for the full list of changes per release.

---

## Migrating from the wrapper defines

The current source uses native types in place of the exec-based `ipmi::user`,
`ipmi::network`, and `ipmi::snmp` defines shipped in the 8.x releases.
When moving from those releases, update manifests and class-hash entries
together:

| Previous interface | Current interface | Behaviour to review |
| --- | --- | --- |
| `ipmi::user` | `ipmi_user` | A native resource; remove relationships to old internal `Exec` resources. |
| `user` (default `root`) | `username` (default title) | Set the username explicitly if the title was only a label. |
| `user_id` default `3` | `user_id` default `auto` | Set `3` explicitly to retain a pinned slot. |
| `purge_id_mismatch` | `purge_duplicates` | Also applies to disabled users; cleanup is represented as Puppet resources. |
| `ipmi::network` | `ipmi_network` | `type`, `ip`, `netmask` and `gateway` have no defaults. |
| `type` default `dhcp` | Explicit `type => 'dhcp'` | Remove static fields when selecting DHCP; static requires both address and mask. |
| `ipmi::snmp`, parameter `snmp` | `ipmi_snmp`, parameter `community` | Omission still sets `public`. |

Also review these changes:

* Direct native resources need explicit dependencies and no longer derive
  channels from facts. Class hashes use the precedence documented above.
* Conflicting account/slot assignments and duplicate network/SNMP channel
  targets are rejected. Disabled users are BMC-wide, not channel-local.
* Per-channel flat facts such as `ipmi1_ipaddress` are removed. Use the
  structured `ipmi` fact; the channel-agnostic `ipmi_*` facts remain.
* Watchdog `auto` can select systemd, which loads the module directly and sets
  `IPMI_WATCHDOG=no`. Existing `IPMI_WATCHDOG_OPTIONS` then no longer configure
  that load. Set timeout/options explicitly, or choose
  `watchdog_supervisor => 'openipmi'` to retain the service-based path.
* The private `ipmi::config` class has been replaced by `ipmi::watchdog`.
* `/usr/libexec/puppet_ipmi_purge_id_mismatch`, installed by the old purge
  option, is no longer managed or executed. Remove it through a site file
  resource with `ensure => absent` if it remains on upgraded hosts.

For older migrations, 8.0.0 replaced `ipmitool_mc_info` with
`ipmitool.mc_info`, and 7.0.0 dropped Puppet 7 support. See
[CHANGELOG.md](CHANGELOG.md) for release history.

---

## Development

Development uses the Vox Pupuli test tooling in `Gemfile` and `Rakefile`.
After installing the development dependencies with Bundler:

```sh
bundle exec rake lint
bundle exec rake rubocop
bundle exec rake spec
mdl README.md
```

Specs cover class catalogs, custom facts, native types, providers, and
multi-step user/network operations. Add tests for behavioural changes.
Beaker acceptance tests are in `spec/acceptance` and use
`voxpupuli-acceptance` from the `system_tests` bundle group. GitHub Actions
runs the module CI and separate Markdown, shell and YAML checks.

Regenerate the API reference after changing public documentation:

```sh
bundle exec rake strings:generate:reference
```

Update this README for user-visible behaviour and examples. Consult
[REFERENCE.md](REFERENCE.md) for details that do not belong in the usage guide.

---

## Support and authors

For issues, feature requests, and documentation, see the project's home pages:

* GitHub: [https://github.com/jhoblitt/puppet-ipmi](https://github.com/jhoblitt/puppet-ipmi)
* Puppet Forge: [https://forge.puppet.com/jhoblitt/ipmi](https://forge.puppet.com/jhoblitt/ipmi)

Authored by Joshua Hoblitt <josh@hoblitt.com> and contributors.
Licensed under Apache-2.0; see [LICENSE](LICENSE).
