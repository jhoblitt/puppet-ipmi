# Puppet ipmi Module

[![CI](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/ci.yml/badge.svg)](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/ci.yml)
[![markdownlint](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/markdownlint.yaml/badge.svg)](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/markdownlint.yaml)
[![shellcheck](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/shellcheck.yaml/badge.svg)](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/shellcheck.yaml)
[![yamllint](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/yamllint.yaml/badge.svg)](https://github.com/jhoblitt/puppet-ipmi/actions/workflows/yamllint.yaml)

## Table of Contents

1. [Overview](#overview)
1. [Description](#description)
1. [Usage](#usage)
  * [Examples](#examples)
  * [Classes](#classes)
1. [Additional Facts](#additional-facts)
1. [Limitations](#limitations)
1. [Versioning](#versioning)
1. [Support](#support)
1. [Contributing](#contributing)
1. [See Also](#see-also)

## Overview

Manages the OpenIPMI package

## Description

Installs the [OpemIPMI](http://openipmi.sourceforge.net/) package,
provides IPMI facts in a format compatible with
[The Foreman](https://www.theforeman.org)'s
[BMC features](https://www.theforeman.org/manuals/latest/index.html#4.3.3BMC)
and enables the `ipmi` service. The latter loads the kernel drivers
needed for communicating with the BMC from user space.

It also manages the companion `ipmievd` daemon, whose name can be
customized with the `ipmievd_service_name` parameter.

## Usage

### Reference

See [REFERENCE](REFERENCE.md)

### Examples

```puppet
  include ipmi
```

Create a user with admin privileges in any slot (default):

```puppet
  ipmi_user { 'newuser1':
    password => 'password1',
  }
```

Create a user with operator privileges:

```puppet
  ipmi_user { 'operator user: newuser2':
    username => 'newuser2',
    password => 'password2',
    priv     => 3,
    user_id  => 5,
  }
```

Create a user with user privileges on a specific channel:

```puppet
  ipmi_user { 'newuser3':
    password => 'password3',
    priv     => 2,
    user_id  => 6,
    channel  => 3,
  }
```

Create a user and remove it from any other slot (for example after moving
it to a different `user_id`):

```puppet
  ipmi_user { 'newuser1':
    password         => 'password1',
    user_id          => 4,
    purge_duplicates => true,
  }
```

Remove a user (the slot is renamed `DISABLED_<id>`, and access is revoked if
it was still enabled):

```puppet
  ipmi_user { 'olduser':
    ensure => absent,
  }
```

Configure a static ip on IPMI lan channel 1:

```puppet
  ipmi_network { 'lan1':
    type        => 'static',
    ip          => '192.168.1.10',
    netmask     => '255.255.255.0',
    gateway     => '192.168.1.1',
    lan_channel => 1,
  }
```

Configure IPMI lan channel 1 to DHCP:

```puppet
  ipmi_network { 'lan1 DHCP':
    type        => 'dhcp',
    lan_channel => 1,
  }
```

Configure IPMI snmp string on lan channel 1:

```puppet
  ipmi_snmp { 'lan1':
    community   => 'secret',
    lan_channel => 1,
  }
```

### Backend selection

`ipmitool` is the supported backend and the default on Linux. The
`freeipmi` providers are experimental. To force a specific backend, set
the provider on the resource:

```puppet
  ipmi_user { 'newuser1':
    password => 'password1',
    provider => 'freeipmi',
  }
```

NOTE: the `freeipmi` backend is **EXPERIMENTAL** and may not work in all cases!

### Classes

#### `ipmi`

```puppet
  # defaults
  class { 'ipmi':
    service_ensure         => 'running', # default is 'running'
    ipmievd_service_ensure => 'running', # default is 'stopped'
    watchdog               => true,      # default is false
    service_manage         => false,     # default is true
  }
```

When `service_manage` is set to `false`, the `ipmi` service is not managed
by the module; it is left to the administrator or an external tooling
system to start and stop. The companion `ipmievd` daemon and the rest of
the module continue to behave normally.

When `users`, `networks`, or `snmps` are passed as class parameters, the
`ipmi` class declares the corresponding native resources and injects the
`default_channel` value for any resource that does not specify a channel.
`ipmi_network` and `ipmi_snmp` reject catalogs where two resources target
the same LAN channel, preventing them from fighting on every run.

For resources declared through `ipmi::users`, `ipmi::networks`, and
`ipmi::snmps`, `ipmi::default_channel` takes precedence over the node's
`ipmi.default.channel` fact; an invalid or missing fact falls back to 1.
An integer network/SNMP resource title takes precedence over the fact.
Native resources declared directly do not consult facts during compilation:
specify `channel`/`lan_channel` explicitly when the target channel is not 1
(or use an integer title for network/SNMP).

#### The IPMI hardware watchdog

When `watchdog => true` the `ipmi_watchdog` kernel module is loaded, which
provides `/dev/watchdog`. Loading it does not start the BMC timer: the timer
runs once something opens `/dev/watchdog` and pings it, or if the module is
given the `start_now=1` option.

The device can only be opened once, so one component owns it, chosen by
`watchdog_supervisor` (`auto` by default):

* `systemd`: Puppet loads the module, now and at boot. Its options go to
  `/etc/modprobe.d/50-ipmi-watchdog.conf` and the boot-time load to
  `/etc/modules-load.d/50-ipmi-watchdog.conf`; files of other names, such as
  the `ipmi_watchdog.conf` that puppet/kmod writes, are left alone. A
  `system.conf` drop-in (`/etc/systemd/system.conf.d/50-ipmi-watchdog.conf`)
  makes PID 1 open and ping `/dev/watchdog`. systemd reads it only when PID 1
  starts, so Puppet runs `systemctl daemon-reexec` whenever the drop-in
  changes or is removed. If the OpenIPMI config file exists, `IPMI_WATCHDOG`
  in it is forced to `no` (the file is never created for this), so the
  OpenIPMI service does not also load the module with its own options.
* `openipmi`: `IPMI_WATCHDOG=yes` is set in the OpenIPMI config, which makes
  the OpenIPMI service load the module with the options in
  `IPMI_WATCHDOG_OPTIONS`. `watchdog_timeout` and `watchdog_module_options`
  are written there; when neither is set it keeps its value, such as the
  package's `timeout=60`. Puppet neither loads the module nor writes the
  modprobe.d and modules-load.d files, and removes them if they exist, so
  `watchdog_manage_module` has no effect. Nothing in this module opens the
  device, so the timer is started by whatever else does, such as the
  `watchdog` daemon. A drop-in written while systemd was the owner is
  removed.
* `auto`: `systemd` when systemd is the init system (the
  `ipmi_systemd_version` fact is present), unless its version is 250 or 251,
  and `openipmi` otherwise. `ipmi_watchdog` creates only `/dev/watchdog`.
  systemd up to 249 opens that path, and 252 onwards falls back to it when
  `/dev/watchdog0` does not exist, but 250 and 251 open `/dev/watchdog0` and
  nothing else.

Options:

* `watchdog_timeout` sets the module `timeout` option, in seconds, and under
  `systemd` also `RuntimeWatchdogSec`. The default, `0`, writes neither: the
  driver default of 10 seconds applies, and systemd keeps whatever
  `RuntimeWatchdogSec` the rest of its configuration sets, which is off unless
  something sets it. With no setting to write, the drop-in is not created.
  Set a non-zero value to have systemd arm the BMC watchdog.
* `watchdog_systemd_options` adds other `system.conf` [Manager] settings. A
  `RuntimeWatchdogSec` here replaces `watchdog_timeout`; `0` keeps systemd off
  the device on hardware with a buggy BMC watchdog. When PID 1 takes the
  device it sets the BMC timer to `RuntimeWatchdogSec`, so that value, not
  the module's `timeout` option, is the timeout from then on. Leave
  `WatchdogDevice` unset (see below).
* `watchdog_module_options` adds any other module option. Names are module
  parameter names, and values may not contain spaces, quotes or other
  characters a shell would interpret, because `IPMI_WATCHDOG_OPTIONS` is
  expanded unquoted by the OpenIPMI service. A Boolean is written as `1` or
  `0` and a whole Float as an integer, because the driver's integer
  parameters reject `true` and `60.0`; a fractional value is an error.
  Setting `timeout` here as well as a non-zero `watchdog_timeout` is an error
  unless the two values are the same number.
* `watchdog_manage_module => false` under `systemd` skips the module load and
  its options, for hosts where `/dev/watchdog` already exists.
  `watchdog_timeout` and `watchdog_module_options` then have no effect on the
  module.

```puppet
  class { 'ipmi':
    watchdog                => true,
    watchdog_supervisor     => 'auto',
    watchdog_timeout        => 60,
    watchdog_module_options => { 'action' => 'power_cycle' },
  }
```

Installing or upgrading the packages neither re-executes PID 1 nor restarts
a service, and changes to the module files or the drop-in do not restart the
`ipmi` or `ipmievd` services. Under `openipmi`, a change to the OpenIPMI
config restarts the `ipmi` service, as that service loads the module.
Module options only apply the next time the module is loaded, usually after a
reboot.

To turn the watchdog off:

* `watchdog => false` sets `IPMI_WATCHDOG=no` and removes the drop-in and
  both module files. Removing the drop-in re-executes PID 1, which disarms
  and closes the device before it re-executes; the new instance opens it
  again only if `RuntimeWatchdogSec` is set elsewhere.
* To keep the module loaded but stop PID 1 from arming the BMC, keep
  `watchdog => true` and set
  `watchdog_systemd_options => { 'RuntimeWatchdogSec' => 0 }`.
* Puppet never unloads the module: unloading it does not stop a running BMC
  timer, which would then reset the host because nothing could ping it. A
  loaded module stays loaded until the next boot, or until it is unloaded by
  hand (`modprobe -r ipmi_watchdog`) once nothing holds `/dev/watchdog`.

When upgrading from 8.x or earlier, where `watchdog => true` only set
`IPMI_WATCHDOG=yes`:

* `auto` now picks `systemd` on every supported release (EL8, EL9 and EL10,
  Debian 11, Ubuntu 20.04). Puppet then loads the module itself and forces
  `IPMI_WATCHDOG` to `no`, so `IPMI_WATCHDOG_OPTIONS`, and its package
  default of `timeout=60`, no longer applies: the module gets
  `watchdog_timeout` and `watchdog_module_options`, or the driver default of
  10 seconds. Set `watchdog_supervisor => 'openipmi'` to keep the OpenIPMI
  service in charge of the module as before.
* `watchdog => false`, the default, also removes the files listed above if
  they exist.
* A change to the OpenIPMI config restarts only the `ipmi` service, not
  `ipmievd`, and the private class `ipmi::config` is gone.

Which device PID 1 opens: `ipmi_watchdog` provides only the legacy
`/dev/watchdog` node. Unlike drivers built on the kernel's watchdog core, such
as `iTCO_wdt`, it has no `/dev/watchdogN` node and no `/sys/class/watchdog`
entry, so there is no other name to point `WatchdogDevice` at.

* While `ipmi_watchdog` holds `/dev/watchdog`, the kernel numbers other
  watchdog drivers from `/dev/watchdog1`, so `/dev/watchdog0` does not exist.
  With `WatchdogDevice` unset, systemd up to 249 opens `/dev/watchdog`, and
  252 and later fall back to it, so PID 1 opens the BMC's watchdog.
* `WatchdogDevice=/dev/watchdog0`, or any other `/dev/watchdogN`, names
  another driver, never the BMC. systemd 252 and later treat
  `/dev/watchdog` like an unset value, and 250 and 251 replace it with
  `/dev/watchdog0`.
* If another watchdog driver registers before `ipmi_watchdog`, it takes
  `/dev/watchdog` as well as `/dev/watchdog0`, and `ipmi_watchdog` gets no
  device at all (the kernel logs `Unable to register misc device`). No
  `WatchdogDevice` value reaches the BMC then; keep the other driver from
  loading, for example by blacklisting it.

PID 1 logs `Using hardware watchdog 'IPMI'` (`Hardware watchdog 'IPMI'` in
older releases such as 239) once it has opened the BMC's watchdog.

### Native Resources

The public API consists of the native Puppet types `ipmi_user`,
`ipmi_network`, and `ipmi_snmp`. The previous wrapper defined types
(`ipmi::user`, `ipmi::network`, `ipmi::snmp`) have been removed.

When upgrading from 8.x or earlier:

* `ipmi_user` takes `username`, not `user`.
* `ipmi_user`'s `user_id` now defaults to `'auto'`.
* `ipmi_user`'s username now defaults to the `namevar` rather than `root`.
* `ipmi::snmps` entries and `ipmi_snmp` take `community`, not `snmp`.
* `ip`, `netmask` or `gateway` together with `type => 'dhcp'` is rejected,
  and the error fails the whole agent run.
* `ipmi_network`'s `type` has no default. `ipmi::network` defaulted it to
  `dhcp`, so a network declared without `type`, directly or through
  `ipmi::networks`, switched its channel to DHCP. `ipmi_network` leaves the
  address source as the BMC has it. To keep switching to DHCP, set
  `type => 'dhcp'`.
* A static `ipmi_network` no longer defaults `netmask` to `255.255.255.0`
  or `gateway` to `0.0.0.0`; unset ones keep whatever the BMC holds.
* `ipmi::default_channel` applies only to resources declared through the
  `ipmi` class.
* `purge_id_mismatch` is now `ipmi_user`'s `purge_duplicates` (see below).
  It also applies to disabled users.
* A catalog that declares the same username twice on one channel, one
  explicit `user_id` for different usernames on any channel, one username
  with different explicit `user_id` values on any channels, or one username
  with a different `enable` or `password` on another channel, is rejected,
  as is an `ensure => absent` resource that would remove the slot a present
  one manages on any channel.

#### `ipmi_user`

```puppet
  # defaults
  ipmi_user { 'newuser':
    priv     => 4,           # Administrator
    user_id  => 'auto',      # auto-select a slot
    channel  => 1,
  }
```

When `enable => false`, the account is disabled, after its privilege is set
to `NO ACCESS` and its channel and SOL access removed on every LAN channel,
regardless of the `priv` value.  This makes disabled resources suitable for
reserving a slot ID without granting login access.  The resource is in sync
once the BMC reports the account disabled: `NO ACCESS` on its channel alone
still leaves any privilege on another channel, and SOL access.  When the BMC
cannot report it (`ipmitool` shows an `Enable Status` of `unknown`, or none),
it is in sync once no LAN channel grants the slot a privilege.

IPMI cannot delete a slot.  `ensure => absent` renames the slot to
`DISABLED_<id>`, after removing channel, privilege and SOL access on every LAN
channel and disabling the account.  A slot the BMC reports disabled with no
privilege on any LAN channel (for example a reserved `enable => false` user) is
only renamed.  BMCs do not allow permission changes on a disabled account, so
unless the BMC reports the account enabled, a refused permission change is
tolerated, but disabling the account must succeed; a BMC that refuses them
keeps a disabled slot's old privilege.  So a slot the BMC did not report
enabled is read again after the revoke, and while any LAN channel still grants
it a privilege it is not renamed: the resource fails, and the next run tries
again.  Slots with an empty or `DISABLED_*` name are treated as free unless the
BMC reports them enabled or any LAN channel grants them a privilege.

The password is never put on a command line, where other local users could
read it. `bmc-config` reads it from a mode 0600 temporary file, removed after
use, as its `Password` key, which stores a password of 17 to 20 bytes in the
IPMI 2.0 20-byte form, as `ipmitool` does; the BMC must support that form.
`bmc-config` compares a password of 16 bytes or fewer only in the 16-byte form,
so one the BMC holds in the 20-byte form is written once more.
`ipmitool` reads a password of 16 bytes or fewer at its own prompt, fed from
such a file; a password of 17 to 20 bytes goes through an `ipmitool exec`
batch file, whose parser cannot carry a `#`, a tab, a NUL byte, both kinds of
quote, or a `~` together with a space or quote, so such a password is
rejected. Neither backend accepts a password containing a newline or a NUL
byte, which would cut it short, and `bmc-config` does not accept one
containing whitespace.

The username does go on the command line, so it may not start with `-`, which
`ipmitool`'s option parser would take as an option of its own.

##### Channels

A user slot's name, password and enabled state are shared by every channel;
only its privilege and access are per channel. So the BMC's user table is read
once per run as one table: each slot's name and enabled state, and its
privilege on every LAN channel and every channel a resource names. Writes
update that table as they go; it is read again only before a slot is renamed:
to confirm that the slot does not hold the user already, and, after revoking a
slot the BMC did not report enabled, that no channel grants it a privilege.
A privilege of `NO ACCESS`, or none at all (`Unknown (0x00)` in
`ipmitool user list`), grants nothing.

`ipmitool` finds the LAN channels by probing channels 1 to 11, the only
numbers a LAN channel can have, with `ipmitool channel info`; a channel whose
medium is `802.3 LAN` or `Other LAN` counts, as for `ipmitool lan`.
`bmc-config` names its 802.3 LAN channels only when the BMC has more than one,
so with one LAN channel the `freeipmi` provider reads the channels resources
name. A probe that fails, other than for a channel the BMC does not have, or a
checkout that leaves out a LAN key, fails the `ipmi_user` resources: a channel
it missed would keep its access.

##### Slot allocation (`user_id => 'auto'`)

Slots are chosen from the BMC's current user table and the whole catalog, so
the result does not depend on resource evaluation order. User slots and names
are BMC-wide, so resources on every channel, and of every provider, are
allocated together, and `auto` resources with the same username on different
channels share one slot:

1. Explicit `user_id` values are reserved first.
1. An `auto` username that an explicit resource also declares takes that slot.
1. A user that already holds a slot keeps it (the lowest id if several that
   no explicit `user_id` names, including that of an `ensure => absent`
   resource for the same username, whose slot is retired instead).
1. The remaining `auto` resources, sorted by title, take the lowest free
   slots: empty or `DISABLED_*`, not reported enabled, and granted no
   privilege on any LAN channel.  Slot 1 (anonymous) is never allocated.
1. A resource that finds no free slot fails on its own; the others apply.

##### Removing duplicates (`purge_duplicates => true`)

Each other slot that holds the same username is blanked and disabled.  They
appear in the report as generated `ipmi_user` resources with
`ensure => absent` (titled `<title> (duplicate in slot <id>)`), run before the
resource that generated them, and honour `--noop`.

Slots managed by other resources in the catalog, on any channel, and slot 1
are never purged.

Puppet looks for duplicates before it applies anything. When `ipmitool` or
`bmc-config` is not installed yet (for example on the run that installs it),
or the BMC cannot be read, the purge is skipped with a notice or warning and
happens on a later run. Skipping the purge does not by itself fail the run.

##### Replacing or moving an account

An explicit `user_id` names the **slot to manage**, not an empty-slot
requirement. To replace or rename an account in slot 5, declare the new
`username` with `user_id => 5`, `enable => true`, and its new password. If the
old account is not disabled with no privilege anywhere, the provider first
revokes its channel, privilege and SOL access on every LAN channel and
disables it; only then does it rename the slot, set the new password and
enable the account. The former username is no longer in slot 5.
This deliberately replaces its access, so verify the slot and keep a separate
working BMC administrator before applying. Automatic allocation
(`user_id => 'auto'`) does not take a slot occupied by another username.

The slot is never renamed while the old account still has access. A username
or password the backend cannot write is refused before anything is written.
If a write fails after the old account is revoked, the slot is left disabled,
and the next run tries again.

A **disabled** user takes over the slot the same way. If `enable => false`
targets an explicit slot named for a different user, the provider revokes the
slot's channel and SOL access on every LAN channel while the account is still
enabled, disables it, and then renames the slot to the new username. The new
username is reserved there, and the next run is in sync. To disable an existing
account without renaming it, use its current username with the explicit slot.

```puppet
  ipmi_user { 'new_operator':
    user_id  => 5,
    password => Sensitive('new-secret'),
    priv     => 3,
  }
```

Moving an existing username to another explicit slot is different: set its
new `user_id` and `purge_duplicates => true` to revoke and rename any old
slot that still holds that username. Without `purge_duplicates`, the old
slot can remain enabled. A slot claimed by another resource in the catalog
is not purged. User slots are shared by every channel, so do not declare two
present resources for the same username on one channel, for one explicit
slot with different usernames on any channel, or for one username with
different explicit slots on any channels; such a catalog is rejected. To give
a user access on several channels, give each resource the same `user_id`, or
`auto`. Those resources are one account, so they must also agree on `enable`
and `password`, though one may leave the password out; only `priv` may differ
from channel to channel.
Test slot changes with `--noop` before applying.

To remove an old slot by hand instead, give the `ensure => absent` resource
that slot's explicit `user_id`. An `auto` resource for that username then
keeps another slot holding it, or takes a free one. An absent resource for
the same username as a present one, on any channel, is rejected when its
`user_id` is `auto`, or the same as the present resource's, because it would
remove the slot the present resource manages and the two would undo each
other on every run. Some such conflicts only show once the BMC's user table is
read, such as the slot an explicit `user_id` takes over from its old username.
The absent resource then fails with an error naming the resource that holds
the slot, and leaves the slot alone.

#### `ipmi_network`

```puppet
  ipmi_network { 'lan1':
    type        => 'dhcp',
    lan_channel => 1,
  }
```

A source other than DHCP or static (`BIOS Assigned Address`, `Unspecified`,
and so on) is reported as `other`, which never equals a managed `type`. The
resource therefore writes the desired source, and is in sync once the BMC
reports DHCP or static. A BMC that keeps reporting another source after the
write changes on every run.

#### `ipmi_snmp`

**Credential change:** If `community` is omitted, `ipmi_snmp` actively
sets the BMC SNMP community to `public`. Omission does not preserve the
existing value. Set `community` explicitly to avoid unintentionally
replacing a configured community string.

```puppet
  ipmi_snmp { 'lan1':
    community   => 'public',
    lan_channel => 1,
  }
```

`community` is always sensitive, so Puppet reports a change to it as
`changed [redacted] to [redacted]`. It may be given as `Sensitive('...')`,
but a plain string is redacted the same way. `ipmitool` prints the community
it sets, `ipmi-pef-config` names a value it refuses, and both print the
current community when they read it, so when a write or read fails, its error
shows `[redacted]` in its place. A failed password write is kept out of the
error the same way.

The community is never put on a command line, where other local users could
read it. `ipmitool` reads it from an `ipmitool exec` batch file and
`ipmi-pef-config` from a config file, each mode 0600 and removed after use.
So `ipmitool` rejects a community containing a `#`, whitespace other than a
space, a NUL byte, both kinds of quote, or a `~` together with a space or
quote, and `freeipmi` rejects one containing whitespace or a NUL byte.

A community is at most 18 bytes, the size of the BMC's community field, so a
multibyte character counts as each of its bytes. It may not start or end with
whitespace: both backends read the community back with that stripped, so such
a community would never be in sync.

`ipmitool` also rejects a community that starts with `help`. Its `lan set`
takes any value starting with `help` as a request for help: it prints its
usage and sets nothing, so such a community would never be applied.

## Additional Facts

This module provides IPMI facts for Facter, compatible with The Foreman's
BMC features, in two forms, and a systemd version fact for the watchdog:

### Structured Format

The `ipmi` fact is a nested hash, keyed by IPMI LAN channel number. The
first channel is also mirrored under the `default` key.

```text
ipmi => {
  default => {
    channel => 1,
    gateway => 192.168.10.1,
    ipaddress => 192.168.10.201,
    ipaddress_source => Static Address,
    macaddress => 00:30:48:c9:64:2a,
    subnet_mask => 255.255.255.0,
    users => {
      1 => {
        id => 1,
        name => '',
        privilege => 'NO ACCESS',
      },
      2 => {
        id => 2,
        name => 'admin',
        privilege => 'ADMINISTRATOR',
      }
    },
  },
  1 => {
    channel => 1,
    gateway => 192.168.10.1,
    ipaddress => 192.168.10.201,
    ipaddress_source => Static Address,
    macaddress => 00:30:48:c9:64:2a,
    subnet_mask => 255.255.255.0,
    users => {
      1 => {
        id => 1,
        name => '',
        privilege => 'NO ACCESS',
      },
      2 => {
        id => 2,
        name => 'admin',
        privilege => 'ADMINISTRATOR',
      }
    },
  },
}
```

### Flat Format

The address fields are also exposed as individual flat facts (prefixed
with `ipmi_`), for compatibility with The Foreman:

```text
ipmi_gateway => 192.168.10.1
ipmi_ipaddress => 192.168.10.201
ipmi_ipaddress_source => Static Address
ipmi_macaddress => 00:30:48:c9:64:2a
ipmi_subnet_mask => 255.255.255.0
```

### `ipmi_systemd_version`

The major version of systemd, as a string such as `252`, from
`systemctl --version`. It is reported only when systemd is the init system
(`/run/systemd/system` exists) and is what `watchdog_supervisor => 'auto'`
decides on.

## Limitations

At present, only support for RedHat and Debian distributions
has been implemented.

Adding other Linux distrubtions should be trivial.

### Scope and access

* **In-band only.** Providers talk to the local BMC through the kernel IPMI
  driver (`/dev/ipmi0`) and must run as root.  Remote (LAN/lanplus) access
  is not supported, so containers and VMs without the IPMI device cannot be
  managed.
* **Packages.** The `ipmi` class installs `OpenIPMI` and `ipmitool` only.
  The `freeipmi` providers also need the `freeipmi` package (`bmc-config`
  and `ipmi-pef-config`); install it yourself or add it to `ipmi::packages`.
* **First run.** A provider is unsuitable until its command exists.  A
  resource declared directly, without the `ipmi` class or an explicit
  `Package` ordering, may be skipped or fail on a host where the tool is
  installed in the same run (not covered by the tests).  Resources declared
  through the `ipmi` class are ordered after `ipmi::install`.
* **Tested hardware.** Parsers are covered by fixtures from Supermicro, ASUS
  and HP BMCs only.  Other vendors may format output differently.  Test on a
  non-production node first, and keep a working BMC login while doing so.

### Secrets

* **Command line exposure.** `ipmitool` and `bmc-config` receive passwords and
  SNMP community strings as arguments, so they are visible in the process
  table (`/proc/<pid>/cmdline`) to local users while the command runs.  Only
  Puppet's own logs and reports are redacted.
* **`community` is sensitive.** The `ipmi_snmp` `community` property is
  redacted in logs and reports.
* **Passwords cannot be read back.** Whether the password is current is
  tested with `ipmitool user test` or `bmc-config --diff`.  If that test
  fails for any reason, including a command error and not only a wrong
  password, the password is treated as different and rewritten on every run.
  A warning is logged when the check itself fails.
* **`password` is required** whenever `enable` is true, even for a user that
  already exists.  Passwords are at most 20 bytes; with `ipmitool`, 16 bytes
  or fewer use the 16 byte form.

### `freeipmi` backend

* Values containing whitespace (passwords, community strings, usernames) are
  rejected, because `bmc-config --key-pair` keeps only the first word.
* Reading users requires a full `bmc-config --checkout`.  If it exits with
  status 1 and the output is incomplete, the run fails instead of guessing.

### `ipmi_user`

* **User IDs are shared by the whole BMC; `channel` only selects where
  privileges and access are set.**  Uniqueness checks and `auto` allocation
  are made per `channel`.  Do not manage the same BMC with resources on
  different channels unless each uses a distinct explicit `user_id`, or two
  `auto` resources may be given the same free slot.  Access granted on
  other channels is not changed.
* A present and an absent resource for the same username with `user_id =>
  auto`, or for the same explicit slot, are rejected.  An absent resource for
  a different explicit slot is allowed.
* **No slot is ever deleted.**  `ensure => absent` renames the slot
  `DISABLED_<id>`; the slot's other state (for example a stale password)
  is not cleared.
* **IDs 2-63 are accepted**, but not checked against the BMC's real
  maximum.  A slot the BMC does not have is expected to fail when the tool
  rejects the write.
* **Enumeration.** `puppet resource ipmi_user` lists only the default
  channel (1), and only slots with a name that is not empty or `DISABLED_*`.
* **Cost.** With `ipmitool`, reading users runs one `channel getaccess` per
  named slot, on every run, on every channel in the catalog.
  `purge_duplicates` reads the user table again for each resource that sets
  it.

### `ipmi_network`

* IPv4 only.  Addresses are not checked for netmask validity or for whether
  the gateway lies on the subnet.
* **Do not change the address of the channel you reach the BMC through**
  unless you have another way in.  Writes are not verified or rolled back,
  and some BMCs may apply them after a delay.
* With `type` unset, `ip`, `netmask` and `gateway` are written as given
  even if the BMC is on DHCP.  A BMC may ignore or revert these writes,
  which would show as a change on every run.  Set `type` as well.
* When the resource switches to static, `ip`, `netmask` and `gateway` are
  re-checked and may be written once more after the first write, because
  some BMCs reload a stored address on a source change.

### `ipmi_snmp`

* A default `community` of `public` is applied when it is omitted (see
  above).
* The community string is at most 18 characters.

### Catalog failures

* The duplicate channel, username and slot checks (`pre_run_check`) run at
  apply time, not at catalog compile time, and a failure stops the whole
  run, so unrelated resources are not applied either.
* `ip`, `netmask` or `gateway` together with `type => 'dhcp'` is rejected
  when the catalog is built, which fails the agent run.

## Versioning

This module is versioned according to the [Semantic Versioning
2.0.0](http://semver.org/spec/v2.0.0.html) specification.

## Support

Please log tickets and issues at
[github](https://github.com/jhoblitt/puppet-ipmi/issues)

## Contributing

1. Fork it on github
1. Make a local clone of your fork
1. Create a topic branch.  Eg, `feature/mousetrap`
1. Make/commit changes
  * Commit messages should be in [imperative tense](http://git-scm.com/book/ch5-2.html)
  * Check that linter warnings or errors are not introduced - `bundle exec rake lint`
  * Check that `Rspec-puppet` unit tests are not broken and coverage is added for new
    features - `bundle exec rake spec`
  * Documentation of API/features is updated as appropriate in the README
  * If present, `beaker` acceptance tests should be run and potentially
    updated - `bundle exec rake beaker`
1. When the feature is complete, rebase / squash the branch history as
   necessary to remove "fix typo", "oops", "whitespace" and other trivial commits
1. Push the topic branch to github
1. Open a Pull Request (PR) from the *topic branch* onto parent repo's `master` branch

## See Also

* [OpenIPMI](http://openipmi.sourceforge.net/)
